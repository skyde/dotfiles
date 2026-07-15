# copy-diff - Copy git diff with extended context to clipboard
# Usage: copy-diff [lines]
#   lines   number of context lines (default: 100)
param(
    [int]$Lines = 100
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

# Get the diff with extended context and copy to clipboard
$diff = git diff -U$Lines $mergeBase
if ($diff) {
    $diff | Set-Clipboard
    Write-Host "Diff copied to clipboard ($($diff.Split("`n").Count) lines)"
} else {
    Write-Host "No diff to copy"
}
