// All backend communication lives here (FRONTEND.md §0 rule 3).
// Components/hooks never call fetch directly — only this module does.

import { API_BASE_URL } from '../config'

// ── Auth token store ──────────────────────────────────────────────────────
// The JWT lives in localStorage so the session survives reloads. On boot the
// app calls getMe() to confirm it's still valid (the "/me" check).

const TOKEN_KEY = 'rb_token'
const USER_KEY = 'rb_user' // cached user for instant (optimistic) boot

export function getToken() {
  return localStorage.getItem(TOKEN_KEY)
}
export function setToken(token) {
  localStorage.setItem(TOKEN_KEY, token)
}
export function clearToken() {
  localStorage.removeItem(TOKEN_KEY)
  localStorage.removeItem(USER_KEY)
}

// Cache the last-known user so a reload can render immediately while /auth/me is
// re-validated in the background (the backend can be slow to wake from a cold start).
export function cacheUser(user) {
  if (user) localStorage.setItem(USER_KEY, JSON.stringify(user))
}
export function getCachedUser() {
  try {
    return JSON.parse(localStorage.getItem(USER_KEY))
  } catch {
    return null
  }
}

// Decode a JWT payload client-side (no verification — just to read claims for an
// optimistic boot). Returns null if the token is malformed.
function decodeJwt(token) {
  try {
    const payload = token.split('.')[1]
    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'))
    return JSON.parse(json)
  } catch {
    return null
  }
}

/** True if the token is missing, malformed, or its `exp` is in the past. */
export function isTokenExpired(token = getToken()) {
  const claims = token && decodeJwt(token)
  if (!claims?.exp) return true
  return claims.exp * 1000 <= Date.now()
}

/** A minimal user ({ id }) read straight from the token — no email, no network. */
export function userFromToken(token = getToken()) {
  const claims = token && decodeJwt(token)
  return claims?.sub ? { id: claims.sub } : null
}

/** Attach the Bearer token (if present) to a fetch options object. */
function authHeaders(extra = {}) {
  const token = getToken()
  return token ? { ...extra, Authorization: `Bearer ${token}` } : extra
}

/** Error thrown for auth failures; `status` carries the HTTP code. */
export class AuthError extends Error {
  constructor(message, status = 0) {
    super(message)
    this.name = 'AuthError'
    this.status = status
  }
}

// Pull a human message out of FastAPI's { detail } shape (string or 422 array).
async function readError(res, fallback) {
  try {
    const body = await res.json()
    const d = body.detail
    if (typeof d === 'string') return d
    if (Array.isArray(d) && d[0]?.msg) return d[0].msg
  } catch {
    /* fall through */
  }
  return fallback
}

const AUTH_UNREACHABLE = 'Could not reach the server. Is the backend running?'

/** Create an account. Returns { token, user }. */
export async function signup(email, password) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/auth/signup`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
  } catch {
    throw new AuthError(AUTH_UNREACHABLE)
  }
  if (res.ok) return res.json()
  throw new AuthError(await readError(res, 'Could not create account.'), res.status)
}

/** Log in. Returns { token, user }. */
export async function login(email, password) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    })
  } catch {
    throw new AuthError(AUTH_UNREACHABLE)
  }
  if (res.ok) return res.json()
  throw new AuthError(await readError(res, 'Incorrect email or password.'), res.status)
}

// ── Public landing demo (NO auth; profile is browser-held) ─────────────────

/** Error for demo calls. `status` 403 = free demo used, 429 = rate-limited. */
export class DemoError extends Error {
  constructor(message, status = 0) {
    super(message)
    this.name = 'DemoError'
    this.status = status
  }
}

/** Has this visitor's IP already used its one free demo? -> { used } */
export async function demoStatus() {
  try {
    const res = await fetch(`${API_BASE_URL}/demo/status`)
    if (res.ok) return res.json()
  } catch {
    /* treat as not-used; the action call will surface real errors */
  }
  return { used: false }
}

/** Build a profile from pasted LaTeX (browser-held, not saved). -> profile */
export async function demoExtractLatex(code) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/demo/extract/latex`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code }),
    })
  } catch {
    throw new DemoError('Could not reach the server.')
  }
  if (res.ok) return (await res.json()).profile
  throw new DemoError(await readError(res, 'Could not read that LaTeX.'), res.status)
}

/** Build a profile from an uploaded PDF (browser-held, not saved). -> profile */
export async function demoExtractPdf(file) {
  const form = new FormData()
  form.append('file', file)
  let res
  try {
    res = await fetch(`${API_BASE_URL}/demo/extract/pdf`, { method: 'POST', body: form })
  } catch {
    throw new DemoError('Could not reach the server.')
  }
  if (res.ok) return (await res.json()).profile
  throw new DemoError(await readError(res, 'Could not read that PDF.'), res.status)
}

