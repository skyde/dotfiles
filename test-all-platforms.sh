#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./test-all-platforms.sh [cycles] [options]

Dispatch and watch the comprehensive GitHub Actions workflow.

Options:
  --workflow FILE   Workflow file (default: comprehensive-test.yml)
  --branch REF      Branch or ref (default: current branch, or main if detached)
  --repo OWNER/REPO Repository (default: skyde/dotfiles)
  --status-only     Show the latest run without dispatching
  --allow-dirty     Test the remote ref even if the local tree is dirty
  -h, --help        Show this help

This script never stages, commits, or pushes local changes.
EOF
}

current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
REPO=${REPO:-skyde/dotfiles}
BRANCH=${BRANCH:-${current_branch:-main}}
WORKFLOW_FILE=${WORKFLOW_FILE:-comprehensive-test.yml}
cycles=1
cycles_set=false
status_only=false
allow_dirty=false

while (($# > 0)); do
  case "$1" in
    --workflow)
      WORKFLOW_FILE=${2:?--workflow requires a file}
      shift 2
      ;;
    --branch)
      BRANCH=${2:?--branch requires a ref}
      shift 2
      ;;
    --repo)
      REPO=${2:?--repo requires OWNER/REPO}
      shift 2
      ;;
    --status-only)
      status_only=true
      shift
      ;;
    --allow-dirty)
      allow_dirty=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if $cycles_set; then
        echo "Unexpected argument: $1" >&2
        usage >&2
        exit 2
      fi
      cycles=$1
      cycles_set=true
      shift
      ;;
  esac
done

if ! [[ "$cycles" =~ ^[1-9][0-9]*$ ]]; then
  echo "cycles must be a positive integer" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required: https://cli.github.com/" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Authenticate GitHub CLI first with 'gh auth login'." >&2
  exit 1
fi

if ! $status_only && ! $allow_dirty && [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty; commit and push first, or pass --allow-dirty." >&2
  exit 2
fi

gh workflow view "$WORKFLOW_FILE" --repo "$REPO" >/dev/null

echo "Repository: $REPO"
echo "Branch/ref: $BRANCH"
echo "Workflow: $WORKFLOW_FILE"

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

show_latest_run() {
  gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW_FILE" \
    --branch "$BRANCH" \
    --limit 1 \
    --json databaseId,status,conclusion,url,createdAt,workflowName
}

verify_remote_head() {
  # An explicitly selected remote ref may intentionally differ from local HEAD.
  if [[ -z "$current_branch" || "$BRANCH" != "$current_branch" ]]; then
    return
  fi

  local local_sha
  local remote_sha
  local_sha="$(git rev-parse HEAD)"
  remote_sha="$(
    gh api --method GET "repos/$REPO/commits" -f "sha=$BRANCH" -f per_page=1 --jq '.[0].sha'
  )"

  if [[ -z "$remote_sha" || "$remote_sha" != "$local_sha" ]]; then
    echo "Remote '$REPO:$BRANCH' does not match local HEAD." >&2
    echo "Push commit $local_sha before dispatching this workflow." >&2
    exit 2
  fi
}

wait_for_new_run() {
  local previous_id="$1"
  local current_id
  local attempt

  for attempt in {1..60}; do
    current_id="$(latest_run_id)"
    if [[ -n "$current_id" && "$current_id" != "$previous_id" ]]; then
      printf '%s\n' "$current_id"
      return 0
    fi
    if ((attempt % 10 == 0)); then
      echo "Still waiting for the dispatched run..." >&2
    fi
    sleep 2
  done

  echo "Timed out waiting for the dispatched workflow run to appear." >&2
  return 1
}

if $status_only; then
  show_latest_run
  exit 0
fi

verify_remote_head

for ((cycle = 1; cycle <= cycles; cycle++)); do
  echo
  echo "Dispatching cycle $cycle/$cycles..."

  previous_id="$(latest_run_id)"
  gh workflow run "$WORKFLOW_FILE" --repo "$REPO" --ref "$BRANCH"

  run_id="$(wait_for_new_run "$previous_id")"
  echo "Watching run $run_id"
  gh run watch "$run_id" --repo "$REPO" --exit-status

  gh run view "$run_id" \
    --repo "$REPO" \
    --json databaseId,status,conclusion,url,createdAt,workflowName
done
