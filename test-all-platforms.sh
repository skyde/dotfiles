#!/bin/bash
set -e

# Handled before anything else, so `--help` never depends on the repository
# state or on the workflow existing.
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Usage: $0 [number_of_cycles]"
    echo ""
    echo "This script triggers and monitors GitHub Actions workflows"
    echo "to test dotfiles installation across all platforms:"
    echo "  - Linux (Ubuntu)"
    echo "  - macOS (latest)"
    echo "  - Windows (latest)"
    echo ""
    echo "Options:"
    echo "  number_of_cycles  Number of test cycles to run (default: 3)"
    echo "  --help, -h        Show this help message"
    echo ""
    echo "Environment:"
    echo "  DOTFILES_WORKFLOW  Workflow to run (default: comprehensive-test.yml)"
    echo "  DOTFILES_BRANCH    Branch to trigger on (default: the current branch)"
    echo "  DOTFILES_REPO      owner/name (default: skyde/dotfiles)"
    echo ""
    echo "Requires a clean working tree: CI tests what is pushed, not what is local."
    echo ""
    echo "Examples:"
    echo "  $0              # Run 3 test cycles"
    echo "  $0 5            # Run 5 test cycles"
    exit 0
fi

# GitHub repository and workflow monitoring script
REPO="${DOTFILES_REPO:-skyde/dotfiles}"

# The branch to trigger on, defaulting to whichever one is checked out. It used
# to be hard-coded to "main", which is how this script came to push to main from
# whatever branch you happened to be on (see main() below).
BRANCH="${DOTFILES_BRANCH:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)}"

# There is no simple-test.yml in this repository and there never has been, so
# every `gh workflow run` and `gh run list` this script made was against a
# workflow that does not exist. Default to one that does, and check before
# doing anything rather than failing halfway through a cycle.
WORKFLOW_FILE="${DOTFILES_WORKFLOW:-comprehensive-test.yml}"

script_dir="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$script_dir/.github/workflows/$WORKFLOW_FILE" ]; then
    echo "❌ No such workflow: .github/workflows/$WORKFLOW_FILE" >&2
    echo "   Available:" >&2
    for wf in "$script_dir"/.github/workflows/*.yml; do
        [ -e "$wf" ] && echo "     $(basename "$wf")" >&2
    done
    echo "   Override with DOTFILES_WORKFLOW=<name>." >&2
    exit 1
fi

echo "=== MULTI-PLATFORM TESTING AUTOMATION ==="
echo "Repository: $REPO"
echo "Branch: $BRANCH"
echo "Workflow: $WORKFLOW_FILE"
echo ""

# Function to check if gh is authenticated
check_gh_auth() {
    if gh auth status >/dev/null 2>&1; then
        echo "✓ GitHub CLI authenticated"
        return 0
    else
        echo "ℹ GitHub CLI not authenticated - using public API"
        return 1
    fi
}

# Function to trigger workflow using GitHub CLI
trigger_workflow_gh() {
    echo "Triggering workflow via GitHub CLI..."
    gh workflow run "$WORKFLOW_FILE" --repo "$REPO" --ref "$BRANCH"
}

# Function to trigger workflow using git push
trigger_workflow_git() {
    echo "Triggering workflow via git push (branch: $BRANCH)..."
    if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
        echo "# Test trigger $(date)" >> .github/test-trigger.md
        git add .github/test-trigger.md
        git commit -m "Trigger workflow for platform testing $(date +%H:%M:%S)" || true
        git push origin "$BRANCH"
    else
        echo "⚠️ Branch '$BRANCH' not found; please create it or change BRANCH variable." >&2
        return 1
    fi
}

# Function to get workflow status using GitHub API
get_workflow_status() {
    echo "Fetching workflow status..."
    
    # Get latest workflow runs
    if check_gh_auth; then
        if command -v jq >/dev/null 2>&1; then
            gh run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --limit 1 --json status,conclusion,url,createdAt
        else
            echo "⚠️ jq not installed; showing raw output" >&2
            gh run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --limit 1
        fi
    else
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
    
    while [ $wait_time -lt $max_wait ]; do
        echo "Checking status... (${wait_time}s elapsed)"
        
    if check_gh_auth && command -v jq >/dev/null 2>&1; then
            # Get the latest run status
            local status
            status=$(gh run list --workflow="$WORKFLOW_FILE" --repo "$REPO" --limit 1 --json status,conclusion --jq '.[0]')
            
            if [ "$status" != "null" ] && [ -n "$status" ]; then
                local run_status
                local conclusion
                run_status=$(echo "$status" | jq -r '.status')
                conclusion=$(echo "$status" | jq -r '.conclusion')
                
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
    else
            echo "ℹ Cannot monitor without authentication - check manually at:"
            echo "https://github.com/$REPO/actions"
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

    # The success-rate line divides by this, so a non-positive count is an
    # arithmetic error rather than a no-op run.
    if ! [[ "$test_count" =~ ^[0-9]+$ ]] || [ "$test_count" -lt 1 ]; then
        echo "❌ Number of cycles must be a positive integer (got '$test_count')." >&2
        return 1
    fi

    echo "=== RUNNING $test_count PLATFORM TEST CYCLES ==="
    
    for i in $(seq 1 "$test_count"); do
        echo ""
        echo "🚀 TEST CYCLE $i/$test_count"
        echo "===================="
        
        # Trigger the workflow
        if check_gh_auth; then
            trigger_workflow_gh
        else
            trigger_workflow_git
        fi
        
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
    echo "Checking current repository status..."

    # Refuse rather than commit. This used to `git add -A`, commit everything in
    # the working tree under the message "Auto-commit before platform testing"
    # and push it to a hard-coded "main" — from whatever branch you were on,
    # with no prompt. Running a test helper must never publish your work.
    if [ -n "$(git status --porcelain)" ]; then
        echo "❌ Working directory is not clean." >&2
        git status --short >&2
        echo "" >&2
        echo "   Commit or stash first; CI tests what is pushed, not what is local." >&2
        exit 1
    fi

    echo ""
    get_workflow_status
    echo ""
    
    # Default to 3 test cycles
    local cycles=${1:-3}
    run_platform_tests "$cycles"
}

# Run main function with arguments
main "$@"
