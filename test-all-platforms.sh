#!/bin/bash
set -e

# GitHub repository and workflow monitoring script
REPO="skyde/dotfiles"
BRANCH="main"
WORKFLOW_FILE="simple-test.yml"

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
    git status --porcelain
    
    if [ -n "$(git status --porcelain)" ]; then
        echo "⚠️  Working directory not clean - committing changes first"
        git add -A
        git commit -m "Auto-commit before platform testing"
        git push origin "$BRANCH"
    fi
    
    echo ""
    get_workflow_status
    echo ""
    
    # Default to 3 test cycles
    local cycles=${1:-3}
    run_platform_tests "$cycles"
}

# Check command line arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
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
    echo "Examples:"
    echo "  $0              # Run 3 test cycles"
    echo "  $0 5            # Run 5 test cycles"
    exit 0
fi

# Run main function with arguments
main "$@"
