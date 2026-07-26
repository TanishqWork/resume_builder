# VPS Deployment Runbook — resume.thetan.in

Self-hosted on Hostinger KVM 2 (Ubuntu 22.04), replacing the previous
Vercel + Render setup. The database stays on **Neon** — nothing runs Postgres locally.

```
                          Internet
                              │
                              ▼
                     Nginx (80 / 443)  ── resume.thetan.in
                    ┌─────────┴──────────┐
                    │                    │
              /  (static)            /api/  (proxy, prefix stripped)
                    │                    │
    /var/www/resume/frontend/dist   127.0.0.1:8100
                                    PM2: resume-backend
                                    uvicorn → FastAPI → pdflatex
                                                      → Neon Postgres
```

Sits alongside the existing `quiz-backend` (PM2) and `next-app` (PM2) without
touching either.

---

## Layout on the server

```
/var/www/resume/                  ← single git clone of the whole repo
├── backend/
│   ├── venv/                     ← python3.12 virtualenv (gitignored)
│   └── .env                      ← SECRETS, created by hand, never committed
├── frontend/
│   ├── dist/                     ← live bundle, nginx root
│   └── dist.prev/                ← previous bundle, kept for rollback
└── deploy/                       ← the scripts in this folder
```

| Thing | Value |
|---|---|
| Domain | `resume.thetan.in` |
| Backend port | `8100`, bound to `127.0.0.1` only |
| PM2 process | `resume-backend` |
| Python | `3.12` from deadsnakes (system `python3.10` untouched) |
| Nginx vhost | `deploy/nginx/resume.thetan.in.conf` → symlinked into `sites-enabled` |
| Logs | `/var/log/resume/`, `/var/log/nginx/resume.*.log` |

---

## First-time setup

### 1. DNS
Hostinger DNS for `thetan.in`:

```
A    resume    <VPS_IP>    TTL 300
```

Verify before continuing — certbot will fail otherwise:
```bash
dig +short resume.thetan.in
```

### 2. Provision the box
```bash
ssh root@<VPS_IP>
mkdir -p /var/www/resume && cd /var/www/resume
git clone https://github.com/TanishqWork/resume_builder.git .
bash deploy/setup-vps.sh          # add ENABLE_SWAP=1 to also create 2 GB swap
```

Installs Python 3.12, TeX Live (~2 GB — the slow step, once), rsync, and
pm2-logrotate. Idempotent, re-runnable.

### 3. Secrets
`backend/.env` is gitignored and must be written by hand, once:

```bash
nano /var/www/resume/backend/.env
```

```ini
# --- Database (Neon — same connection string the Render service used) --------
DATABASE_URL=postgresql://USER:PASS@HOST/DB?sslmode=require

# --- AI ---------------------------------------------------------------------
OPENAI_API_KEY=sk-...

# --- Auth -------------------------------------------------------------------
# Generate: python3.12 -c "import secrets; print(secrets.token_urlsafe(48))"
JWT_SECRET=<long random string>

# --- LaTeX ------------------------------------------------------------------
# REQUIRED. The default in app/core/config.py is a macOS path and will fail here.
PDFLATEX_PATH=/usr/bin/pdflatex
COMPILE_TIMEOUT=20

# --- CORS -------------------------------------------------------------------
# Belt-and-braces only: the frontend calls /api on the SAME origin, so the
# browser never sends a preflight. Kept correct in case the API is ever called
# from another host.
CORS_ORIGINS=["https://resume.thetan.in"]
```

```bash
chmod 600 /var/www/resume/backend/.env
```

Confirm the LaTeX path matches reality: `which pdflatex`

### 4. Backend up
```bash
bash /var/www/resume/deploy/deploy-backend.sh
pm2 save
pm2 startup        # only if not already configured for the other apps
```

Expect `{"status":"ok","service":"resume-builder-backend"}`. On boot the app
applies `backend/app/db/schema.sql` against Neon idempotently — no migration step.

