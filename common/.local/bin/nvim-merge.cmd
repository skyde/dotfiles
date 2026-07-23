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

set "NVIM_MERGE_OUTPUT=%~1"
set "NVIM_MERGE_BASE=%~2"
set "NVIM_MERGE_LEFT=%~3"
set "NVIM_MERGE_RIGHT=%~4"

nvim -f -c "lua local escape = vim.fn.fnameescape; vim.api.nvim_cmd({ cmd = 'DiffviewMergeFiles', args = { escape(vim.env.NVIM_MERGE_OUTPUT), escape(vim.env.NVIM_MERGE_BASE), escape(vim.env.NVIM_MERGE_LEFT), escape(vim.env.NVIM_MERGE_RIGHT) } }, {})"
set "nvim_merge_status=%ERRORLEVEL%"
endlocal & exit /b %nvim_merge_status%

:usage
>&2 echo usage: nvim-merge OUTPUT BASE LEFT RIGHT
endlocal
exit /b 64
