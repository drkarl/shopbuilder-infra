#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./start_task.sh <github-issue-number>
#
# Example:
#   ./start_task.sh 1
#   ./start_task.sh 14

# --- Configurable bits ---
WORKTREES_DIR=".worktrees"       # Where worktrees live (relative to repo root)
BASE_BRANCH="main"               # Your default branch
ROLE_LABEL="Infrastructure"      # Just for prompt text
TMUX_SESSION="tasks"             # Shared tmux session for all task windows

IMPLEMENTER_AGENT_NAME="staff-engineer"   # For prompt text only
REVIEWER_AGENT_NAME="code-reviewer"       # For prompt text only

REVIEW_REQUEST_FILE=".ai/review.requested"
REVIEW_DONE_FILE=".ai/review.done"
AI_DIR=".ai"                     # Directory for AI workflow files (gitignored)
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

# Capture script directory before cd (BASH_SOURCE may be relative)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$REPO_ROOT"

# Check host dependencies
for cmd in git tmux claude gh jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: '$cmd' is not installed or not on PATH."
    exit 1
  fi
done

# Check Anthropic API key
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Error: ANTHROPIC_API_KEY environment variable is not set."
  echo "Claude Code CLI requires this to function."
  exit 1
fi

# Check GitHub authentication
# Prefer gh CLI's stored auth over GITHUB_TOKEN for better private repo access
if gh auth status &>/dev/null; then
  GH_LOGGED_USER=$(gh auth status 2>&1 | grep -oP 'Logged in to github.com account \K\S+' || true)
  if [[ -n "$GH_LOGGED_USER" ]]; then
    echo "Using gh CLI auth (logged in as '${GH_LOGGED_USER}')"
    # Unset token env vars so gh uses its stored auth
    unset GITHUB_TOKEN GH_TOKEN 2>/dev/null || true
  fi
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "Using GITHUB_TOKEN for authentication"
  export GH_TOKEN="${GITHUB_TOKEN}"
else
  echo "Warning: No GitHub authentication found."
  echo "   Run 'gh auth login' or set GITHUB_TOKEN."
  echo ""
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Fetch issue from GitHub
echo "Fetching GitHub issue #${ISSUE_NUMBER}..."

ISSUE_JSON="$(gh issue view "$ISSUE_NUMBER" --json title,body,state 2>/dev/null)" || {
  echo "Error: Could not fetch issue #${ISSUE_NUMBER} from GitHub."
  echo ""
  echo "Open issues:"
  gh issue list --limit 20 --state open
  exit 1
}

ISSUE_TITLE="$(echo "$ISSUE_JSON" | jq -r '.title')"
ISSUE_BODY="$(echo "$ISSUE_JSON" | jq -r '.body')"
ISSUE_STATE="$(echo "$ISSUE_JSON" | jq -r '.state')"

if [[ -z "$ISSUE_TITLE" || "$ISSUE_TITLE" == "null" ]]; then
  echo "Error: Could not extract title from issue #${ISSUE_NUMBER}."
  exit 1
fi

if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
  echo "Warning: Issue #${ISSUE_NUMBER} is closed."
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo "Issue #${ISSUE_NUMBER}: $ISSUE_TITLE"

# Branch & worktree names derived from issue number and title
SLUG="$(echo "${ISSUE_NUMBER}-${ISSUE_TITLE}" \
  | tr '[:upper:]' '[:lower:]' \
  | tr -cs 'a-z0-9' '-' \
  | sed 's/^-//;s/-$//' \
  | cut -c1-50)"

BRANCH_NAME="feature/${SLUG}"
WORKTREE_NAME="${SLUG}"
WORKTREE_PATH="${WORKTREES_DIR}/${WORKTREE_NAME}"
WINDOW_NAME="${SLUG}"
ABS_WORKTREE_PATH="${REPO_ROOT}/${WORKTREE_PATH}"

echo "Branch:        $BRANCH_NAME"
echo "Worktree path: $WORKTREE_PATH"
echo "tmux window:   ${TMUX_SESSION}:${WINDOW_NAME}"

mkdir -p "${WORKTREES_DIR}"

# Create branch if needed
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
  echo "Branch ${BRANCH_NAME} already exists."
else
  echo "Creating branch ${BRANCH_NAME} from ${BASE_BRANCH}..."
  if git show-ref --verify --quiet "refs/remotes/origin/${BASE_BRANCH}"; then
    git fetch origin "${BASE_BRANCH}" >/dev/null 2>&1 || true
    git branch "${BRANCH_NAME}" "origin/${BASE_BRANCH}"
  else
    git branch "${BRANCH_NAME}" "${BASE_BRANCH}"
  fi
fi

# Create worktree if not present
if [[ -d "$WORKTREE_PATH" ]]; then
  echo "Worktree directory already exists."
else
  echo "Adding worktree..."
  git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
fi

# Create .ai directory for workflow files
mkdir -p "${WORKTREE_PATH}/${AI_DIR}"

