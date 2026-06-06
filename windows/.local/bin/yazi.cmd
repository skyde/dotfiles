@echo off
setlocal
set "BASH_EXE=%ProgramFiles%\Git\usr\bin\bash.exe"
if not exist "%BASH_EXE%" set "BASH_EXE=bash.exe"
"%BASH_EXE%" "%~dp0yazi" %*
exit /b %ERRORLEVEL%
