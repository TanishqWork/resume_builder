"""Application configuration (BACKEND.md §4 — no magic values in logic).

All environment-specific values live here, sourced from env vars with sane,
platform-neutral dev defaults. In production these are overridden via
backend/.env on the VPS (see deploy/README.md — DEPLOYMENT.md is superseded).
"""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Path to the LaTeX engine. Bare command name by default: correct wherever
    # pdflatex is on PATH — the production VPS (/usr/bin/pdflatex, apt-installed
    # by deploy/setup-vps.sh), Linux, and Windows with MiKTeX/TeX Live.
    # Override in .env when it is NOT on PATH:
    #   macOS BasicTeX: /usr/local/texlive/2026basic/bin/universal-darwin/pdflatex
    #   Windows + Docker shim: ...\windows\pdflatex.cmd (see windows/README.md)
    pdflatex_path: str = "pdflatex"

    # Kill a compile that runs longer than this (seconds) — guards runaway/malicious input.
    compile_timeout: int = 20

    # Reject input larger than this many bytes.
    max_code_bytes: int = 1_000_000

    # Browser origins allowed to call this API (React dev servers by default).
    cors_origins: list[str] = ["http://localhost:5173", "http://localhost:3000"]

    # --- AI layer (see LLM.md) ---------------------------------------------
    # OpenAI API key. Server-side ONLY — never sent to the frontend, never
    # committed. Empty default so the app still boots without AI configured;
    # AI endpoints fail clearly until this is set in .env.
    openai_api_key: str = ""

    # Model names per tier (LLM.md §2). Names live here, never in logic.
    gen_model: str = "gpt-5"        # flagship: full resume generation + self-repair
    edit_model: str = "gpt-4.1"     # fast tier for post-gen, section-scoped chat edits

    # Match tier picks a model by input size (LLM.md §5): small/easy inputs use the
    # fast mini; large inputs use the full model for better long-context accuracy.
    gap_model_small: str = "gpt-4.1-mini"
    gap_model_large: str = "gpt-4.1"
    gap_token_threshold: int = 6000   # est. input tokens; above this -> large model
                                      # (revisited properly in the RAG phase — LLM.md §7)
    chars_per_token: int = 4          # rough token estimate: len(text) // this

    # Path to the structured profile store — the single source of truth (LLM.md §1).
    # Package-relative default (app/data/profile.json); override via env if needed.
    profile_path: str = str(Path(__file__).resolve().parent.parent / "data" / "profile.json")

    # Match gate threshold (percent). >= unlocks generation; < advises only.
    match_threshold: int = 70

    # Verify & repair loop caps (LLM.md §4).
    max_repair_retries: int = 2     # per-check retries (compile / one-page)
    max_total_model_calls: int = 6  # hard ceiling on model calls per /generate

    # ai_client resilience — network-retry tunables (distinct from the repair retries).
    ai_max_retries: int = 3            # attempts per model on transient errors
    ai_backoff_base: float = 0.5       # seconds; exponential: base * 2**(attempt-1)
    fallback_model: str = "gpt-4o-mini"  # tried if a tier's primary model keeps failing
    match_temperature: float = 0.0     # low -> stable match score (LLM.md §5)

    # --- Accounts & database (multi-user) ----------------------------------
    # Postgres connection string (Neon). Server-side ONLY, set in .env.
    # Empty default lets the app import without a DB; DB-backed routes fail clearly.
    database_url: str = ""

    # JWT auth. Secret MUST be overridden in .env in any real deployment — the
    # default is dev-only and clearly unsafe to ship. HS256 is symmetric (one secret).
    jwt_secret: str = "dev-only-insecure-change-me"
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 60 * 24 * 7  # 7 days — "stay logged in"

    # --- Profile (seeding + chat) ------------------------------------------
    # Resume PDF upload size cap (bytes) for the seeding endpoint.
    max_pdf_bytes: int = 5_000_000
    # Profile-chat messages allowed per user per day (cost guard). Counter in DB;
    # conversation itself is never stored (session-only, frontend-held).
    chat_daily_limit: int = 10

    # --- Public landing demo (cost guards) ---------------------------------
    # Resume extractions allowed per IP per day (the demo's gpt-4.1 calls). The
    # tailored GENERATION is separately limited to one per IP for the lifetime.
    demo_extract_daily_limit: int = 5


@lru_cache
def get_settings() -> Settings:
    """Cached settings singleton — import this, don't instantiate Settings directly."""
    return Settings()
