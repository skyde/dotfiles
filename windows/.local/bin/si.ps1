# si - Simple Zoekt indexer
# Usage: si [PATH]
#   PATH    directory to index; defaults to current directory
param(
    [string]$Path = "."
)

$ErrorActionPreference = 'Stop'

# Get CPU count for parallelism
$cpuCount = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
if (-not $cpuCount) { $cpuCount = 4 }

Write-Host "Using $cpuCount parallel workers"

$ignores = ".git,.svn,.hg,.idea,.vs,node_modules,out,build,dist,tmp,temp,cache,.cache,__pycache__,.mypy_cache,.pytest_cache,.tox,vendor,CMakeFiles,.gradle,.mvn,pkg,bin,.terraform,.jekyll-cache,_site"

$targetDir = ".zoekt"

# Create a temp directory in the current folder
$tempDir = Join-Path $PWD ".zoekt.tmp.$([System.IO.Path]::GetRandomFileName())"

try {
    # Run the indexer into the temporary directory
    & zoekt-index -index $tempDir -parallelism $cpuCount -ignore_dirs="$ignores" $Path

    if ($LASTEXITCODE -ne 0) {
        throw "zoekt-index failed with exit code $LASTEXITCODE"
    }

    Write-Host "Indexing complete. Swapping in new index..."

    # Remove the old index
    if (Test-Path $targetDir) {
        Remove-Item -Recurse -Force $targetDir
    }

    # Move the new index into place
    Move-Item $tempDir $targetDir

    Write-Host "Done."
}
catch {
    # Clean up on failure
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
    throw
}
