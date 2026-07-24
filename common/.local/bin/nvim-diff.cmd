@echo off
setlocal

if "%~2"=="" goto usage
if not "%~4"=="" goto usage

where nvim >nul 2>nul
if errorlevel 1 (
    >&2 echo nvim-diff: nvim is not available
    endlocal
    exit /b 127
)

set "NVIM_DIFF_LEFT=%~f1"
set "NVIM_DIFF_RIGHT=%~f2"
if "%~3"=="" (
    set "NVIM_DIFF_OUTPUT="
) else (
    set "NVIM_DIFF_OUTPUT=%~f3"
)
set "NVIM_DIFFVIEW_COMMAND=files"

if not "%~3"=="" set "NVIM_DIFFVIEW_COMMAND=dirs"
if exist "%~1\NUL" if exist "%~2\NUL" set "NVIM_DIFFVIEW_COMMAND=dirs"

nvim -f -c "lua local args = { vim.env.NVIM_DIFF_LEFT, vim.env.NVIM_DIFF_RIGHT }; local output = vim.env.NVIM_DIFF_OUTPUT; if output and output ~= '' then args[#args + 1] = output end; require('config.diff_tool').open(vim.env.NVIM_DIFFVIEW_COMMAND, args)"
set "nvim_diff_status=%ERRORLEVEL%"
endlocal & exit /b %nvim_diff_status%

:usage
>&2 echo usage: nvim-diff LEFT RIGHT [OUTPUT]
endlocal
exit /b 64
