#!/bin/bash
# Trigger and watch the hosted cross-platform test workflow without modifying the repository.
set -euo pipefail

REPO="${DOTFILES_REPO:-skyde/dotfiles}"
WORKFLOW_FILE="${DOTFILES_WORKFLOW:-comprehensive-test.yml}"
BRANCH="${DOTFILES_BRANCH:-$(git branch --show-current 2>/dev/null || true)}"

usage() {
    cat <<USAGE
Usage: $0 [number_of_cycles]

Triggers $WORKFLOW_FILE on GitHub Actions and waits for each run to finish.
Environment overrides:
  DOTFILES_REPO       Repository in owner/name form (default: $REPO)
  DOTFILES_BRANCH     Remote branch to test (default: current branch)
  DOTFILES_WORKFLOW   Workflow file (default: $WORKFLOW_FILE)
USAGE
}

latest_run_id() {
    gh run list \
        --repo "$REPO" \
        --workflow "$WORKFLOW_FILE" \
        --branch "$BRANCH" \
        --event workflow_dispatch \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId // empty'
}

wait_for_new_run() {
    local previous_id="$1"
    local attempt run_id

    for attempt in $(seq 1 30); do
        run_id="$(latest_run_id)"
        if [ -n "$run_id" ] && [ "$run_id" != "$previous_id" ]; then
            printf '%s\n' "$run_id"
            return 0
        fi
        sleep 2
    done

    echo "Timed out waiting for the workflow run to appear." >&2
    return 1
}

main() {
    local cycles="${1:-3}"
    local cycle previous_id run_id

    if ! [[ "$cycles" =~ ^[1-9][0-9]*$ ]]; then
        echo "number_of_cycles must be a positive integer." >&2
        return 2
    fi

    if [ -z "$BRANCH" ]; then
        echo "No current branch detected; set DOTFILES_BRANCH explicitly." >&2
        return 2
    fi

    if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI authentication is required: gh auth login" >&2
        return 1
    fi

    if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then
        echo "Warning: local changes are not part of the remote workflow run." >&2
    fi

    echo "Repository: $REPO"
    echo "Branch: $BRANCH"
    echo "Workflow: $WORKFLOW_FILE"

    for cycle in $(seq 1 "$cycles"); do
        echo "=== Test cycle $cycle/$cycles ==="
        previous_id="$(latest_run_id)"
        gh workflow run "$WORKFLOW_FILE" --repo "$REPO" --ref "$BRANCH"
        run_id="$(wait_for_new_run "$previous_id")"
        gh run watch "$run_id" --repo "$REPO" --exit-status
    done

    echo "✅ All $cycles hosted test cycle(s) passed"
}

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
esac

main "$@"