### 5. Frontend up
```bash
bash /var/www/resume/deploy/deploy-frontend.sh
```

(One time only — after this, CI builds on a GitHub runner and rsyncs `dist/`.)

### 6. Nginx
```bash
ln -sf /var/www/resume/deploy/nginx/resume.thetan.in.conf \
       /etc/nginx/sites-enabled/resume.thetan.in.conf
nginx -t && systemctl reload nginx
```

`nginx -t` first, always — a broken config would take down `quiz-backend` and
`next-app` too, since they share this Nginx.

### 7. TLS
```bash
certbot --nginx -d resume.thetan.in
```

Certbot **edits the vhost file in place**, adding the `:443` server block and
the HTTP→HTTPS redirect. That edit is expected — see *Editing the nginx config
after certbot* below.

### 8. CI/CD
Add these under GitHub → Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `VPS_HOST` | VPS IP |
| `VPS_USER` | `root` |
| `VPS_SSH_KEY` | private key (whole file, incl. `BEGIN`/`END` lines) |
| `VPS_PORT` | optional, defaults to `22` |

Generate a deploy-only keypair **on the VPS**:
```bash
ssh-keygen -t ed25519 -C "github-actions-resume" -f ~/.ssh/gh_deploy -N ""
cat ~/.ssh/gh_deploy.pub >> ~/.ssh/authorized_keys
cat ~/.ssh/gh_deploy          # <-- paste this into VPS_SSH_KEY, then delete it
rm ~/.ssh/gh_deploy
```

Then trigger the pipeline: Actions → **Deploy to VPS** → Run workflow.

### 9. Decommission Vercel + Render
**Only after a full click-through on `https://resume.thetan.in` passes** — see
*Cutover checklist*.

- Vercel → project → Settings → delete
- Render → service → Settings → suspend for 48 h as a rollback, then delete
  (also frees the ~4 GB LaTeX image)
- Remove `frontend/vercel.json` from the repo

---

## Everyday deploys

Push to `main`. The pipeline decides what to do:

| Changed | What runs |
|---|---|
| `frontend/**` | build on GitHub runner → rsync `dist/` → atomic swap |
| `backend/**` | `pip install` → import-check → `pm2 reload` |
| `deploy/**` | both |

Then it smoke-tests the live site (`/api/` health, `/`, and `/login` for the SPA
fallback) and fails loudly if anything is down.

### Manual deploy (Actions unavailable)
```bash
ssh root@<VPS_IP>
bash /var/www/resume/deploy/deploy-backend.sh     # pulls, installs, reloads
bash /var/www/resume/deploy/deploy-frontend.sh    # pulls, builds ON the VPS, swaps
```

Both scripts self-update: they `git reset --hard origin/main` and then re-exec
the freshly pulled copy of themselves, so a mid-run `git` operation can't
corrupt the running script.

### Nginx config changes
Pushing `deploy/nginx/*.conf` updates the file in the repo clone. Because
`sites-enabled` is a **symlink** into that clone, the new config is on disk
immediately — but Nginx does not reload itself:
```bash
nginx -t && systemctl reload nginx
```

---

## Rollback

**Frontend** — previous bundle is one rename away:
```bash
cd /var/www/resume/frontend
rm -rf dist.bad && mv dist dist.bad && mv dist.prev dist
```

**Backend** — check out the last good commit and redeploy:
```bash
cd /var/www/resume
git log --oneline -10
git reset --hard <good-sha>
SKIP_PULL=1 bash deploy/deploy-backend.sh
```
(`SKIP_PULL=1`, or the script will pull `main` straight back over your rollback.)

---

## Troubleshooting

**`pdflatex` fails on the VPS but worked on Render**
The likeliest cause of a post-migration break: a font/package present in the
Docker image but missing here. Compile the default template by hand to see the
real LaTeX error:
```bash
cd /tmp && cp /var/www/resume/backend/app/data/default_template.tex t.tex
pdflatex -interaction=nonstopmode t.tex | tail -40
```
Missing package → `apt-get install texlive-<collection>`, then add it to
`deploy/setup-vps.sh` **and** `backend/Dockerfile` so the two stay in step.

