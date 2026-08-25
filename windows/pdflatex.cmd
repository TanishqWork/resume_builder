@echo off
REM ---------------------------------------------------------------------------
REM pdflatex.cmd - LaTeX engine shim for LOCAL DEVELOPMENT on Windows.
REM
REM backend/app/services/latex_service.py runs the configured engine as a plain
REM subprocess, with cwd set to a fresh temp dir that already holds resume.tex.
REM This script stands in for that binary and runs the real engine inside
REM Docker, so a Windows box needs no system LaTeX yet still compiles against
REM the SAME TeX Live package set as the production VPS.
REM
REM Production does NOT use this, or Docker at all - the VPS apt-installs
REM TeX Live directly (deploy/setup-vps.sh) and sets PDFLATEX_PATH=/usr/bin/pdflatex.
REM
REM Wire it up in backend\.env:
REM     PDFLATEX_PATH=C:\Build\resume_builder\windows\pdflatex.cmd
REM
REM Build the image first (once):
REM     docker build -f docker/latex.Dockerfile -t resume-latex docker/
REM
REM   %%CD%%  - the temp dir uvicorn set as cwd. Mounting it at /work puts
REM           resume.tex where the engine expects it and drops resume.pdf
REM           back onto the host, which is what latex_service.py then reads.
REM   %%~n0%% - this file's own basename, so a copy named xelatex.cmd runs xelatex.
REM   %%*    - forwards latex_service.py's flags (-interaction, -halt-on-error,
REM           -no-shell-escape) through verbatim.
REM ---------------------------------------------------------------------------

docker run --rm -v "%CD%:/work" -w /work resume-latex %~n0 %*
exit /b %ERRORLEVEL%
