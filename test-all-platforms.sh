#!/bin/bash
set -euo pipefail

# GitHub repository and workflow monitoring script
REPO="skyde/dotfiles"
BRANCH="main"
WORKFLOW_FILE="comprehensive-test.yml"
CYCLES=3
TRIGGER_WORKFLOW=0
COMMIT_DIRTY=0
ALLOW_GIT_PUSH_TRIGGER=0

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
    
    echo "=== RUNNING $test_count PLATFORM TEST CYCLES ==="
    
    for i in $(seq 1 "$test_count"); do
        echo ""
        echo "🚀 TEST CYCLE $i/$test_count"
        echo "===================="
        
        # Trigger the workflow
        if check_gh_auth; then
            trigger_workflow_gh
        elif [ "$ALLOW_GIT_PUSH_TRIGGER" -eq 1 ]; then
            trigger_workflow_git
        else
            echo "❌ GitHub CLI is not authenticated."
            echo "Refusing to trigger by committing and pushing unless --allow-git-push-trigger is set."
            return 1
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
    git status --porcelain
    
    if [ -n "$(git status --porcelain)" ]; then
        if [ "$COMMIT_DIRTY" -eq 1 ]; then
            echo "⚠️  Working directory not clean - committing changes first because --commit-dirty was set"
            git add -A
            git commit -m "Auto-commit before platform testing"
            git push origin "$BRANCH"
        elif [ "$TRIGGER_WORKFLOW" -eq 1 ]; then
            echo "❌ Working directory is not clean."
            echo "Commit/stash changes first, or pass --commit-dirty to allow this script to commit and push them."
            exit 1
        fi
    fi
    
    echo ""
    get_workflow_status
    echo ""
    
    if [ "$TRIGGER_WORKFLOW" -eq 1 ]; then
        run_platform_tests "$CYCLES"
    else
        echo "Status-only mode. Pass --trigger to run workflow cycles."
    fi
}

usage() {
    echo "Usage: $0 [number_of_cycles]"
    echo ""
    echo "By default this script only shows current workflow status."
    echo "With --trigger, it triggers and monitors GitHub Actions workflows"
    echo "to test dotfiles installation across all platforms:"
    echo "  - Linux (Ubuntu)"
    echo "  - macOS (latest)"
    echo "  - Windows (latest)"
    echo ""
    echo "Options:"
    echo "  number_of_cycles          Number of test cycles to run (default: 3)"
    echo "  --status-only             Show latest workflow status and exit (default behavior)"
    echo "  --trigger                 Trigger workflow cycles"
    echo "  --commit-dirty            Allow auto-commit/push of dirty working tree before triggering"
    echo "  --allow-git-push-trigger  Allow git-push fallback trigger when gh is not authenticated"
    echo "  --help, -h                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                         # Show latest workflow status"
    echo "  $0 --status-only           # Show latest workflow status"
    echo "  $0 --trigger               # Run 3 test cycles via gh workflow run"
    echo "  $0 --trigger 5             # Run 5 test cycles"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            exit 0
            ;;
        --trigger)
            TRIGGER_WORKFLOW=1
            ;;
        --status-only)
            TRIGGER_WORKFLOW=0
            ;;
        --commit-dirty)
            COMMIT_DIRTY=1
            ;;
        --allow-git-push-trigger)
            ALLOW_GIT_PUSH_TRIGGER=1
            ;;
        ''|*[!0-9]*)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            CYCLES="$1"
            ;;
    esac
    shift
done

if [ "$CYCLES" -lt 1 ]; then
    echo "number_of_cycles must be at least 1" >&2
    exit 2
fi

# Run main function with arguments
main
