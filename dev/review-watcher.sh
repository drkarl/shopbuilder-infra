#!/usr/bin/env bash
set -euo pipefail

# Review watcher script - waits for review.requested then runs code review
#
# Workflow:
#   1. Wait for review.requested file (created by implementer after PR)
#   2. Run Claude as code-reviewer to review the PR
#   3. Post review to GitHub
#   4. Create review.done file to signal implementer

AI_DIR=".ai"
REVIEW_REQUEST_FILE="${AI_DIR}/review.requested"
REVIEW_DONE_FILE="${AI_DIR}/review.done"

# Cleanup handler
cleanup() {
  echo ""
  echo "Reviewer watcher interrupted."
  exit 0
}
trap cleanup INT TERM

echo "Reviewer watcher started."
echo "   Waiting for '${REVIEW_REQUEST_FILE}' to appear in $(pwd)..."
echo ""

# Wait for review request file using inotifywait if available, otherwise poll
wait_for_file() {
  local target_file="$1"

  if command -v inotifywait >/dev/null 2>&1; then
    echo "   Using inotifywait for efficient file watching..."
    while [[ ! -f "${target_file}" ]]; do
      inotifywait -qq -e create -e moved_to -t 60 "${AI_DIR}" 2>/dev/null || true
    done
  else
    echo "   inotifywait not found, falling back to polling (install inotify-tools for efficiency)..."
    while [[ ! -f "${target_file}" ]]; do
      sleep 5
    done
  fi
}

wait_for_file "${REVIEW_REQUEST_FILE}"

# Robust file reading with retry (race condition protection)
REVIEW_CONTEXT=""
for attempt in 1 2 3; do
  if REVIEW_CONTEXT="$(cat "${REVIEW_REQUEST_FILE}" 2>/dev/null)" && [[ -n "${REVIEW_CONTEXT}" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "${REVIEW_CONTEXT}" ]]; then
  echo "Error: Could not read ${REVIEW_REQUEST_FILE} after multiple attempts."
  exit 1
fi

echo "Found ${REVIEW_REQUEST_FILE}. Reading review context..."
echo ""

# Extract PR number if available for gh commands
PR_NUMBER="$(grep -oP '^PR_NUMBER=\K.*' "${REVIEW_REQUEST_FILE}" 2>/dev/null || true)"
PR_URL="$(grep -oP '^PR_URL=\K.*' "${REVIEW_REQUEST_FILE}" 2>/dev/null || true)"

echo "Starting Claude in code-reviewer mode..."
echo ""

# The code-reviewer agent definition contains the full review methodology.
# This prompt provides only the task-specific context.
claude --dangerously-skip-permissions "## Code Review Request

You are reviewing a pull request as the **code-reviewer** agent.

### PR Context
${REVIEW_CONTEXT}

### Instructions

1. Fetch the PR information and diff:
   gh pr view ${PR_NUMBER} --json title,body,files,additions,deletions
   gh pr diff ${PR_NUMBER}

2. Perform a thorough code review following your standard review process:
   - Security scan first: Hardcoded secrets, exposed credentials, insecure configurations
   - Correctness: Logic bugs, edge cases, error handling
   - Consistency: Alignment with existing codebase patterns
   - IaC specific: Check for proper variable usage, module structure, state management

3. Post your review to GitHub using gh pr review:
   - To approve: gh pr review ${PR_NUMBER} --approve --body \"Your review text\"
   - To request changes: gh pr review ${PR_NUMBER} --request-changes --body \"Your review text\"
   - To comment only: gh pr review ${PR_NUMBER} --comment --body \"Your review text\"

4. After posting the review, write status to '${REVIEW_DONE_FILE}':
   echo 'STATUS=done' > ${REVIEW_DONE_FILE}
   echo 'PR_NUMBER=${PR_NUMBER}' >> ${REVIEW_DONE_FILE}
   echo 'VERDICT=approve or request-changes or comment' >> ${REVIEW_DONE_FILE}

IMPORTANT: You MUST post your review to GitHub. The implementer reads feedback from GitHub, not terminal output."

echo ""
echo "Review session finished."

# Fallback: ensure review.done exists even if Claude didn't create it
if [[ ! -f "${REVIEW_DONE_FILE}" ]]; then
  cat > "${REVIEW_DONE_FILE}" <<DONE_EOF
STATUS=done
COMPLETED_AT=$(date -Iseconds)
DONE_EOF
  echo "Wrote ${REVIEW_DONE_FILE} to signal review completion."
else
  echo "${REVIEW_DONE_FILE} already created by reviewer."
fi
