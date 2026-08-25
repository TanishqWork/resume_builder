#Requires -Version 5.1
<#
    start.ps1 - run backend (:8000) and frontend (:5173) on Windows, each in its
    own PowerShell window so you can watch both sets of logs live.

    Run from the repo root:
        powershell -ExecutionPolicy Bypass -File .\windows\start.ps1
    or just double-click windows\start.bat

    Run windows\install.ps1 first if you have not already.
#>

$ErrorActionPreference = 'Stop'

# Repo root = parent of this script's folder (windows\).
$Root     = Split-Path -Parent $PSScriptRoot
$Backend  = Join-Path $Root 'backend'
$Frontend = Join-Path $Root 'frontend'
$VenvPy   = Join-Path $Backend 'venv\Scripts\python.exe'

# --- preflight: make sure install.ps1 has been run --------------------------
if (-not (Test-Path $VenvPy)) {
    Write-Host 'Backend not installed. Run .\windows\install.ps1 first.' -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $Frontend 'node_modules'))) {
    Write-Host 'Frontend not installed. Run .\windows\install.ps1 first.' -ForegroundColor Red
    exit 1
}
if (-not (Test-Path (Join-Path $Backend '.env'))) {
    Write-Host 'backend\.env is missing. Run .\windows\install.ps1 first.' -ForegroundColor Red
    exit 1
}

# --- commands ---------------------------------------------------------------
# uvicorn is launched as "python -m uvicorn" from the venv's own interpreter, so
# no Activate.ps1 is needed and ExecutionPolicy is never in the way.
# cwd MUST be backend\ - config.py loads ".env" relative to the working directory.
$BackendCmd  = "Set-Location '$Backend'; & '$VenvPy' -m uvicorn app.main:app --reload --port 8000"
$FrontendCmd = "Set-Location '$Frontend'; & npm.cmd run dev"

# --- launch two windows -----------------------------------------------------
Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $BackendCmd
Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $FrontendCmd

Write-Host 'Opened two PowerShell windows:' -ForegroundColor Cyan
Write-Host '  * backend  -> http://localhost:8000  (API docs at /docs)'
Write-Host '  * frontend -> http://localhost:5173'
Write-Host ''
Write-Host 'Close those windows (or press Ctrl+C in each) to stop the servers.'
