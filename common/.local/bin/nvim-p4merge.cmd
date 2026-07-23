@echo off
setlocal

if "%~4"=="" goto usage
if not "%~5"=="" goto usage

rem P4 passes BASE, THEIRS, YOURS, OUTPUT. Diffview expects
rem OUTPUT, BASE, LEFT (ours), RIGHT (theirs).
call "%~dp0nvim-merge.cmd" "%~4" "%~1" "%~3" "%~2"
set "nvim_p4merge_status=%ERRORLEVEL%"
endlocal & exit /b %nvim_p4merge_status%

:usage
>&2 echo usage: nvim-p4merge BASE THEIRS YOURS OUTPUT
endlocal
exit /b 64
