@echo off
setlocal
set "VSCODE_CMD="
if defined VSCODE_CLI (
  if exist "%VSCODE_CLI%" (
    set "VSCODE_CMD=%VSCODE_CLI%"
  )
)

set "VSCODE_CANDIDATE=%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd"
if exist "%VSCODE_CANDIDATE%" (
  set "VSCODE_CMD=%VSCODE_CANDIDATE%"
)

if not defined VSCODE_CMD (
  set "VSCODE_CANDIDATE=%ProgramFiles%\Microsoft VS Code\bin\code.cmd"
  if exist "%VSCODE_CANDIDATE%" (
    set "VSCODE_CMD=%VSCODE_CANDIDATE%"
  )
)

if defined VSCODE_CMD (
  call "%VSCODE_CMD%" %*
  exit /b %ERRORLEVEL%
)

echo code.cmd: Visual Studio Code CLI not found 1>&2
exit /b 1
