# Set a permanent user-level env-var so tools
# know to launch PowerShell instead of cmd
[Environment]::SetEnvironmentVariable('SHELL', 'pwsh', 'User')
Write-Host '✔  SHELL=pwsh (User scope) set. You may need to restart shells.'
