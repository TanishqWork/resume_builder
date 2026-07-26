#!/usr/bin/env bash
#
# Build the React/Vite frontend ON THE VPS and publish it to the nginx root.
#
# This is the MANUAL FALLBACK path. Normally CI builds the bundle on a GitHub
# runner and rsyncs only dist/ over — that keeps this 2 vCPU box free during
# deploys. Use this script when Actions is unavailable:
#
#   bash /var/www/resume/deploy/deploy-frontend.sh
#
# Skip the git pull (tree already synced):
#   SKIP_PULL=1 bash deploy/deploy-frontend.sh
#
set -euo pipefail

APP_ROOT=/var/www/resume
FRONTEND="$APP_ROOT/frontend"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$*" >&2; exit 1; }

# Same two-stage trick as deploy-backend.sh: don't let git rewrite the script
# that is currently executing.
if [[ "${STAGE:-1}" == "1" && "${SKIP_PULL:-0}" != "1" ]]; then
  log "Syncing $APP_ROOT to origin/main"
  git -C "$APP_ROOT" fetch --prune origin
  git -C "$APP_ROOT" reset --hard origin/main
  STAGE=2 exec bash "$APP_ROOT/deploy/deploy-frontend.sh" "$@"
fi

cd "$FRONTEND"
command -v npm >/dev/null || die "npm not found"

# .env.production supplies VITE_API_BASE_URL=/api and is BAKED IN at build time.
# Changing the API URL therefore requires a rebuild, not a restart.
[[ -f .env.production ]] || die ".env.production missing — the bundle would default to http://localhost:8000"

log "Installing dependencies (npm ci)"
npm ci --no-audit --no-fund

# ---------------------------------------------------------------------------
# Build into dist.new, NOT dist.
#
# nginx serves directly out of dist/. Building into it in place would leave the
# live site half-written for the duration of the build — old index.html pointing
# at assets that have just been deleted. So we build beside it and swap.
# ---------------------------------------------------------------------------
log "Building into dist.new"
rm -rf dist.new
npm run build -- --outDir dist.new --emptyOutDir
[[ -f dist.new/index.html ]] || die "build produced no dist.new/index.html"

# ---------------------------------------------------------------------------
# Atomic-ish publish: two renames on the same filesystem, microseconds apart.
# dist.prev is kept as a one-command rollback (see deploy/README.md).
# ---------------------------------------------------------------------------
log "Publishing"
rm -rf dist.prev
[[ -d dist ]] && mv dist dist.prev
mv dist.new dist

log "Done — https://resume.thetan.in"
