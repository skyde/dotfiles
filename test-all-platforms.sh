#!/usr/bin/env bash
set -euo pipefail

# GitHub repository and workflow monitoring script
REPO=${REPO:-"skyde/dotfiles"}
BRANCH=${BRANCH:-"$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'main')"}
WORKFLOW_FILE=${WORKFLOW_FILE:-"comprehensive-test.yml"}
ALLOW_DIRTY=0
STATUS_ONLY=0

echo "=== MULTI-PLATFORM TESTING AUTOMATION ==="
echo "Repository: $REPO"
echo "Branch: $BRANCH"
echo "Workflow: $WORKFLOW_FILE"
echo ""

usage() {
    echo "Usage: $0 [number_of_cycles] [options]"
    echo ""
    echo "This script triggers and monitors GitHub Actions workflows"
    echo "to test dotfiles installation across all platforms:"
    echo "  - Linux (Ubuntu)"
    echo "  - macOS (latest)"
    echo "  - Windows (latest)"
    echo ""
    echo "Options:"
    echo "  number_of_cycles      Number of test cycles to run (default: 3)"
    echo "  --workflow FILE       Workflow file to run (default: comprehensive-test.yml)"
    echo "  --branch BRANCH       Remote branch/ref to run (default: current branch)"
    echo "  --repo OWNER/REPO     GitHub repository (default: skyde/dotfiles)"
    echo "  --status-only         Show latest workflow status without triggering a run"
    echo "  --allow-dirty         Continue with a dirty tree, testing only the remote ref"
    echo "  --help, -h            Show this help message"
    echo ""
    echo "The script never stages, commits, or pushes local changes. Commit and push"
    echo "your work first if you want the remote workflow to test those changes."
}

# Function to check if gh is authenticated
check_gh_auth() {
    command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
}

# Function to trigger workflow using GitHub CLI
trigger_workflow_gh() {
    if ! check_gh_auth; then
        echo "GitHub CLI authentication is required to trigger workflows safely." >&2
        echo "Run 'gh auth login', or use --status-only to inspect the latest run." >&2
        return 1
    fi

    gh workflow view "$WORKFLOW_FILE" --repo "$REPO" >/dev/null
    echo "Triggering workflow via GitHub CLI..."
    gh workflow run "$WORKFLOW_FILE" --repo "$REPO" --ref "$BRANCH"
}

# Function to get workflow status using GitHub API
get_workflow_status() {
    echo "Fetching workflow status..."

    # Get latest workflow runs
    if check_gh_auth; then
        gh run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --branch "$BRANCH" --limit 1 --json status,conclusion,url,createdAt
    else
        echo "ℹ GitHub CLI not authenticated - using public API"
        # Use curl to access public GitHub API
        curl -s "https://api.github.com/repos/$REPO/actions/workflows" | \
        python3 -c "
import json, sys
data = json.load(sys.stdin)
for wf in data.get('workflows', []):
    if '$WORKFLOW_FILE' in wf['path']:
        print(f'Workflow ID: {wf[\"id\"]}')
        break
" 2>/dev/null || echo "Could not fetch workflow info via API"
    fi
}

# Function to monitor workflow results
monitor_workflow() {
    local max_wait=600  # 10 minutes max wait
    local wait_time=0
    local check_interval=30

    echo "Monitoring workflow progress..."

    if ! check_gh_auth; then
        echo "Cannot monitor workflow runs without GitHub CLI authentication." >&2
        return 1
    fi

    while [ $wait_time -lt $max_wait ]; do
        echo "Checking status... (${wait_time}s elapsed)"

        # Get the latest run status
        local status
        status=$(gh run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --branch "$BRANCH" --limit 1 --json status,conclusion --jq '.[0] | [.status, .conclusion] | @tsv' 2>/dev/null || true)

        if [ -n "$status" ]; then
            local run_status
            local conclusion
            IFS=$'\t' read -r run_status conclusion <<< "$status"

            echo "Status: $run_status, Conclusion: $conclusion"

            if [ "$run_status" = "completed" ]; then
                if [ "$conclusion" = "success" ]; then
                    echo "✅ Workflow completed successfully!"
                    return 0
                else
                    echo "❌ Workflow failed with conclusion: $conclusion"
                    return 1
                fi
            fi
        fi

        sleep $check_interval
        wait_time=$((wait_time + check_interval))
    done

    echo "⏰ Monitoring timeout reached"
    return 2
}

# Function to run comprehensive platform tests
run_platform_tests() {
    local test_count=${1:-3}
    local success_count=0

    if ! [[ "$test_count" =~ ^[0-9]+$ ]] || [ "$test_count" -lt 1 ]; then
        echo "number_of_cycles must be a positive integer" >&2
        return 2
    fi

    echo "=== RUNNING $test_count PLATFORM TEST CYCLES ==="

    for i in $(seq 1 "$test_count"); do
        echo ""
        echo "🚀 TEST CYCLE $i/$test_count"
        echo "===================="

        # Trigger the workflow
        trigger_workflow_gh

        echo "Waiting 60 seconds for workflow to start..."
        sleep 60

        # Monitor the results
        if monitor_workflow; then
            echo "✅ Test cycle $i completed successfully"
            success_count=$((success_count + 1))
        else
            echo "❌ Test cycle $i failed"
        fi

        # Wait between cycles if not the last one
        if [ "$i" -lt "$test_count" ]; then
            echo "Waiting 120 seconds before next cycle..."
            sleep 120
        fi
    done

    echo ""
    echo "=== FINAL RESULTS ==="
    echo "Successful cycles: $success_count/$test_count"
    echo "Success rate: $(( success_count * 100 / test_count ))%"

    if [ "$success_count" -eq "$test_count" ]; then
        echo "🎉 ALL PLATFORM TESTS PASSED!"
        return 0
    else
        echo "⚠️  Some platform tests failed"
        return 1
    fi
}

# Main execution
main() {
    local cycles="$1"
    local status

    echo "Checking current repository status..."
    status="$(git status --porcelain)"
    printf '%s\n' "$status"

    if [ -n "$status" ] && [ "$ALLOW_DIRTY" -ne 1 ]; then
        echo "Working directory is not clean." >&2
        echo "Commit and push your work first, or pass --allow-dirty to test the current remote ref anyway." >&2
        return 2
    elif [ -n "$status" ]; then
        echo "⚠️  Dirty tree allowed; workflow will test remote ref '$BRANCH', not these local changes."
    fi

    echo ""
    if check_gh_auth; then
        echo "✓ GitHub CLI authenticated"
    else
        echo "ℹ GitHub CLI not authenticated"
    fi

    get_workflow_status
    echo ""

    if [ "$STATUS_ONLY" -eq 1 ]; then
        return 0
    fi

    run_platform_tests "$cycles"
}

cycles=3
cycles_set=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --workflow)
            WORKFLOW_FILE=${2:?--workflow requires a file name}
            shift 2
            ;;
        --branch)
            BRANCH=${2:?--branch requires a branch/ref}
            shift 2
            ;;
        --repo)
            REPO=${2:?--repo requires OWNER/REPO}
            shift 2
            ;;
        --status-only)
            STATUS_ONLY=1
            shift
            ;;
        --allow-dirty)
            ALLOW_DIRTY=1
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [ "$cycles_set" -eq 1 ]; then
                echo "Unexpected argument: $1" >&2
                usage >&2
                exit 2
            fi
            cycles=$1
            cycles_set=1
            shift
            ;;
    esac
done

# Run main function with arguments
main "$cycles"
