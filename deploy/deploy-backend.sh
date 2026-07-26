#!/usr/bin/env bash
#
# Deploy the FastAPI backend on the VPS.
#
# Used two ways:
#   - by CI (.github/workflows/deploy-vps.yml) over SSH
#   - by hand when Actions is down:  bash /var/www/resume/deploy/deploy-backend.sh
#
# Skip the git pull (e.g. CI already synced the tree):
#   SKIP_PULL=1 bash deploy/deploy-backend.sh
#
set -euo pipefail

APP_ROOT=/var/www/resume
BACKEND="$APP_ROOT/backend"
VENV="$BACKEND/venv"
PY=python3.12
PM2_NAME=resume-backend
HEALTH_URL=http://127.0.0.1:8100/

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Two-stage self-update.
#
# `git reset --hard` rewrites THIS script while bash is still reading it, which
# can make the shell execute garbage. So stage 1 syncs the tree and then re-execs
# the freshly pulled copy as stage 2, which does the actual work.
# ---------------------------------------------------------------------------
if [[ "${STAGE:-1}" == "1" && "${SKIP_PULL:-0}" != "1" ]]; then
  log "Syncing $APP_ROOT to origin/main"
  git -C "$APP_ROOT" fetch --prune origin
  git -C "$APP_ROOT" reset --hard origin/main
  STAGE=2 exec bash "$APP_ROOT/deploy/deploy-backend.sh" "$@"
fi

cd "$BACKEND"

# ---------------------------------------------------------------------------
# Preflight. Fail before touching a running process, not halfway through.
# ---------------------------------------------------------------------------
command -v "$PY" >/dev/null || die "$PY not found — run deploy/setup-vps.sh first"
command -v pdflatex >/dev/null || die "pdflatex not found — run deploy/setup-vps.sh first"
[[ -f "$BACKEND/.env" ]] || die "$BACKEND/.env is missing (it is gitignored — create it by hand, see deploy/README.md)"

# ---------------------------------------------------------------------------
# Virtualenv + dependencies.
# ---------------------------------------------------------------------------
if [[ ! -x "$VENV/bin/python" ]]; then
  log "Creating virtualenv ($PY)"
  "$PY" -m venv "$VENV"
fi

log "Installing dependencies"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet -r requirements.txt

# Import-check before restarting. A syntax error or missing dep surfaces here,
# while the OLD process is still happily serving traffic.
log "Import check"
"$VENV/bin/python" -c "from app.main import app" \
  || die "app.main failed to import — NOT restarting, old version still live"

# ---------------------------------------------------------------------------
# Start or reload under PM2. reload = zero-downtime; start = first deploy.
# ---------------------------------------------------------------------------
if pm2 describe "$PM2_NAME" >/dev/null 2>&1; then
  log "Reloading PM2 process $PM2_NAME"
  pm2 reload "$PM2_NAME" --update-env
else
  log "Starting PM2 process $PM2_NAME (first run)"
  pm2 start "$APP_ROOT/deploy/ecosystem.config.cjs"
fi
pm2 save --force >/dev/null

# ---------------------------------------------------------------------------
# Health gate. init_db() applies schema.sql against Neon on boot, so a bad
# DATABASE_URL shows up right here rather than as a mystery 500 later.
# ---------------------------------------------------------------------------
log "Waiting for health check"
for i in $(seq 1 30); do
  if curl -fsS --max-time 3 "$HEALTH_URL" >/dev/null 2>&1; then
    log "Healthy: $(curl -fsS "$HEALTH_URL")"
    exit 0
  fi
  sleep 2
done

printf '\n--- last 40 log lines ---\n'
pm2 logs "$PM2_NAME" --lines 40 --nostream || true
die "backend did not become healthy within 60s"
