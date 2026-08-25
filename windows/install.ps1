#Requires -Version 5.1
<#
    install.ps1 - one-shot setup for Resume Builder on Windows.
    Installs the backend (Python venv + deps) and the frontend (npm deps).

    Run once after cloning, from the repo root:
        powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
    or just double-click windows\install.bat
#>

$ErrorActionPreference = 'Stop'

# Repo root = parent of this script's folder (windows\).
$Root     = Split-Path -Parent $PSScriptRoot
$Backend  = Join-Path $Root 'backend'
$Frontend = Join-Path $Root 'frontend'

function Write-Step($msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-Note($msg) { Write-Host "  $msg" -ForegroundColor Yellow }
function Write-Ok  ($msg) { Write-Host "  $msg" -ForegroundColor Green }

Write-Step '==> Resume Builder - install (Windows)'

# ---------------------------------------------------------------------------
# 0) Locate a real Python
# ---------------------------------------------------------------------------
# NOTE: do NOT use "python3" on Windows. It is usually the Microsoft Store stub
# in WindowsApps, which opens the Store instead of running Python.
function Get-PythonCommand {
    # Preferred: the py launcher, which always points at a real install.
    if (Get-Command 'py' -ErrorAction SilentlyContinue) {
        try {
            $v = & py -3 --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $v) { return @{ Exe = 'py'; Args = @('-3'); Version = "$v".Trim() } }
        } catch { }
    }
    $cmd = Get-Command 'python' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -notlike '*\WindowsApps\*') {
        try {
            $v = & python --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $v) { return @{ Exe = 'python'; Args = @(); Version = "$v".Trim() } }
        } catch { }
    }
    return $null
}

# ---------------------------------------------------------------------------
# 1) Backend (Python)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Step '[1/2] Backend (Python)...'
Set-Location $Backend

$py = Get-PythonCommand
if ($null -eq $py) {
    Write-Host '  ERROR: Python 3.9+ not found.' -ForegroundColor Red
    Write-Host '         Install it from https://www.python.org/downloads/windows/' -ForegroundColor Red
    Write-Host '         and tick "Add python.exe to PATH" during setup, then re-run.' -ForegroundColor Red
    exit 1
}
Write-Ok "using $($py.Version)"

$VenvPy = Join-Path $Backend 'venv\Scripts\python.exe'
if (-not (Test-Path $VenvPy)) {
    Write-Note 'creating virtualenv (backend\venv)...'
    & $py.Exe @($py.Args + @('-m', 'venv', 'venv'))
    if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR: venv creation failed.' -ForegroundColor Red; exit 1 }
}

# Install into the venv by calling its python.exe directly. This deliberately
# skips Activate.ps1 so a restrictive ExecutionPolicy can never block setup.
& $VenvPy -m pip install --quiet --upgrade pip
& $VenvPy -m pip install --quiet -r requirements.txt
if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR: pip install failed.' -ForegroundColor Red; exit 1 }
Write-Ok 'backend dependencies installed.'

# --- .env: create from template if missing (never overwrite an existing one) --
$EnvFile = Join-Path $Backend '.env'
if (-not (Test-Path $EnvFile)) {
    Copy-Item (Join-Path $Backend '.env.example') $EnvFile
    # The template ships the macOS BasicTeX path. On Windows, MiKTeX/TeX Live put
    # pdflatex.exe on PATH, so the bare command name is the right default here.
    (Get-Content $EnvFile) -replace '^PDFLATEX_PATH=.*$', 'PDFLATEX_PATH=pdflatex' |
        Set-Content $EnvFile -Encoding utf8
    Write-Note 'created backend\.env from template - add your OPENAI_API_KEY and DATABASE_URL to it.'
} else {
    # Existing .env carried over from the Mac will point pdflatex at a macOS path.
    $envText = Get-Content $EnvFile -Raw
    if ($envText -match '(?m)^PDFLATEX_PATH=(/usr/|/opt/|/Library/).*$') {
        Write-Note 'WARNING: backend\.env has a macOS PDFLATEX_PATH - PDF compiles will fail on Windows.'
        Write-Note '         Change that line to:  PDFLATEX_PATH=pdflatex'
    }
}

# --- pdflatex: required to compile PDFs, installed separately (large) --------
$pdflatex = Get-Command 'pdflatex' -ErrorAction SilentlyContinue
if ($pdflatex) {
    Write-Ok "pdflatex found at $($pdflatex.Source)"
} else {
    Write-Note 'NOTE: pdflatex not found - PDFs will not compile until you install LaTeX.'
    Write-Note '      Recommended (MiKTeX):   winget install MiKTeX.MiKTeX'
    Write-Note '      Alternative (TeX Live): https://tug.org/texlive/windows.html'
    Write-Note '      Open a NEW terminal afterwards so PATH picks it up, then: pdflatex --version'
}

# ---------------------------------------------------------------------------
# 2) Frontend (Node)
# ---------------------------------------------------------------------------
Write-Host ''
Write-Step '[2/2] Frontend (Node)...'
Set-Location $Frontend

# Use npm.cmd, not the npm.ps1 shim - the .cmd runs regardless of ExecutionPolicy.
if (-not (Get-Command 'npm.cmd' -ErrorAction SilentlyContinue)) {
    Write-Host '  ERROR: npm not found. Install Node.js 18+ from https://nodejs.org/ and re-run.' -ForegroundColor Red
    exit 1
}

& npm.cmd install
if ($LASTEXITCODE -ne 0) { Write-Host '  ERROR: npm install failed.' -ForegroundColor Red; exit 1 }
Write-Ok 'frontend dependencies installed.'

# --- frontend .env sanity check ---------------------------------------------
# frontend\.env is local-dev only and is NOT committed. If it holds the
# production value (VITE_API_BASE_URL=/api) the dev server has nothing to proxy
# /api to, so every API call 404s against Vite itself.
$FeEnv = Join-Path $Frontend '.env'
if (Test-Path $FeEnv) {
    $feText = Get-Content $FeEnv -Raw
    if ($feText -match '(?m)^\s*VITE_API_BASE_URL\s*=\s*/api\s*$') {
        Write-Host ''
        Write-Note 'WARNING: frontend\.env sets VITE_API_BASE_URL=/api (a PRODUCTION value).'
        Write-Note '         Local dev has no /api proxy, so all API calls will fail.'
        Write-Note '         Fix it with:  VITE_API_BASE_URL=http://localhost:8000'
        Write-Note '         (.env.production keeps /api for the real deploy - leave it alone.)'
    }
}

Set-Location $Root
Write-Host ''
Write-Step '==> Done. Start everything with:  .\windows\start.ps1'
