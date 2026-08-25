# Running Resume Builder on Windows

The Mac equivalents of these scripts live in [`mac/`](../mac/).

## One-time setup

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\install.ps1
```

Or just double-click **`windows\install.bat`**.

This creates `backend\venv`, installs the Python and npm dependencies, and
creates `backend\.env` from the template if it does not exist yet.

## Every day

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\start.ps1
```

Or double-click **`windows\start.bat`**. Two PowerShell windows open:

- backend  -> http://localhost:8000 (API docs at `/docs`)
- frontend -> http://localhost:5173

Close the windows or press `Ctrl+C` in each to stop.

## Why `-ExecutionPolicy Bypass`?

Windows blocks unsigned `.ps1` files by default. The flag applies to that one
process only -- it needs no admin rights and changes nothing system-wide. The
`.bat` launchers pass it for you, which is why double-clicking works.

## Prerequisites

| Tool | Check | Install |
|---|---|---|
| Python 3.9+ | `py -3 --version` | <https://www.python.org/downloads/windows/> (tick *Add python.exe to PATH*) |
| Node.js 18+ | `node --version` | <https://nodejs.org/> |
| LaTeX | `pdflatex --version` | Docker shim (see below) **or** `winget install MiKTeX.MiKTeX` |

> **Do not rely on `python3` on Windows.** It usually resolves to the Microsoft
> Store stub in `WindowsApps`, which opens the Store instead of running Python.
> The scripts use the `py` launcher instead.

### LaTeX

PDF compilation shells out to `pdflatex`, so nothing compiles until LaTeX is
available. There are two routes.

#### Option A -- Docker shim (recommended)

Production (`resume.thetan.in`) apt-installs a specific set of TeX Live packages
onto Ubuntu 22.04 -- see `deploy/setup-vps.sh`. This route reproduces that set
**exactly**, so a resume that compiles here compiles there. Requires Docker
Desktop; no system LaTeX at all.

Build the image once (~2 GB, several minutes):

```powershell
docker build -f docker/latex.Dockerfile -t resume-latex docker/
```

Then point `backend\.env` at the shim:

```
PDFLATEX_PATH=C:\Buildesume_builder\windows\pdflatex.cmd
```

`windows\pdflatex.cmd` runs the real engine inside a throwaway container,
bind-mounting the backend's per-compile temp dir at `/work`. The backend still
runs **natively** in the venv -- only the LaTeX engine is containerised, which
mirrors production, where uvicorn also runs natively (under PM2).

Costs roughly half a second of container startup per compile. A `/generate` can
compile up to 3 times via the repair loop, well inside the 20 s
`COMPILE_TIMEOUT`. Docker Desktop must be running, or compiles fail with a
Docker error in the LaTeX log.

#### Option B -- MiKTeX natively

Simpler and faster per compile, but the package set is **not** the same as the
VPS: MiKTeX resolves packages on demand from its own repository, so a document
can succeed locally and fail in production on a missing font or package. That
exact failure is the first entry in `deploy/README.md`'s troubleshooting list.

```powershell
winget install MiKTeX.MiKTeX
```

Open a **new** terminal afterwards so `PATH` refreshes, then confirm:

```powershell
pdflatex --version
```

Leave `PDFLATEX_PATH=pdflatex` for this route. Let the first compile finish --
MiKTeX is slower while it fetches packages. For everything up front, install
TeX Live instead: <https://tug.org/texlive/windows.html>.

## Environment variables

`backend\.env` (not committed -- created by `install.ps1`):

| Key | Windows value |
|---|---|
| `PDFLATEX_PATH` | Docker shim: `C:\Buildesume_builder\windows\pdflatex.cmd`. Native MiKTeX/TeX Live: `pdflatex` (they put it on `PATH`). **Never** the macOS `/usr/local/texlive/...` path. |
| `OPENAI_API_KEY` | your key. Required for `/match` and `/generate`. |
| `DATABASE_URL` | Neon Postgres string. Required for auth, profile, and dashboard. |
| `JWT_SECRET` | any long random string. Generate one with `py -3 -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `CORS_ORIGINS` | must include `http://localhost:5173` for the Vite dev server. |

`frontend\.env` (not committed) is **local dev only** and must use the absolute
backend URL:

```
VITE_API_BASE_URL=http://localhost:8000
```

`frontend\.env.production` is a separate, committed file that correctly uses
`VITE_API_BASE_URL=/api` for the VPS deploy, where Nginx proxies `/api/` to the
backend. Do not copy that value into `frontend\.env` -- the Vite dev server has
no such proxy, so every API call would 404. `install.ps1` warns if it finds this.

Vite bakes `VITE_*` values in at **build** time, so changing them needs a
restart of the dev server (or a rebuild), not just a page refresh.
