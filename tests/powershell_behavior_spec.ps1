# Behavior tests for the Windows-facing dotfile scripts. No Pester dependency required.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$powerShellExe = (Get-Process -Id $PID).Path
$script:passed = 0
$script:failed = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Context
    )
    if (-not $Condition) {
        throw $Context
    }
}

function Assert-Equal {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][string]$Context
    )
    if ($Expected -ne $Actual) {
        throw "$Context (expected '$Expected', got '$Actual')"
    }
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Context
    )
    if (-not $Text.Contains($Needle)) {
        throw "$Context (missing '$Needle')"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Context
    )
    if ($Text.Contains($Needle)) {
        throw "$Context (unexpected '$Needle')"
    }
}

function Invoke-WithEnvironment {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Values,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    $previous = @{}
    foreach ($name in $Values.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$Values[$name], 'Process')
    }

    try {
        & $Body
    } finally {
        foreach ($name in $Values.Keys) {
            [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process')
        }
    }
}

function Invoke-ChildScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $repoRoot
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $powerShellExe
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoLogo')
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($ScriptPath)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.GetAwaiter().GetResult()
        Stderr = $stderrTask.GetAwaiter().GetResult()
        Output = $stdoutTask.GetAwaiter().GetResult() + $stderrTask.GetAwaiter().GetResult()
    }
}

function New-TestDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("dotfiles-spec-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}

function Write-CmdShim {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    Set-Content -LiteralPath $Path -Value $Content -Encoding ascii
}

function New-FakeBin {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$Stow,
        [switch]$Git,
        [switch]$Winget,
        [switch]$Code
    )

    $fakeBin = Join-Path $Root 'bin'
    New-Item -ItemType Directory -Path $fakeBin | Out-Null

    if ($Stow) {
        Write-CmdShim (Join-Path $fakeBin 'stow.cmd') @'
@echo off
>>"%STOW_LOG%" echo CALL %*
if defined STOW_EXIT_CODE exit /b %STOW_EXIT_CODE%
exit /b 0
'@
    }

    if ($Git) {
        Write-CmdShim (Join-Path $fakeBin 'git.cmd') @'
@echo off
>>"%GIT_LOG%" echo CALL %*
if defined GIT_EXIT_CODE exit /b %GIT_EXIT_CODE%
exit /b 0
'@
    }

    if ($Winget) {
        Write-CmdShim (Join-Path $fakeBin 'winget.cmd') @'
@echo off
>>"%WINGET_LOG%" echo CALL %*
if defined WINGET_EXIT_CODE exit /b %WINGET_EXIT_CODE%
exit /b 0
'@
    }

    if ($Code) {
        Write-CmdShim (Join-Path $fakeBin 'code.cmd') @'
@echo off
>>"%CODE_LOG%" echo CALL %*
if defined CODE_EXIT_CODE exit /b %CODE_EXIT_CODE%
exit /b 0
'@
    }

    return $fakeBin
}

function New-LocalApply {
    param([Parameter(Mandatory = $true)][string]$TestHome)
    $localRoot = Join-Path $TestHome 'dotfiles-local'
    New-Item -ItemType Directory -Force -Path $localRoot | Out-Null
    Set-Content -LiteralPath (Join-Path $localRoot 'apply.ps1') -Encoding utf8 -Value @'
Add-Content -LiteralPath $env:LOCAL_APPLY_LOG -Value ("CALL " + ($args -join " "))
'@
}

function Get-Lines {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    Get-Content -LiteralPath $Path
}

