#!/usr/bin/env bash
set -euo pipefail

# Implementer workflow script - runs in 3 phases:
#   Phase 1: Implementation (run Claude with task prompt)
#   Phase 2: Wait for code review (watch for review.done)
#   Phase 3: Address review feedback (run Claude to fix issues)
#
# Smart resume: automatically skips to appropriate phase based on existing files.
# Run this script again after exiting Claude to continue the workflow.

AI_DIR=".ai"
REVIEW_REQUEST_FILE="${AI_DIR}/review.requested"
REVIEW_DONE_FILE="${AI_DIR}/review.done"
TASK_PROMPT_FILE="${AI_DIR}/.task-prompt.md"

# Cleanup handler
cleanup() {
  echo ""
  echo "Implementer interrupted."
  echo "   Run ./implementer.sh again to resume from current phase."
  exit 0
}
trap cleanup INT TERM

# Helper: wait for a file to appear
wait_for_file() {
  local target_file="$1"

  if command -v inotifywait >/dev/null 2>&1; then
    echo "   Using inotifywait for efficient file watching..."
    while [[ ! -f "${target_file}" ]]; do
      inotifywait -qq -e create -e moved_to -t 60 "${AI_DIR}" 2>/dev/null || true
    done
  else
    echo "   Polling for ${target_file}..."
    while [[ ! -f "${target_file}" ]]; do
      sleep 5
    done
  fi
}

# Helper: run Phase 3 (address review feedback)
run_phase3() {
  local pr_number="$1"
  echo "Phase 3: Addressing review feedback"
  echo ""

  claude --dangerously-skip-permissions "## Address Code Review Feedback

The code-reviewer has completed their review of PR #${pr_number}.

### Instructions

1. Fetch the review comments from GitHub:
   gh pr view ${pr_number} --json reviews,comments

2. Read through each comment carefully.

3. For each comment:
   - If you agree: make the fix, commit with message 'Address review: <description>'
   - If you disagree: reply on GitHub explaining why:
     gh pr comment ${pr_number} --body 'Regarding [topic]: [your reasoning]'

4. After addressing all feedback, post a summary on the PR:
   gh pr comment ${pr_number} --body 'Addressed review feedback:
   - [x] Fixed: <item>
   - [ ] Not addressed: <item> - <reason>'

5. Push your changes: git push

6. If the reviewer requested changes, they may review again. Check for updates."

  echo ""
  echo "Review feedback addressed."
}

# Determine current phase based on existing files
echo "Checking workflow state..."
echo ""

# Check for task prompt
if [[ ! -f "${TASK_PROMPT_FILE}" ]]; then
  echo "Error: ${TASK_PROMPT_FILE} not found."
  echo "   This script should be run from a worktree created by start_task.sh"
  exit 1
fi

# If review.done exists, go straight to Phase 3
if [[ -f "${REVIEW_DONE_FILE}" ]]; then
  PR_NUMBER="$(grep -oP '^PR_NUMBER=\K.*' "${REVIEW_REQUEST_FILE}" 2>/dev/null || true)"
  if [[ -z "${PR_NUMBER}" ]]; then
    echo "review.done exists but could not extract PR_NUMBER"
    exit 1
  fi
  REVIEW_VERDICT="$(grep -oP '^VERDICT=\K.*' "${REVIEW_DONE_FILE}" 2>/dev/null || echo "unknown")"
  echo "Found ${REVIEW_DONE_FILE} (verdict: ${REVIEW_VERDICT})"
  echo "   Skipping to Phase 3..."
  echo ""
  run_phase3 "${PR_NUMBER}"
  echo ""
  echo "Implementer workflow complete."
  exit 0
fi

# If review.requested exists, skip to Phase 2
if [[ -f "${REVIEW_REQUEST_FILE}" ]]; then
  PR_NUMBER="$(grep -oP '^PR_NUMBER=\K.*' "${REVIEW_REQUEST_FILE}" 2>/dev/null || true)"
  if [[ -z "${PR_NUMBER}" ]]; then
    echo "review.requested exists but could not extract PR_NUMBER"
    exit 1
  fi
  echo "Found ${REVIEW_REQUEST_FILE} (PR #${PR_NUMBER})"
  echo "   Skipping Phase 1, going to Phase 2..."
  echo ""
else
  # Phase 1: Implementation
  echo "Phase 1: Implementation"
  echo ""

  claude --dangerously-skip-permissions "$(cat ${TASK_PROMPT_FILE})"

  echo ""
  echo "Implementation phase complete."
  echo ""

  # Check if PR was created
  if [[ ! -f "${REVIEW_REQUEST_FILE}" ]]; then
    echo "No ${REVIEW_REQUEST_FILE} found - PR may not have been created yet."
    echo "   Run ./implementer.sh again after creating the PR."
    exit 0
  fi

  PR_NUMBER="$(grep -oP '^PR_NUMBER=\K.*' "${REVIEW_REQUEST_FILE}" 2>/dev/null || true)"
  if [[ -z "${PR_NUMBER}" ]]; then
    echo "Could not extract PR_NUMBER from ${REVIEW_REQUEST_FILE}"
    exit 0
  fi
fi

# Phase 2: Wait for review
echo "Phase 2: Waiting for code review..."
echo "   PR #${PR_NUMBER} created. Watching for '${REVIEW_DONE_FILE}'..."
echo ""

wait_for_file "${REVIEW_DONE_FILE}"

echo ""
echo "Found ${REVIEW_DONE_FILE}. Code review complete!"
echo ""

REVIEW_VERDICT="$(grep -oP '^VERDICT=\K.*' "${REVIEW_DONE_FILE}" 2>/dev/null || echo "unknown")"
echo "   Review verdict: ${REVIEW_VERDICT}"
echo ""

# Phase 3: Address feedback
run_phase3 "${PR_NUMBER}"

echo ""
echo "Implementer workflow complete."
