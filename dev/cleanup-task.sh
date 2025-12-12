#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./cleanup-task.sh <github-issue-number>
#
# Example:
#   ./cleanup-task.sh 1
#   ./cleanup-task.sh 14
#
# This script cleans up after a task is completed and PR is merged:
# - Kills the tmux window if still open
# - Removes the git worktree
# - Deletes the local branch
# - Optionally deletes the remote branch
#
# Note: GitHub issues close automatically when their PR is merged.

# --- Configurable bits (must match start_task.sh) ---
WORKTREES_DIR=".worktrees"
BASE_BRANCH="main"
TMUX_SESSION="tasks"
# --------------------------

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <github-issue-number>"
  echo ""
  echo "Open issues:"
  gh issue list --limit 20 --state open
  exit 1
fi

ISSUE_NUMBER="$1"

# Validate issue number is numeric
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: Issue number must be numeric, got: $ISSUE_NUMBER"
  exit 1
fi

# Ensure we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository."
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Check for gh CLI
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: 'gh' CLI is not installed or not on PATH."
  exit 1
fi

# Fetch issue title from GitHub to derive the slug
echo "Fetching GitHub issue #${ISSUE_NUMBER}..."

ISSUE_TITLE="$(gh issue view "$ISSUE_NUMBER" --json title --jq '.title' 2>/dev/null)" || {
  echo "Error: Could not fetch issue #${ISSUE_NUMBER} from GitHub."
  echo ""
  echo "Open issues:"
  gh issue list --limit 20 --state open
  exit 1
}

if [[ -z "$ISSUE_TITLE" || "$ISSUE_TITLE" == "null" ]]; then
  echo "Error: Could not extract title from issue #${ISSUE_NUMBER}."
  exit 1
fi

# Derive names (must match start_task.sh logic exactly)
SLUG="$(echo "${ISSUE_NUMBER}-${ISSUE_TITLE}" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9' '-' \
  | sed 's/^-//;s/-$//' \
  | cut -c1-50)"

BRANCH_NAME="feature/${SLUG}"
WORKTREE_NAME="${SLUG}"
WORKTREE_PATH="${WORKTREES_DIR}/${WORKTREE_NAME}"
WINDOW_NAME="${SLUG}"

echo "Cleaning up task: Issue #${ISSUE_NUMBER} - ${ISSUE_TITLE}"
echo ""
echo "Branch:        $BRANCH_NAME"
echo "Worktree path: $WORKTREE_PATH"
echo "tmux window:   ${TMUX_SESSION}:${WINDOW_NAME}"
echo ""

# Check if branch exists and if PR is merged
BRANCH_EXISTS=false
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
  BRANCH_EXISTS=true
fi

# Warn if branch still has unmerged commits
if $BRANCH_EXISTS; then
  # Check if branch is fully merged into base branch
  git fetch origin "${BASE_BRANCH}" >/dev/null 2>&1 || true
  UNMERGED_COMMITS=$(git log "origin/${BASE_BRANCH}..${BRANCH_NAME}" --oneline 2>/dev/null | wc -l || echo "0")
  if [[ "$UNMERGED_COMMITS" -gt 0 ]]; then
    echo "Warning: Branch '${BRANCH_NAME}' has ${UNMERGED_COMMITS} unmerged commit(s)."
    echo "   Make sure the PR is merged before cleaning up."
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
fi

# 1. Kill tmux window if it exists
echo "Checking tmux window..."
if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  if tmux list-windows -t "${TMUX_SESSION}" -F '#{window_name}' | grep -q "^${WINDOW_NAME}$"; then
    echo "   Killing tmux window '${WINDOW_NAME}'..."
    tmux kill-window -t "${TMUX_SESSION}:${WINDOW_NAME}" 2>/dev/null || true
    echo "   Window killed."
  else
    echo "   Window not found (already closed)."
  fi
else
  echo "   Session '${TMUX_SESSION}' not found (no windows to kill)."
fi

# 2. Remove worktree
echo ""
echo "Checking worktree..."
if [[ -d "$WORKTREE_PATH" ]]; then
  echo "   Removing worktree at '${WORKTREE_PATH}'..."
  git worktree remove --force "$WORKTREE_PATH" 2>/dev/null || {
    echo "   git worktree remove failed, trying manual cleanup..."
    rm -rf "$WORKTREE_PATH"
    git worktree prune
  }
  echo "   Worktree removed."
else
  echo "   Worktree not found (already removed)."
fi

# Prune any stale worktree references
git worktree prune 2>/dev/null || true

# 3. Delete local branch
echo ""
echo "Checking local branch..."
if $BRANCH_EXISTS; then
  echo "   Deleting local branch '${BRANCH_NAME}'..."
  git branch -D "$BRANCH_NAME" 2>/dev/null || {
    echo "   Could not delete branch (may be checked out elsewhere)."
  }
  echo "   Local branch deleted."
else
  echo "   Local branch not found (already deleted)."
fi

# 4. Optionally delete remote branch
echo ""
echo "Checking remote branch..."
if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH_NAME}"; then
  echo "   Remote branch 'origin/${BRANCH_NAME}' exists."
  read -p "   Delete remote branch? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git push origin --delete "$BRANCH_NAME" 2>/dev/null || {
      echo "   Could not delete remote branch (may already be deleted or no permission)."
    }
    echo "   Remote branch deleted."
  else
    echo "   Skipped remote branch deletion."
  fi
else
  echo "   Remote branch not found (already deleted or never pushed)."
fi

echo ""
echo "================================================================"
echo "Cleanup complete for issue #${ISSUE_NUMBER}"
echo ""
echo "Summary:"
echo "  - tmux window: killed (if existed)"
echo "  - Worktree: removed"
echo "  - Local branch: deleted"
echo ""
echo "Note: GitHub issue will close automatically when its PR is merged."
echo "================================================================"
