@echo off
setlocal
set "BTOP_EXE="
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\aristocratos.btop4win_*") do (
  if exist "%%~fD\btop4win\btop4win.exe" (
    set "BTOP_EXE=%%~fD\btop4win\btop4win.exe"
  )
)

if defined BTOP_EXE (
  "%BTOP_EXE%" %*
  exit /b %ERRORLEVEL%
)

where btop4win.exe >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
  echo btop.cmd: btop4win.exe not found 1>&2
  exit /b 1
)

btop4win.exe %*
exit /b %ERRORLEVEL%
