# LaTeX engine image for LOCAL DEVELOPMENT only.
#
# Production (resume.thetan.in) does NOT run this — or any — container. The VPS
# apt-installs TeX Live straight onto Ubuntu 22.04 via deploy/setup-vps.sh, and
# uvicorn runs natively under PM2. This image exists so a dev machine without a
# system LaTeX (Windows, or a clean Mac) can still compile with the EXACT same
# package set the VPS has, instead of a near-miss like MiKTeX.
#
# Base is ubuntu:22.04 deliberately — same distro release as the VPS, so the
# TeX Live version matches too, not just the package names.
#
# The package list below MUST stay identical to deploy/setup-vps.sh. If a resume
# ever needs a new collection, add it in THREE places: here, setup-vps.sh, and
# backend/Dockerfile (the Render-era reference spec).
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
      texlive-latex-base \
      texlive-latex-recommended \
      texlive-latex-extra \
      texlive-fonts-recommended \
      texlive-fonts-extra \
      texlive-xetex \
    && rm -rf /var/lib/apt/lists/*

# The backend bind-mounts its per-compile temp dir here and runs with cwd=/work.
WORKDIR /work

# No ENTRYPOINT on purpose: windows/pdflatex.cmd passes the engine name and all
# of latex_service.py's flags through verbatim, so the same image serves
# pdflatex, xelatex, or lualatex without needing a variant per engine.