function Test-ApplyNormalizesArgumentsAndRunsLocalOnce {
    $temp = New-TestDirectory
    try {
        $testHome = Join-Path $temp 'home with spaces'
        New-Item -ItemType Directory -Path $testHome | Out-Null
        $fakeBin = New-FakeBin -Root $temp -Stow
        New-LocalApply -TestHome $testHome
        $stowLog = Join-Path $temp 'stow.log'
        $localLog = Join-Path $temp 'local.log'

        Invoke-WithEnvironment @{
            PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            USERPROFILE = $testHome
            HOME = $testHome
            STOW_LOG = $stowLog
            LOCAL_APPLY_LOG = $localLog
            DOTFILES_STOW_COMMAND = 'stow'
            STOW_EXIT_CODE = $null
        } {
            $result = Invoke-ChildScript -ScriptPath (Join-Path $repoRoot 'apply.ps1') -Arguments @('--no-act', '--yes', '--restow')
            Assert-Equal 0 $result.ExitCode 'apply.ps1 should succeed'
        }

        $stowLines = @(Get-Lines $stowLog)
        $stowText = $stowLines -join "`n"
        $localLines = @(Get-Lines $localLog)
        Assert-Equal 2 $stowLines.Count 'common and windows should each be stowed once'
        Assert-Contains $stowText "--target=$testHome" 'HOME with spaces should remain one target argument'
        Assert-Contains $stowText '--no' '--no-act should normalize to --no'
        Assert-Contains $stowText '--restow' 'restow should reach Stow'
        Assert-NotContains $stowText '--no-act' 'unsupported alias must not reach Stow'
        Assert-NotContains $stowText '--yes' 'wrapper confirmation flag must not reach Stow'
        Assert-Contains $stowText ' common' 'common package call'
        Assert-Contains $stowText ' windows' 'windows package call'
        Assert-Equal 1 $localLines.Count 'dotfiles-local must run exactly once'
        Assert-Contains $localLines[0] '--no-act --yes --restow' 'local apply should receive original arguments'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-ApplyPropagatesNativeFailure {
    $temp = New-TestDirectory
    try {
        $testHome = Join-Path $temp 'home'
        New-Item -ItemType Directory -Path $testHome | Out-Null
        $fakeBin = New-FakeBin -Root $temp -Stow
        New-LocalApply -TestHome $testHome
        $stowLog = Join-Path $temp 'stow.log'
        $localLog = Join-Path $temp 'local.log'

        Invoke-WithEnvironment @{
            PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            USERPROFILE = $testHome
            HOME = $testHome
            STOW_LOG = $stowLog
            STOW_EXIT_CODE = '23'
            LOCAL_APPLY_LOG = $localLog
            DOTFILES_STOW_COMMAND = 'stow'
        } {
            $result = Invoke-ChildScript -ScriptPath (Join-Path $repoRoot 'apply.ps1') -Arguments @('--no')
            Assert-True ($result.ExitCode -ne 0) 'native Stow failure should fail apply.ps1'
            Assert-Contains $result.Output 'exit code 23' 'native exit code should be reported'
        }

        Assert-True (-not (Test-Path -LiteralPath $localLog)) 'local apply ran after Stow failed'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-ApplyDryRunDoesNotInstallMissingStow {
    $temp = New-TestDirectory
    try {
        $testHome = Join-Path $temp 'home'
        New-Item -ItemType Directory -Path $testHome | Out-Null
        $fakeBin = New-FakeBin -Root $temp -Winget
        $wingetLog = Join-Path $temp 'winget.log'

        Invoke-WithEnvironment @{
            PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            USERPROFILE = $testHome
            HOME = $testHome
            WINGET_LOG = $wingetLog
            DOTFILES_STOW_COMMAND = 'definitely-missing-stow'
        } {
            $result = Invoke-ChildScript -ScriptPath (Join-Path $repoRoot 'apply.ps1') -Arguments @('--no')
            Assert-True ($result.ExitCode -ne 0) 'missing Stow should make preview fail clearly'
            Assert-Contains $result.Output 'required to preview' 'missing-Stow diagnostic'
        }

        Assert-True (-not (Test-Path -LiteralPath $wingetLog)) 'dry run attempted to install Stow'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-InitWorksFromAnotherDirectoryWithoutPrompts {
    $temp = New-TestDirectory
    try {
        $testHome = Join-Path $temp 'home'
        $working = Join-Path $temp 'elsewhere'
        New-Item -ItemType Directory -Path $testHome, $working | Out-Null
        $fakeBin = New-FakeBin -Root $temp -Stow
        $stowLog = Join-Path $temp 'stow.log'

        Invoke-WithEnvironment @{
            PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            USERPROFILE = $testHome
            HOME = $testHome
            STOW_LOG = $stowLog
            AUTO_INSTALL = '0'
            DOTFILES_STOW_COMMAND = 'stow'
        } {
            $result = Invoke-ChildScript -ScriptPath (Join-Path $repoRoot 'init.ps1') -Arguments @('--no') -WorkingDirectory $working
            Assert-Equal 0 $result.ExitCode 'init.ps1 should work outside the repository directory'
        }

        Assert-Equal 2 (@(Get-Lines $stowLog)).Count 'init should apply common and windows once each'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-InitAutomaticModeUsesRepositoryManifests {
    $temp = New-TestDirectory
    try {
        $testHome = Join-Path $temp 'home'
        $working = Join-Path $temp 'elsewhere'
        New-Item -ItemType Directory -Path $testHome, $working | Out-Null
        $fakeBin = New-FakeBin -Root $temp -Stow -Winget -Code
        $stowLog = Join-Path $temp 'stow.log'
        $wingetLog = Join-Path $temp 'winget.log'
        $codeLog = Join-Path $temp 'code.log'

        Invoke-WithEnvironment @{
            PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            USERPROFILE = $testHome
            HOME = $testHome
            STOW_LOG = $stowLog
            WINGET_LOG = $wingetLog
            CODE_LOG = $codeLog
            AUTO_INSTALL = '1'
            DOTFILES_STOW_COMMAND = 'stow'
        } {
            $result = Invoke-ChildScript -ScriptPath (Join-Path $repoRoot 'init.ps1') -WorkingDirectory $working
            Assert-Equal 0 $result.ExitCode 'automatic init should succeed with command shims'
        }

        $expectedExtensions = @(
            Get-Content -LiteralPath (Join-Path $repoRoot 'vscode_extensions.txt') |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and -not $_.StartsWith('#') }
        ).Count
        Assert-Equal $expectedExtensions (@(Get-Lines $codeLog)).Count 'all extension manifest entries should be processed'
        Assert-Equal 12 (@(Get-Lines $wingetLog)).Count 'all common Windows applications should be processed'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-UpdatePullsBothRepositoriesAndAppliesLocalOnce {
    $temp = New-TestDirectory
    try {
        $testHome = Join-Path $temp 'home with spaces'
        New-Item -ItemType Directory -Path (Join-Path $testHome 'dotfiles-local\.git') -Force | Out-Null
        $fakeBin = New-FakeBin -Root $temp -Stow -Git
        New-LocalApply -TestHome $testHome
        $stowLog = Join-Path $temp 'stow.log'
        $gitLog = Join-Path $temp 'git.log'
        $localLog = Join-Path $temp 'local.log'

        Invoke-WithEnvironment @{
            PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            USERPROFILE = $testHome
            HOME = $testHome
            STOW_LOG = $stowLog
            GIT_LOG = $gitLog
            LOCAL_APPLY_LOG = $localLog
            DOTFILES_STOW_COMMAND = 'stow'
        } {
            $result = Invoke-ChildScript -ScriptPath (Join-Path $repoRoot 'update.ps1') -Arguments @('--no', '--yes')
            Assert-Equal 0 $result.ExitCode 'update.ps1 should succeed'
        }

        $gitLines = @(Get-Lines $gitLog)
        $gitText = $gitLines -join "`n"
        $stowLines = @(Get-Lines $stowLog)
        $stowText = $stowLines -join "`n"
        $localLines = @(Get-Lines $localLog)
        Assert-Equal 2 $gitLines.Count 'main and local repositories should each be pulled once'
        Assert-Contains $gitText 'pull --ff-only' 'pulls should be fast-forward only'
        Assert-Contains $gitText "-C `"$testHome\dotfiles-local`" pull --ff-only" 'local repository path should stay intact'
        Assert-Equal 2 $stowLines.Count 'update should restow common and windows once each'
        Assert-Contains $stowText '--restow' 'restow should reach Stow'
        Assert-Contains $stowText '--no' 'preview should reach Stow'
        Assert-NotContains $stowText '--yes' 'wrapper confirmation flag must not reach Stow'
        Assert-Equal 1 $localLines.Count 'update must apply dotfiles-local exactly once'
        Assert-Contains $localLines[0] '--restow --no --yes' 'local apply should receive the complete operation'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-UpdateStopsOnGitFailure {
    $temp = New-TestDirectory
    try {
        $testHome = Join-Path $temp 'home'
        New-Item -ItemType Directory -Path (Join-Path $testHome 'dotfiles-local\.git') -Force | Out-Null
        $fakeBin = New-FakeBin -Root $temp -Stow -Git
        New-LocalApply -TestHome $testHome
        $stowLog = Join-Path $temp 'stow.log'
        $gitLog = Join-Path $temp 'git.log'
        $localLog = Join-Path $temp 'local.log'

        Invoke-WithEnvironment @{
            PATH = "$fakeBin$([IO.Path]::PathSeparator)$env:PATH"
            USERPROFILE = $testHome
            HOME = $testHome
            STOW_LOG = $stowLog
            GIT_LOG = $gitLog
            GIT_EXIT_CODE = '42'
            LOCAL_APPLY_LOG = $localLog
            DOTFILES_STOW_COMMAND = 'stow'
        } {
            $result = Invoke-ChildScript -ScriptPath (Join-Path $repoRoot 'update.ps1') -Arguments @('--no')
            Assert-True ($result.ExitCode -ne 0) 'git failure should fail update.ps1'
            Assert-Contains $result.Output 'exit code 42' 'git exit code should be reported'
        }

        Assert-True (-not (Test-Path -LiteralPath $stowLog)) 'Stow ran after git pull failed'
        Assert-True (-not (Test-Path -LiteralPath $localLog)) 'local apply ran after git pull failed'
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-AllPowerShellScriptsParse {
    $failures = @()
    foreach ($scriptFile in Get-ChildItem -LiteralPath $repoRoot -Filter '*.ps1' -Recurse) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptFile.FullName,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        if ($errors.Count -gt 0) {
            $failures += "$($scriptFile.FullName): $($errors -join '; ')"
        }
    }

    $context = if ($failures.Count -gt 0) { $failures -join "`n" } else { 'all PowerShell scripts should parse' }
    Assert-Equal 0 $failures.Count $context
}

function Run-Test {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )

    Write-Host "TEST $Name"
    try {
        & $Body
        $script:passed++
        Write-Host "PASS $Name" -ForegroundColor Green
    } catch {
        $script:failed++
        Write-Host "FAIL $Name`n$($_.Exception.Message)" -ForegroundColor Red
    }
}

Run-Test 'apply normalizes args and runs local once' { Test-ApplyNormalizesArgumentsAndRunsLocalOnce }
Run-Test 'apply propagates native failures' { Test-ApplyPropagatesNativeFailure }
Run-Test 'apply dry run does not install Stow' { Test-ApplyDryRunDoesNotInstallMissingStow }
Run-Test 'init works from another directory' { Test-InitWorksFromAnotherDirectoryWithoutPrompts }
Run-Test 'init automatic mode uses repository manifests' { Test-InitAutomaticModeUsesRepositoryManifests }
Run-Test 'update pulls and applies local once' { Test-UpdatePullsBothRepositoriesAndAppliesLocalOnce }
Run-Test 'update stops on git failure' { Test-UpdateStopsOnGitFailure }
Run-Test 'all PowerShell scripts parse' { Test-AllPowerShellScriptsParse }

Write-Host "`nPowerShell behavior tests: $($script:passed) passed, $($script:failed) failed"
if ($script:failed -ne 0) {
    exit 1
}
