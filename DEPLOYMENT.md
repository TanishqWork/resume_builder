# DEPLOYMENT  Putting the LaTeX Resume Builder Online (with Docker)

> **⚠️ SUPERSEDED — background reading only.**
> Production now runs on a self-hosted VPS at **https://resume.thetan.in**
> (Nginx + PM2 + Neon), deployed by GitHub Actions. The Vercel and Render
> setup this document describes has been retired.
> **The current runbook is [deploy/README.md](deploy/README.md).**
> `backend/Dockerfile` is kept as the reference for which TeX Live packages the
> app needs — keep it in step with `deploy/setup-vps.sh`.

> Goal: Take the working app from DEVELOPMENT.md and put it on the internet so it's
> a real website. The one NEW thing here is **Docker**. Read DEVELOPMENT.md first 
> the app (React + Python + LaTeX) is exactly the same; deployment just wraps it.

---

## What changes from development → deployment

Same app, two differences:
1. The parts now live on **hosting companies' computers**, not my Mac.
2. The backend gets wrapped in **Docker** so LaTeX comes along reliably.

```
React frontend  →  hosted on Vercel / Netlify        (free)
Python + LaTeX  →  hosted on Render / Railway / Fly    (free tier, or a few $)
   (inside Docker)
```

They talk to each other over the internet.

---

## The ONE catch with LaTeX on a server 🔑

LaTeX is **big software** (~1–4 GB) and must be **physically installed** on whatever
computer runs the Python backend.

- My Mac: I installed it myself, no problem.
- A host's server: it comes **blank** (Python only, no LaTeX).
  - Some hosts let me run a script to install LaTeX → Docker not strictly required.
  - Some hosts **block** installing big software → **Docker is the workaround.**

Practical truth: **Docker is the easiest, most reliable way to deploy**, because it
removes all guesswork about whether LaTeX is present.

---

## What Docker actually is

Docker = a **"lunchbox" / "food truck"**: a sealed box that contains my Python code
**and** LaTeX together, so wherever I ship it, LaTeX always comes along.

- Build the box **once** → it runs **identically** on my Mac, a free host, or a $5 server.
- This kills the "but the server doesn't have LaTeX" problem forever.

### Important facts about Docker

- **Docker the tool is FREE.** Free to install, free to use for personal projects.
  (Only big companies pay for a business license  irrelevant to me.)
- **Docker has nothing to do with speed.** Same speed with or without it.
- The only thing that might cost money is the **server/host** that runs the box 
  and even that has **free tiers**.

```
Docker          = free, always
The host/server = the only thing that might cost money (and has free tiers)
```

---

## How Docker works  the Dockerfile (the recipe)

A `Dockerfile` is a tiny text file describing how to build the box:

```
1. Start with a basic Linux computer
2. Install Python
3. Install LaTeX        ← THIS line is the whole reason Docker helps
4. Copy my Python code in
5. When started, run the waiter (Python)
```

- Write it **once** per project, then basically never touch it again.
- Build the box:  `docker build`
- Run the box:    `docker run`
- First build is **slow** (installing LaTeX takes minutes). After that, fast.
- The #1 thing people fight with: getting the **LaTeX install line right**
  (which packages). That's the part to get a working version of and then leave alone.

### 🔑 The LaTeX line MUST match development

On my Mac I use **BasicTeX + 3 collections** (see DEVELOPMENT.md → "LaTeX setup").
The Docker box runs **Linux**, so it can't use BasicTeX/MacTeX (those are Mac-only) 
instead it installs **TeX Live** and then adds the **exact same three collections** via
`tlmgr`. Same collections in → same fonts/packages → **same PDF** in dev and in production.

```dockerfile
# Inside the Dockerfile  install LaTeX to match my Mac setup
RUN apt-get update && apt-get install -y --no-install-recommends \
      texlive-base texlive-latex-recommended texlive-xetex && \
    tlmgr init-usertree 2>/dev/null; \
    tlmgr install \
      collection-latexextra \
      collection-fontsrecommended \
      collection-fontsextra
# (Alternatively, start FROM a `texlive/texlive` base image which already bundles these.)
```

