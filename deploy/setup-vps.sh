#!/usr/bin/env bash
#
# One-time VPS provisioning for resume.thetan.in (Hostinger KVM 2, Ubuntu 22.04).
#
# Idempotent: safe to re-run. It never touches the existing quiz-backend /
# next-app deployments, and never installs over the system python3.10 that
# Ubuntu's own tooling depends on.
#
# Usage (as root on the VPS):
#   bash /var/www/resume/deploy/setup-vps.sh
#
# Optional:
#   ENABLE_SWAP=1 bash setup-vps.sh    # also create a 2 GB swapfile
#
set -euo pipefail

APP_ROOT=/var/www/resume
PY=python3.12
ENABLE_SWAP=${ENABLE_SWAP:-0}

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (or with sudo)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1) Python 3.12 via deadsnakes.
#
# Ubuntu 22.04 ships 3.10. The backend's Docker image (proven on Render) is
# python:3.12-slim, so we match it exactly rather than hoping every pinned
# wheel in requirements.txt has a 3.10 build. deadsnakes installs alongside
# the system python3 — it does NOT replace it.
# ---------------------------------------------------------------------------
if ! command -v "$PY" >/dev/null 2>&1; then
  log "Installing Python 3.12 (deadsnakes PPA)"
  apt-get update
  apt-get install -y --no-install-recommends software-properties-common
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update
  apt-get install -y --no-install-recommends \
    python3.12 python3.12-venv python3.12-dev
else
  log "Python 3.12 already present: $($PY --version)"
fi

# ---------------------------------------------------------------------------
# 2) LaTeX.
#
# The backend shells out to pdflatex (see app/services/latex_service.py).
# These are the SAME package names as backend/Dockerfile, so a resume compiled
# here is byte-comparable to what Render produced:
#   texlive-latex-extra        ~ collection-latexextra
#   texlive-fonts-recommended  ~ collection-fontsrecommended
#   texlive-fonts-extra        ~ collection-fontsextra (fontawesome5, etc.)
#
# This is the slow step: ~2 GB download, several minutes. One time only.
# ---------------------------------------------------------------------------
if ! command -v pdflatex >/dev/null 2>&1; then
  log "Installing TeX Live (~2 GB, this takes a while)"
  apt-get install -y --no-install-recommends \
    texlive-latex-base \
    texlive-latex-recommended \
    texlive-latex-extra \
    texlive-fonts-recommended \
    texlive-fonts-extra \
    texlive-xetex
else
  log "pdflatex already present: $(command -v pdflatex)"
fi

# ---------------------------------------------------------------------------
# 3) Supporting tools. rsync is how CI ships the frontend build.
# ---------------------------------------------------------------------------
log "Ensuring git / rsync / curl"
apt-get install -y --no-install-recommends git rsync curl ca-certificates

# ---------------------------------------------------------------------------
# 4) Directories.
# ---------------------------------------------------------------------------
log "Creating $APP_ROOT and log dir"
mkdir -p "$APP_ROOT"
mkdir -p /var/log/resume

# ---------------------------------------------------------------------------
# 5) Optional swap. The box reports Swap: 0. We build the frontend in GitHub
#    Actions (not here), so this is precautionary headroom for pdflatex bursts
#    on 2 vCPU rather than a requirement.
# ---------------------------------------------------------------------------
if [[ "$ENABLE_SWAP" == "1" ]]; then
  if ! swapon --show | grep -q '/swapfile'; then
    log "Creating 2 GB swapfile"
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  else
    log "Swapfile already active"
  fi
fi

# ---------------------------------------------------------------------------
# 6) PM2 log rotation. LaTeX is chatty; without this the logs grow unbounded.
# ---------------------------------------------------------------------------
if command -v pm2 >/dev/null 2>&1; then
  if ! pm2 list | grep -q pm2-logrotate; then
    log "Installing pm2-logrotate"
    pm2 install pm2-logrotate || true
    pm2 set pm2-logrotate:max_size 10M || true
    pm2 set pm2-logrotate:retain 7 || true
  fi
fi

# ---------------------------------------------------------------------------
# 7) Report.
# ---------------------------------------------------------------------------
log "Verification"
printf '  python3.12 : %s\n' "$($PY --version 2>&1)"
printf '  pdflatex   : %s\n' "$(command -v pdflatex || echo MISSING)"
printf '  node       : %s\n' "$(command -v node >/dev/null && node --version || echo MISSING)"
printf '  pm2        : %s\n' "$(command -v pm2 >/dev/null && pm2 --version || echo MISSING)"
printf '  nginx      : %s\n' "$(command -v nginx >/dev/null && nginx -v 2>&1 || echo MISSING)"
printf '  free disk  : %s\n' "$(df -h / | awk 'NR==2{print $4}')"

cat <<'NEXT'

Provisioning done. Next steps:

  1. Clone the repo (if not already):
       cd /var/www/resume
       git clone https://github.com/TanishqTapAcademy/resume_builder.git .

  2. Create backend/.env  (NEVER committed — see deploy/README.md for the template)

  3. First backend deploy:
       bash /var/www/resume/deploy/deploy-backend.sh

  4. Install the nginx vhost:
       ln -sf /var/www/resume/deploy/nginx/resume.thetan.in.conf \
              /etc/nginx/sites-enabled/resume.thetan.in.conf
       nginx -t && systemctl reload nginx

  5. TLS:
       certbot --nginx -d resume.thetan.in

NEXT
