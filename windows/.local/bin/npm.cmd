@echo off
setlocal
set "NPM_CMD=%USERPROFILE%\.local\opt\nodejs\npm.cmd"
if not exist "%NPM_CMD%" (
  echo npm.cmd: portable npm.cmd not found 1>&2
  exit /b 1
)

call "%NPM_CMD%" %*
exit /b %ERRORLEVEL%
