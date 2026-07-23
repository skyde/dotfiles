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

set "NVIM_DIFF_LEFT=%~1"
set "NVIM_DIFF_RIGHT=%~2"
set "NVIM_DIFF_OUTPUT=%~3"
set "NVIM_DIFFVIEW_COMMAND=DiffviewDiffFiles"

if not "%~3"=="" set "NVIM_DIFFVIEW_COMMAND=DiffviewDiffDirs"
if exist "%~1\NUL" if exist "%~2\NUL" set "NVIM_DIFFVIEW_COMMAND=DiffviewDiffDirs"

nvim -f -c "lua local escape = vim.fn.fnameescape; local args = { escape(vim.env.NVIM_DIFF_LEFT), escape(vim.env.NVIM_DIFF_RIGHT) }; local output = vim.env.NVIM_DIFF_OUTPUT; if output and output ~= '' then args[#args + 1] = escape(output) end; vim.api.nvim_cmd({ cmd = vim.env.NVIM_DIFFVIEW_COMMAND, args = args }, {})"
set "nvim_diff_status=%ERRORLEVEL%"
endlocal & exit /b %nvim_diff_status%

:usage
>&2 echo usage: nvim-diff LEFT RIGHT [OUTPUT]
endlocal
exit /b 64