# Write task prompt inside worktree (for implementer)
TASK_PROMPT_FILE="${WORKTREE_PATH}/${AI_DIR}/.task-prompt.md"
cat > "$TASK_PROMPT_FILE" <<EOF
# Task: Implement ${ISSUE_TITLE} (${ROLE_LABEL}) — Agent: ${IMPLEMENTER_AGENT_NAME}

## Issue Details
**Title:** ${ISSUE_TITLE}
**GitHub Issue:** #${ISSUE_NUMBER}

${ISSUE_BODY}

## Role

You are acting as a **Staff Engineer implementer** (agent: "${IMPLEMENTER_AGENT_NAME}").
You own the technical execution of this issue end-to-end within this worktree and branch.

## Tech & Runtime Context (${ROLE_LABEL})

- Infrastructure as Code: Terraform >= 1.0
- Container Orchestration: Kubernetes
- Cloud Provider: AWS (primary)
- CI/CD: GitHub Actions / Woodpecker CI
- Typical commands:
  - Initialize: \`terraform init\`
  - Plan: \`terraform plan\`
  - Apply: \`terraform apply\`
  - Format: \`terraform fmt\`
  - Validate: \`terraform validate\`

Directory Structure:
- terraform/ - Terraform modules and configurations
  - modules/ - Reusable infrastructure modules
  - environments/ - Environment-specific configurations (dev, staging, prod)
- kubernetes/ - Kubernetes manifests
  - base/ - Base configurations
  - overlays/ - Environment-specific overlays
- docker/ - Docker configurations
- scripts/ - Deployment and utility scripts
- docs/ - Infrastructure documentation

Assumptions:
- This repo contains infrastructure as code, not application code.
- Changes should be backwards-compatible where possible.
- Sensitive values should use variables, not hardcoded values.
- Use existing patterns for module structure and naming.

## Constraints & Style

- Keep changes **small and focused** on this issue.
- Do not perform large refactors unless explicitly requested.
- Do not modify unrelated modules or environments.
- Always run \`terraform fmt\` before committing.
- Always run \`terraform validate\` to ensure valid syntax.
- Test in dev/staging before prod changes.
- Document any new variables or outputs in README files.
- When you complete the task, commit, push and create a PR using gh cli.
- Never add attribution or Co-Authored by on commits.
- When addressing code reviews, when possible, reply directly to the comment when you're defending why you don't agree with a comment, otherwise as a general PR comment.

## Required Steps

### Phase 1: Implementation

1. Understand the existing infrastructure related to this issue.
2. Design a minimal change that satisfies the requirements.
3. Implement the change in the relevant modules/environments only.
4. Run \`terraform fmt\` to format the code.
5. Run \`terraform validate\` to ensure valid syntax.
6. If possible, run \`terraform plan\` to preview changes.
7. Prepare one or more clear commits with meaningful messages.

### Phase 2: PR Creation

8. Push and create a PR:
   \`\`\`bash
   git push -u origin ${BRANCH_NAME}
   gh pr create --title "${ISSUE_TITLE}" --body "Closes #${ISSUE_NUMBER}" --base ${BASE_BRANCH}
   \`\`\`

9. Request Copilot review (if gh-copilot-review extension is installed):
   \`\`\`bash
   gh copilot-review <PR_NUMBER>
   \`\`\`
   If not installed, skip this step.

10. Create \`${REVIEW_REQUEST_FILE}\` with PR info to trigger the code-reviewer agent:
    \`\`\`bash
    cat > ${REVIEW_REQUEST_FILE} <<EOF
    PR_NUMBER=<PR_NUMBER>
    PR_URL=<PR_URL>
    NOTES=<any special notes for the reviewer>
    EOF
    \`\`\`

11. **Exit this session** by running \`/exit-session\` so the workflow can proceed to Phase 2 (waiting for code review).

### Phase 3: Address Code Reviews

**Note:** Phase 3 runs in a new Claude session after the code-reviewer posts feedback.

12. Fetch and read the review comments from GitHub:
    \`\`\`bash
    gh pr view <PR_NUMBER> --json reviews,comments
    \`\`\`

13. For each review comment:
    - If you **agree and will fix**: make the change, commit, push
    - If you **disagree or won't fix**: reply to the comment on GitHub explaining why:
      \`\`\`bash
      gh pr comment <PR_NUMBER> --body "Regarding [topic]: [your reasoning]"
      \`\`\`

14. After addressing all feedback, post a summary comment on the PR:
    \`\`\`bash
    gh pr comment <PR_NUMBER> --body "Addressed review feedback:
    - [x] Fixed: [description]
    - [x] Fixed: [description]
    - [ ] Not addressed: [description] - [reason]"
    \`\`\`

15. If changes were requested, the reviewer may do another pass. Repeat from step 12.

## Repository Info

- Branch: ${BRANCH_NAME}
- Base branch: ${BASE_BRANCH}
- Worktree path: ${WORKTREE_PATH}
EOF

echo "Wrote task prompt to ${TASK_PROMPT_FILE}"

# Copy workflow scripts from dev/ to worktree .ai/ directory
cp "${SCRIPT_DIR}/implementer.sh" "${WORKTREE_PATH}/${AI_DIR}/implementer.sh"
cp "${SCRIPT_DIR}/review-watcher.sh" "${WORKTREE_PATH}/${AI_DIR}/review-watcher.sh"
chmod +x "${WORKTREE_PATH}/${AI_DIR}/implementer.sh" "${WORKTREE_PATH}/${AI_DIR}/review-watcher.sh"

echo "Copied workflow scripts to ${AI_DIR}/"

# Check if window already exists in the tasks session
if tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  if tmux list-windows -t "${TMUX_SESSION}" -F '#{window_name}' | grep -q "^${WINDOW_NAME}$"; then
    echo "tmux window '${WINDOW_NAME}' already exists in session '${TMUX_SESSION}'."
    echo ""
    echo "Attach with:"
    echo "  tmux attach -t ${TMUX_SESSION}:${WINDOW_NAME}"
    echo ""
    read -p "Attach now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      tmux attach -t "${TMUX_SESSION}:${WINDOW_NAME}"
    fi
    exit 0
  fi
fi

echo "Starting tmux window with 3 panes (implementer + reviewer watcher + shell)..."

# Create session/window + 3-pane layout:
#   - Pane 0: implementer Claude
#   - Pane 1: reviewer watcher
#   - Pane 2: free shell
if ! tmux has-session -t "${TMUX_SESSION}" 2>/dev/null; then
  # New session with first window
  tmux new-session -d -s "${TMUX_SESSION}" -n "${WINDOW_NAME}" -c "${ABS_WORKTREE_PATH}"
else
  # New window in existing session
  tmux new-window -t "${TMUX_SESSION}" -n "${WINDOW_NAME}" -c "${ABS_WORKTREE_PATH}"
fi

# Pane 0 (left): Implementer (runs implementation, then watches for review and addresses feedback)
tmux send-keys -t "${TMUX_SESSION}:${WINDOW_NAME}.0" \
  "./${AI_DIR}/implementer.sh; echo ''; echo 'Implementer finished with code '\$?; exec \$SHELL" C-m

# Split horizontally: create Pane 1 on the right (50% width for reviewer watcher)
tmux split-window -h -p 50 -t "${TMUX_SESSION}:${WINDOW_NAME}.0" -c "${ABS_WORKTREE_PATH}"

# Split Pane 1 vertically to create Pane 2 (bottom-right) as a free shell
# Use 25% for the bottom pane (free shell), leaving 75% for reviewer watcher
tmux split-window -v -p 25 -t "${TMUX_SESSION}:${WINDOW_NAME}.1" -c "${ABS_WORKTREE_PATH}"

# Pane 1 (top-right): reviewer watcher
tmux send-keys -t "${TMUX_SESSION}:${WINDOW_NAME}.1" \
  "./${AI_DIR}/review-watcher.sh" C-m

# Pane 2 (bottom-right): idle shell for manual commands
tmux send-keys -t "${TMUX_SESSION}:${WINDOW_NAME}.2" \
  "echo 'Free shell for manual commands (terraform, kubectl, git, etc.)'; exec \$SHELL" C-m

# Select the implementer pane (pane 0) as the active pane
tmux select-pane -t "${TMUX_SESSION}:${WINDOW_NAME}.0"

echo ""
echo "================================================================"
echo "tmux window '${WINDOW_NAME}' created in session '${TMUX_SESSION}'"
echo ""
echo "Panes:"
echo "  0 (left):         Implementer (implements -> waits for review -> addresses feedback)"
echo "  1 (top-right):    Reviewer watcher (waits for ${REVIEW_REQUEST_FILE})"
echo "  2 (bottom-right): Free shell"
echo ""
echo "Key files in worktree (${WORKTREE_PATH}/${AI_DIR}/):"
echo "  .task-prompt.md        - Implementer instructions"
echo "  implementer.sh         - Implementer workflow script (running in pane 0)"
echo "  review-watcher.sh      - Reviewer watcher script (running in pane 1)"
echo "  review.requested       - Created by implementer after PR, triggers reviewer"
echo "  review.done            - Created by reviewer when done, triggers implementer phase 3"
echo ""
echo "Commands:"
echo "  Attach to session:          tmux attach -t ${TMUX_SESSION}"
echo "  Switch to this window:      tmux select-window -t ${TMUX_SESSION}:${WINDOW_NAME}"
echo "  Kill this window when done: tmux kill-window -t ${TMUX_SESSION}:${WINDOW_NAME}"
echo "  List all task windows:      tmux list-windows -t ${TMUX_SESSION}"
echo "================================================================"
echo ""

# Attach to the session/window
if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "${TMUX_SESSION}:${WINDOW_NAME}"
else
  tmux attach -t "${TMUX_SESSION}:${WINDOW_NAME}"
fi
