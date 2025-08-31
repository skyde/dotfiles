Param()
$ErrorActionPreference = 'Stop'

function Ensure-Winget {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "winget not found; please install winget to proceed" -ForegroundColor Yellow
    return $false
  }
  return $true
}

function Install-WingetPackage($Id) {
  if (-not (Ensure-Winget)) { return }
  if ($env:DOT_DRYRUN) { Write-Host "[install-tools] dry-run: winget install $Id"; return }
  try { winget install --id $Id -e --accept-package-agreements --accept-source-agreements | Out-Null } catch {}
}

function Ensure-Command($Name, $WingetId) {
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Write-Host "[install-tools] installing $Name via winget ($WingetId)"
    Install-WingetPackage $WingetId
  } else {
    Write-Host "[install-tools] $Name already installed"
  }
}

# Core tools
Ensure-Command rg        'BurntSushi.ripgrep.MSVC'
Ensure-Command bat       'sharkdp.bat'
Ensure-Command wezterm   'wez.wezterm'
Ensure-Command hx        'Helix.Helix'
Ensure-Command lazygit   'JesseDuffield.lazygit'
Ensure-Command nvim      'Neovim.Neovim'

# LazyVim starter overlay (similar to Unix hook)
$nvimDir = Join-Path $env:USERPROFILE '.config\nvim'
if (Test-Path $nvimDir) {
  if (-not $env:DOT_DRYRUN) { Remove-Item $nvimDir -Recurse -Force }
}
if (-not $env:DOT_DRYRUN) {
  git clone https://github.com/LazyVim/starter $nvimDir | Out-Null
  try { Remove-Item (Join-Path $nvimDir '.git') -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  @('lazy-lock.json','lua\config\keymaps.lua','lua\plugins\colorscheme.lua','ftplugin\markdown.lua') | ForEach-Object {
    $p = Join-Path $nvimDir $_
    if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue }
  }
}

