@echo off
setlocal

if "%~4"=="" goto usage
if not "%~5"=="" goto usage

where nvim >nul 2>nul
if errorlevel 1 (
    >&2 echo nvim-merge: nvim is not available
    endlocal
    exit /b 127
)

set "NVIM_MERGE_OUTPUT=%~f1"
set "NVIM_MERGE_BASE=%~f2"
set "NVIM_MERGE_LEFT=%~f3"
set "NVIM_MERGE_RIGHT=%~f4"

nvim -f -c "lua require('config.diff_tool').open('merge', { vim.env.NVIM_MERGE_OUTPUT, vim.env.NVIM_MERGE_BASE, vim.env.NVIM_MERGE_LEFT, vim.env.NVIM_MERGE_RIGHT })"
set "nvim_merge_status=%ERRORLEVEL%"
endlocal & exit /b %nvim_merge_status%

:usage
>&2 echo usage: nvim-merge OUTPUT BASE LEFT RIGHT
endlocal
exit /b 64