**504 on `/generate`**
Nginx read timeout. The vhost sets `proxy_read_timeout 300s` because a gpt-5
generation plus pdflatex plus up to 2 repair retries can exceed Nginx's 60s
default. Confirm the running config has it: `nginx -T | grep -A3 proxy_read`.

**413 on PDF upload**
`client_max_body_size` in the `/api/` block; must exceed the app's 5 MB
`max_pdf_bytes`. Set to 6 MB.

**Everyone shares one demo lock / demo gate is bypassable**
`app/api/routes/demo.py` trusts the *first* `X-Forwarded-For` hop. The vhost
sets `X-Forwarded-For $remote_addr` (overwrite, **not**
`$proxy_add_x_forwarded_for`) so it is always the real peer and cannot be
forged. If you ever put Cloudflare in front, revisit this.

Reset a demo lock for testing:
```sql
DELETE FROM demo_usage WHERE ip_address = '<ip>';
DELETE FROM demo_rate  WHERE ip_address = '<ip>';
```

**Backend won't start**
```bash
pm2 logs resume-backend --lines 60
cd /var/www/resume/backend && venv/bin/python -c "from app.main import app"
```
Usually a missing/mistyped `.env` value — most often `DATABASE_URL`, since
`init_db()` runs at startup.

**Editing the nginx config after certbot**
Certbot rewrites the vhost in place, so the server copy diverges from the repo
copy. To change it: edit the **server** file
(`/etc/nginx/sites-enabled/resume.thetan.in.conf`), `nginx -t`, reload, then
port the same edit into `deploy/nginx/resume.thetan.in.conf` in the repo
*keeping* the certbot-added SSL lines out of it. Alternatively, re-symlink to
the repo copy and re-run `certbot --nginx -d resume.thetan.in`, which re-adds
the SSL block.

---

## Cutover checklist

Run against `https://resume.thetan.in` before deleting anything:

- [ ] Landing page loads; deep link `/login` returns the app, not a 404
- [ ] Sign up → log in → refresh keeps you logged in (`/auth/me` via `/api`)
- [ ] Seed profile by **pasting LaTeX**
- [ ] Seed profile by **uploading a PDF** (exercises the 6 MB nginx cap)
- [ ] Profile chat edit → approve
- [ ] Fit check returns a score
- [ ] **Generate a real resume** → PDF renders in the preview → downloads
      ← the single most important test; it's the one that exercises `pdflatex`
- [ ] Post-generation edit works
- [ ] Demo widget on the landing page works from a **fresh IP** (phone on mobile
      data), and is locked on the second attempt
- [ ] `pm2 logs resume-backend` shows no LaTeX warnings during generation
- [ ] `reboot` the box → both new and existing PM2 apps come back
- [ ] `https://` padlock valid, `http://` redirects

---

## Ops notes

- **2 vCPU.** `pdflatex` is CPU-bound and the box also runs `quiz-backend` and
  `next-app`. The PM2 config is deliberately 1 instance in fork mode. If
  `/generate` starts queueing, raise `instances` — but note `exec_mode:
  'cluster'` does **not** work for a non-Node binary, so run a second fork on a
  different port and load-balance in Nginx with `upstream` instead.
- **Swap is 0** by default on this box. `ENABLE_SWAP=1 bash deploy/setup-vps.sh`
  adds 2 GB. Not required (the frontend builds in CI, not here) but cheap insurance.
- **Temp files.** Check `ls /tmp | wc -l` periodically — LaTeX compiles create
  temp dirs, and a leak fills the disk over months.
- **Neon connection limits.** One uvicorn process holds one asyncpg pool. If you
  scale to multiple workers, check the pool size against Neon's free-tier cap.
- **Never open 8100.** `ss -tlnp | grep 8100` must show `127.0.0.1:8100`, never
  `0.0.0.0`.
