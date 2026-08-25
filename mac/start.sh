#!/usr/bin/env bash
#
# start.sh — run backend (:8000) and frontend (:5173), each in its own
# Terminal window so you can watch both sets of logs live.
# Run:  ./mac/start.sh   (run ./mac/install.sh first if you haven't)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"  # repo root (parent of mac/)

BACKEND_CMD="cd '$ROOT/backend' && source venv/bin/activate && uvicorn app.main:app --reload --port 8000"
FRONTEND_CMD="cd '$ROOT/frontend' && npm run dev"

# --- preflight: make sure install.sh has been run -------------------------
if [ ! -d "$ROOT/backend/venv" ]; then
  echo "Backend not installed. Run ./mac/install.sh first." >&2
  exit 1
fi
if [ ! -d "$ROOT/frontend/node_modules" ]; then
  echo "Frontend not installed. Run ./mac/install.sh first." >&2
  exit 1
fi

# --- launch ----------------------------------------------------------------
if [ "$(uname)" = "Darwin" ]; then
  # macOS: open two Terminal.app windows via AppleScript.
  osascript <<EOF
tell application "Terminal"
  activate
  do script "$BACKEND_CMD"
  do script "$FRONTEND_CMD"
end tell
EOF
  echo "Opened two Terminal windows:"
  echo "  • backend  → http://localhost:8000  (API docs at /docs)"
  echo "  • frontend → http://localhost:5173"
else
  # Other OS: no portable way to open terminals — print the commands to run.
  echo "Run these in two separate terminals:"
  echo ""
  echo "  $BACKEND_CMD"
  echo "  $FRONTEND_CMD"
fi
