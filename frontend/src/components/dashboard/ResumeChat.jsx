// Right-side chat panel for the post-generation resume conversation.
// Dumb component: it renders the message log, any pending proposal, and the input;
// useResumeChat owns the async work and the apply/dismiss decision.

import { useEffect, useRef, useState } from 'react'
import { Check, Loader2, Send, Sparkles, User, X } from 'lucide-react'

// A mix of both things the assistant does, so it reads as a conversation rather than a
// command box: two edits and one question.
const SUGGESTIONS = [
  'Make the summary punchier',
  'What am I missing for this job?',
  'Shorten the first experience bullet',
]

export default function ResumeChat({ chat, onSend, disabled = false }) {
  const [input, setInput] = useState('')
  const endRef = useRef(null)
  const sending = chat.status === 'sending'

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [chat.messages, chat.pending, sending])

  function submit(e) {
    e.preventDefault()
    const text = input.trim()
    if (!text || sending || disabled) return
    onSend(text)
    setInput('')
  }

  return (
    <div className="glass flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl">
      <div className="flex items-center gap-2 border-b border-[var(--color-border)] px-4 py-3 text-sm font-semibold text-white">
        <Sparkles className="h-4 w-4 text-blue-300" /> Edit with chat
      </div>

      <div className="min-h-0 flex-1 space-y-3 overflow-auto px-4 py-4">
        {chat.messages.length === 0 && (
          <div className="space-y-3">
            <p className="text-xs text-[var(--color-muted)]">
              Ask me anything about this resume or the job — or tell me what to change and
              I’ll show you the edit before it’s applied.
            </p>
            <div className="flex flex-wrap gap-2">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => onSend(s)}
                  disabled={disabled || sending}
                  className="rounded-full border border-[var(--color-border)] px-3 py-1 text-xs text-white/70 transition hover:bg-white/5 disabled:opacity-40"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {chat.messages.map((m, i) => (
          <Bubble key={i} m={m} />
        ))}

        {/* A compiled candidate waiting for approval. Nothing has changed in the preview
            yet — applying is what makes it live. */}
        {chat.pending && (
          <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/5 p-3">
            <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-emerald-300">
              Proposed change{chat.pending.section ? ` — ${chat.pending.section}` : ''}
            </p>
            {chat.pending.summary?.length > 0 && (
              <ul className="mb-3 space-y-1">
                {chat.pending.summary.map((s, i) => (
                  <li key={i} className="flex gap-1.5 text-xs text-white/80">
                    <span className="text-emerald-300">•</span>
                    <span>{s}</span>
                  </li>
                ))}
              </ul>
            )}
            {chat.pending.warning && (
              <p className="mb-3 text-xs text-amber-200">{chat.pending.warning}</p>
            )}
            <div className="flex gap-2">
              <button
                onClick={chat.apply}
                className="inline-flex items-center gap-1.5 rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-semibold text-black transition hover:brightness-110"
              >
                <Check className="h-3.5 w-3.5" /> Apply
              </button>
              <button
                onClick={chat.dismiss}
                className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--color-border)] px-3 py-1.5 text-xs text-white/90 transition hover:bg-white/5"
              >
                <X className="h-3.5 w-3.5" /> Discard
              </button>
            </div>
          </div>
        )}

        {sending && (
          <div className="flex items-center gap-2 text-xs text-[var(--color-muted)]">
            <Loader2 className="h-3.5 w-3.5 animate-spin" /> Editing…
          </div>
        )}
        <div ref={endRef} />
      </div>

      <form
        onSubmit={submit}
        className="flex items-center gap-2 border-t border-[var(--color-border)] p-3"
      >
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Ask for an edit…"
          disabled={disabled || sending}
          className="flex-1 rounded-xl border border-[var(--color-border)] bg-black/40 px-3 py-2 text-sm text-white/90 outline-none transition placeholder:text-[var(--color-muted)] focus:border-blue-500/60 disabled:opacity-50"
        />
        <button
          type="submit"
          disabled={disabled || sending || !input.trim()}
          className="rounded-xl bg-gradient-to-r from-blue-500 to-emerald-500 p-2.5 text-white transition hover:brightness-110 disabled:opacity-40"
          aria-label="Send edit"
        >
          <Send className="h-4 w-4" />
        </button>
      </form>
    </div>
  )
}

function Bubble({ m }) {
  // 'system' is the app's own confirmation after applying or discarding — centred, quiet,
  // and clearly not something the assistant said.
  if (m.role === 'system') {
    return <p className="py-0.5 text-center text-[11px] text-[var(--color-muted)]">{m.text}</p>
  }

  const isUser = m.role === 'user'
  return (
    <div className={`flex gap-2 ${isUser ? 'justify-end' : ''}`}>
      {!isUser && <Sparkles className="mt-1.5 h-4 w-4 shrink-0 text-blue-300" />}
      <div
        // whitespace-pre-line: answers are prose and can span paragraphs, unlike the old
        // one-line "Updated the X section." acknowledgements.
        className={`max-w-[85%] whitespace-pre-line rounded-2xl px-3 py-2 text-sm ${
          isUser ? 'bg-blue-500/20 text-white' : 'bg-white/5 text-white/85'
        }`}
      >
        {m.text}
      </div>
      {isUser && <User className="mt-1.5 h-4 w-4 shrink-0 text-white/50" />}
    </div>
  )
}
