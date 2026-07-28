# git-copy - Copy git diff to clipboard
# Copies the diff between the current branch and its nearest base to the clipboard.
param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

# Get the merge base with origin/main
$mergeBase = git merge-base HEAD origin/main 2>$null
if (-not $mergeBase) {
    # Try master if main doesn't exist
    $mergeBase = git merge-base HEAD origin/master 2>$null
}

if (-not $mergeBase) {
    Write-Error "Could not find merge base with origin/main or origin/master"
    exit 1
}

# Get the diff and copy to clipboard
$diff = git diff $mergeBase @Args
if ($diff) {
    $diff | Set-Clipboard
    Write-Host "Diff copied to clipboard ($($diff.Split("`n").Count) lines)"
} else {
    Write-Host "No diff to copy"
}
