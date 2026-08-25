#!/usr/bin/env bash
#
# install.sh — one-shot setup for Resume Builder.
# Installs the backend (Python venv + deps) and the frontend (npm deps).
# Run once after cloning:  ./mac/install.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # repo root (parent of mac/)

echo "==> Resume Builder — install"

# ---------------------------------------------------------------------------
# 1) Backend (Python)
# ---------------------------------------------------------------------------
echo ""
echo "[1/2] Backend (Python)…"
cd "$ROOT/backend"

if ! command -v python3 >/dev/null 2>&1; then
  echo "  ERROR: python3 not found. Install Python 3.9+ and re-run." >&2
  exit 1
fi

if [ ! -d venv ]; then
  echo "  creating virtualenv (backend/venv)…"
  python3 -m venv venv
fi

# shellcheck disable=SC1091
source venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt
deactivate
echo "  backend dependencies installed."

# .env — create from template if missing (do not overwrite an existing one)
if [ ! -f .env ]; then
  cp .env.example .env
  echo "  created backend/.env from template — add your OPENAI_API_KEY to it."
fi

# pdflatex is required to compile PDFs but is installed separately (it's ~1 GB)
if ! command -v pdflatex >/dev/null 2>&1 \
   && [ ! -x "/usr/local/texlive/2026basic/bin/universal-darwin/pdflatex" ]; then
  echo "  NOTE: pdflatex not found — PDFs won't compile until you install LaTeX:"
  echo "        macOS:  brew install --cask basictex"
fi

# ---------------------------------------------------------------------------
# 2) Frontend (Node)
# ---------------------------------------------------------------------------
echo ""
echo "[2/2] Frontend (Node)…"
cd "$ROOT/frontend"

if ! command -v npm >/dev/null 2>&1; then
  echo "  ERROR: npm not found. Install Node.js 18+ and re-run." >&2
  exit 1
fi

npm install
echo "  frontend dependencies installed."

echo ""
echo "==> Done. Start everything with:  ./mac/start.sh"