/** Generate one tailored demo resume. -> { blob, warning }. Throws DemoError(403) if used. */
export async function demoGenerate(profile, jd, template = null) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/demo/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ profile, jd, template }),
    })
  } catch {
    throw new DemoError('Could not reach the server.')
  }
  if (res.ok) {
    const blob = await res.blob()
    return { blob, warning: res.headers.get('X-Resume-Warning') ?? '' }
  }
  throw new DemoError(await readError(res, 'Generation failed.'), res.status)
}

/** Resolve the current user from the stored token. Throws AuthError if invalid. */
export async function getMe() {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/auth/me`, { headers: authHeaders() })
  } catch {
    throw new AuthError(AUTH_UNREACHABLE)
  }
  if (res.ok) return res.json()
  throw new AuthError(await readError(res, 'Session expired.'), res.status)
}

// ── Profile (all authed) ──────────────────────────────────────────────────

/** Generic error for profile calls; `status` carries the HTTP code (404 = no profile). */
export class ProfileError extends Error {
  constructor(message, status = 0) {
    super(message)
    this.name = 'ProfileError'
    this.status = status
  }
}

const PROFILE_UNREACHABLE = 'Could not reach the server. Is the backend running?'

/** Fetch the current user's profile. Returns null if they have none yet (404). */
export async function getProfile() {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/profile`, { headers: authHeaders() })
  } catch {
    throw new ProfileError(PROFILE_UNREACHABLE)
  }
  if (res.ok) return res.json()
  if (res.status === 404) return null // no profile yet -> first-time flow
  throw new ProfileError(await readError(res, 'Could not load your profile.'), res.status)
}

/** Save edited profile JSON (raw edit / chat-approved changes). Returns the saved profile. */
export async function saveProfile(data) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/profile`, {
      method: 'PUT',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify(data),
    })
  } catch {
    throw new ProfileError(PROFILE_UNREACHABLE)
  }
  if (res.ok) return res.json()
  throw new ProfileError(await readError(res, 'Could not save your profile.'), res.status)
}

/** Seed the profile from pasted LaTeX (also stored as the user's template). */
export async function seedProfileLatex(code) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/profile/seed/latex`, {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ code }),
    })
  } catch {
    throw new ProfileError(PROFILE_UNREACHABLE)
  }
  if (res.ok) return res.json()
  throw new ProfileError(await readError(res, 'Could not build a profile from that LaTeX.'), res.status)
}

/** Seed the profile from an uploaded resume PDF (parsed + AI-extracted). */
export async function seedProfilePdf(file) {
  const form = new FormData()
  form.append('file', file)
  let res
  try {
    res = await fetch(`${API_BASE_URL}/profile/seed/pdf`, {
      method: 'POST',
      headers: authHeaders(), // no Content-Type: browser sets the multipart boundary
      body: form,
    })
  } catch {
    throw new ProfileError(PROFILE_UNREACHABLE)
  }
  if (res.ok) return res.json()
  throw new ProfileError(await readError(res, 'Could not read that PDF.'), res.status)
}

/**
 * Session chat editor. Sends current profile + message + recent turns; gets back
 * { reply, changes, remaining }. `changes` is a partial top-level patch (or null).
 */
export async function profileChat(profile, message, history) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/profile/chat`, {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ profile, message, history }),
    })
  } catch {
    throw new ProfileError(PROFILE_UNREACHABLE)
  }
  if (res.ok) return res.json()
  if (res.status === 429) {
    throw new ProfileError(await readError(res, 'Daily chat limit reached.'), 429)
  }
  throw new ProfileError(await readError(res, 'The assistant could not respond.'), res.status)
}

/** Error thrown when the backend reports a LaTeX compile failure (HTTP 422). */
export class CompileError extends Error {
  constructor(message, log = '') {
    super(message)
    this.name = 'CompileError'
    this.log = log
  }
}

/**
 * Send LaTeX source to the backend and get back a PDF.
 * @param {string} code - the full LaTeX source
 * @returns {Promise<Blob>} the compiled PDF as a Blob
 * @throws {CompileError} on a LaTeX failure (carries the log)
 * @throws {Error} on a network/unexpected failure
 */
export async function compileLatex(code) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/compile`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code }),
    })
  } catch {
    throw new Error('Could not reach the backend. Is the server running?')
  }

  if (res.ok) {
    return res.blob()
  }

  // Backend returns { detail: { message, log } } on a 422 compile error.
  if (res.status === 422) {
    let detail = {}
    try {
      const body = await res.json()
      detail = body.detail ?? {}
    } catch {
      /* fall through to generic message */
    }
    throw new CompileError(
      detail.message ?? 'LaTeX compilation failed.',
      detail.log ?? '',
    )
  }

  throw new Error(`Unexpected server error (HTTP ${res.status}).`)
}

