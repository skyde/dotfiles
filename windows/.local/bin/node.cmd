@echo off
setlocal
set "NODE_EXE=%USERPROFILE%\.local\opt\nodejs\node.exe"
if not exist "%NODE_EXE%" (
  echo node.cmd: portable node.exe not found 1>&2
  exit /b 1
)

"%NODE_EXE%" %*
exit /b %ERRORLEVEL%
