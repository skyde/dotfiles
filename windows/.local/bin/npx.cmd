@echo off
setlocal
set "NPX_CMD=%USERPROFILE%\.local\opt\nodejs\npx.cmd"
if not exist "%NPX_CMD%" (
  echo npx.cmd: portable npx.cmd not found 1>&2
  exit /b 1
)

call "%NPX_CMD%" %*
exit /b %ERRORLEVEL%