/** Error thrown when the backend can't produce a valid resume (HTTP 422). */
export class GenerationError extends Error {
  constructor(message, log = '') {
    super(message)
    this.name = 'GenerationError'
    this.log = log
  }
}

const UNREACHABLE = 'Could not reach the backend. Is the server running?'

/**
 * Score the stored profile against a job description.
 * @returns {Promise<{score:number, fit:boolean, missing:string[], suggestions:string[]}>}
 */
export async function getMatch(jd) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/match`, {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ jd }),
    })
  } catch {
    throw new Error(UNREACHABLE)
  }

  if (res.ok) return res.json()

  if (res.status === 409) {
    throw new Error('Set up your profile first.')
  }
  if (res.status === 503) {
    throw new Error('AI service unavailable — is OPENAI_API_KEY set on the backend?')
  }
  throw new Error(`Unexpected server error (HTTP ${res.status}).`)
}

// Decode a base64 PDF (from the JSON generate/edit responses) into a Blob.
function pdfBlobFromB64(b64) {
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
  return new Blob([bytes], { type: 'application/pdf' })
}

/**
 * Generate a tailored resume for the logged-in user (profile + template are server-side).
 * `score` is the fit score from the prior match step, stored to history (no recompute).
 * Returns the PDF blob AND the LaTeX source (held in session memory for the chat editor).
 * @returns {Promise<{blob: Blob, tex: string, warning: string}>}
 * @throws {GenerationError} on a hard failure (carries the log)
 */
export async function generateResume(jd, score = null) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/generate`, {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ jd, score }),
    })
  } catch {
    throw new Error(UNREACHABLE)
  }

  if (res.ok) {
    const data = await res.json()
    return { blob: pdfBlobFromB64(data.pdf), tex: data.tex ?? '', warning: data.warning ?? '' }
  }

  if (res.status === 409) {
    throw new Error('Set up your profile first.')
  }
  if (res.status === 422) {
    let detail = {}
    try {
      detail = (await res.json()).detail ?? {}
    } catch {
      /* generic message below */
    }
    throw new GenerationError(detail.message ?? 'Generation failed.', detail.log ?? '')
  }
  if (res.status === 503) {
    throw new Error('AI service unavailable — is OPENAI_API_KEY set on the backend?')
  }
  throw new Error(`Unexpected server error (HTTP ${res.status}).`)
}

/**
 * One turn of the post-generation resume conversation. Not every message is an edit — the
 * assistant answers questions too, and only proposes changes when a change was asked for.
 *
 * The source and the recent turns are sent each call (session memory) — the server is
 * stateless and stores neither. The profile is NOT sent; the backend reads it from the
 * user's own store.
 *
 * `kind` says what came back:
 *   'answer'   -> conversation only; blob is null and nothing should change
 *   'proposal' -> `tex`/`blob` are a COMPILED candidate the user must approve before it lands
 *   'failed'   -> a change was wanted but couldn't be made; `tex` echoes the current source
 *
 * @param {string} tex - current LaTeX source
 * @param {string} message - the user's message
 * @param {string} jd - target job description (context only)
 * @param {{role:string, content:string}[]} history - recent chat turns
 * @returns {Promise<{kind:string, ok:boolean, reply:string, section:string, summary:string[],
 *                    tex:string, blob:Blob|null, warning:string}>}
 */
export async function editResume(tex, message, jd = '', history = []) {
  let res
  try {
    res = await fetch(`${API_BASE_URL}/resume/edit`, {
      method: 'POST',
      headers: authHeaders({ 'Content-Type': 'application/json' }),
      body: JSON.stringify({ tex, message, jd, history }),
    })
  } catch {
    throw new Error(UNREACHABLE)
  }

  if (res.ok) {
    const d = await res.json()
    return {
      kind: d.kind ?? 'answer',
      ok: d.ok,
      reply: d.reply,
      section: d.section ?? '',
      summary: d.summary ?? [],
      tex: d.tex,
      blob: d.pdf ? pdfBlobFromB64(d.pdf) : null,
      warning: d.warning ?? '',
    }
  }

  if (res.status === 409) throw new Error('Set up your profile first.')
  if (res.status === 503) {
    throw new Error('AI service unavailable — is OPENAI_API_KEY set on the backend?')
  }
  throw new Error(`Unexpected server error (HTTP ${res.status}).`)
}