- `pdflatex` is the compiler (matches dev  my resume uses pdfTeX features).
- These collections add ~900 MB–1 GB to the image  expected, not a problem.
- ⚠️ If I ever add a package on my Mac, **add the same line here** so they stay in sync.

---

## Full architecture (deployed, with Docker)

```
┌─────────────────────────── USER'S BROWSER ───────────────────────────┐
│   REACT FRONTEND  (hosted on Vercel / Netlify, free)                  │
│   code editor  +  PDF preview  +  Download button                    │
└──────────────┬──────────────────────────▲────────────────────────────┘
               │  sends LaTeX code         │  PDF sent back
               ▼                           │
┌────────────── DOCKER BOX (the food truck)  hosted on Render/Railway ─┐
│                                                                       │
│   PYTHON BACKEND (the waiter)                                         │
│   1. receives the LaTeX code                                         │
│   2. saves it as resume.tex                                          │
│   3. runs pdflatex resume.tex                                        │
│   4. gets resume.pdf                                                 │
│   5. sends the PDF back to React                                     │
│              │                                                        │
│              ▼                                                        │
│   LaTeX (the chef) ── installed INSIDE the Docker box ──             │
│   turns resume.tex → resume.pdf                                       │
└───────────────────────────────────────────────────────────────────────┘
```

The flow is the same 7 steps as development  only the homes changed, and LaTeX now
lives inside the Docker box instead of directly on the machine.

---

## Where to deploy (free / cheap)

**Frontend (React)**  easy, truly free:
- **Vercel** or **Netlify**  free, ~2 minutes.

**Backend (Python + LaTeX, in Docker)**  needs a host that runs Docker:
- **Render**  free tier, supports Docker ⭐ good starting point.
- **Railway**  small free/cheap credits, very easy.
- **Fly.io**  free allowance, supports Docker.
- **Cheap VPS** (~$4–6/month, Hetzner/DigitalOcean)  most control; here I could even
  install LaTeX directly and skip Docker if I wanted.

Cost summary: **frontend free + backend free tier = $0 to start.** Pay a few $/month
only if the app outgrows free limits (a good problem to have).

---

## How hard is Docker, really?

| Task                                    | Difficulty           | How often            |
|-----------------------------------------|----------------------|----------------------|
| Installing Docker on my Mac             | 🟢 Easy (click install) | Once, ever        |
| Writing the Dockerfile                  | 🟡 Medium first time    | Once per project  |
| Building & running the box locally      | 🟢 Easy (one command)   | Copy-paste        |
| Deploying to a host                     | 🟡 Medium first time    | Once to set up    |
| Updating after it works                 | 🟢 Very easy (push code)| Forever after     |

**Key reassurance:** the difficulty is **front-loaded**  fight it once during setup,
then it "just works" forever. Day-to-day, I forget Docker exists.

---

## Roadmap

```
Phase 1 (DEVELOPMENT.md):  Mac + LaTeX + Python + React   →  no Docker, build & test
Phase 2 (this file):       Wrap backend in Docker          →  test box locally
Phase 3:                   Deploy → React to Vercel, Docker box to Render
After that:                Every update → push to GitHub → auto-redeploys ✨
```

---

## One-breath recap

- Deployment = same app from DEVELOPMENT.md, now living on hosts + wrapped in Docker.
- **Docker** = a free box carrying Python + LaTeX together so LaTeX is always present.
- Docker is **free**; only the **host** might cost money (and has free tiers).
- The `Dockerfile` is a recipe whose key line is **"install LaTeX"**  and it must install
  the **same 3 collections** as my Mac (DEVELOPMENT.md) so the PDF comes out identical.
- Deploy: **React → Vercel (free)**, **Docker box → Render (free tier)**.
- Don't think about Docker until Phase 2  build locally first.
