@echo off
setlocal

if defined NVIM_PERFORCE_CMD (
    set "vcs_p4_command=%NVIM_PERFORCE_CMD%"
    goto run
)

where g4 >nul 2>nul
if not errorlevel 1 (
    set "vcs_p4_command=g4"
    goto run
)

where p4 >nul 2>nul
if not errorlevel 1 (
    set "vcs_p4_command=p4"
    goto run
)

>&2 echo vcs-p4: neither g4 nor p4 is available ^(set NVIM_PERFORCE_CMD to override^)
endlocal
exit /b 127

:run
call "%vcs_p4_command%" %*
set "vcs_p4_status=%ERRORLEVEL%"
endlocal & exit /b %vcs_p4_status%
