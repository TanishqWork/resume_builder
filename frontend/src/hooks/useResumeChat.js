// State for the post-generation resume conversation.
//
// Two things happen in this one chat: the assistant ANSWERS questions about the resume and
// the job, and — only when a change was asked for — it PROPOSES an edit. A proposal is
// already compiled server-side but is NOT live: it waits in `pending` until the user applies
// it, at which point the new PDF + LaTeX go to useGenerate via applyEditedResult and the
// preview updates in place. This mirrors the profile chat's review-then-approve flow.
//
// The message log doubles as the CONTEXT sent with each turn, so follow-ups ("shorten it
// more") resolve. Session-only — nothing here is persisted.

import { useCallback, useState } from 'react'

import { editResume } from '../services/api'

// Recent turns sent as context. The backend re-caps; this just bounds the request body.
const HISTORY_TURNS = 8

/**
 * @param {{ applyEditedResult: (r:{tex:string, blob:Blob, warning:string}) => void }} opts
 * @returns {{ messages, status, pending, send, apply, dismiss, reset }}
 *   messages: [{ role:'user'|'assistant'|'system', text, section?, ok? }]
 *   status: 'idle' | 'sending'
 *   pending: { tex, blob, warning, summary[], section } | null  — awaiting approval
 */
export function useResumeChat({ applyEditedResult }) {
  const [messages, setMessages] = useState([])
  const [status, setStatus] = useState('idle')
  const [pending, setPending] = useState(null)

  const send = useCallback(
    async (message, tex, jd) => {
      const text = (message || '').trim()
      if (!text || status === 'sending' || !tex) return

      // Turns BEFORE this one (the new message travels as `message`), in the
      // {role, content} shape the API expects.
      const history = messages
        .slice(-HISTORY_TURNS)
        .map((m) => ({ role: m.role === 'system' ? 'assistant' : m.role, content: m.text }))

      // Any un-applied proposal is stale the moment a new message is sent: it was computed
      // against the current tex and the user has moved on.
      setPending(null)
      setMessages((m) => [...m, { role: 'user', text }])
      setStatus('sending')
      try {
        const r = await editResume(tex, text, jd, history)
        setMessages((m) => [
          ...m,
          { role: 'assistant', text: r.reply, section: r.section, ok: r.ok },
        ])
        if (r.kind === 'proposal' && r.blob) {
          setPending({
            tex: r.tex,
            blob: r.blob,
            warning: r.warning,
            summary: r.summary,
            section: r.section,
          })
        }
      } catch (err) {
        setMessages((m) => [...m, { role: 'assistant', text: err.message, ok: false }])
      } finally {
        setStatus('idle')
      }
    },
    [messages, status],
  )

  // Approve the pending proposal — this is the only place the live resume changes.
  const apply = useCallback(() => {
    if (!pending) return
    applyEditedResult({ tex: pending.tex, blob: pending.blob, warning: pending.warning })
    const what = pending.section ? ` to ${pending.section}` : ''
    setPending(null)
    setMessages((m) => [...m, { role: 'system', text: `✓ Applied the change${what}.` }])
  }, [applyEditedResult, pending])

  const dismiss = useCallback(() => {
    if (!pending) return
    setPending(null)
    setMessages((m) => [...m, { role: 'system', text: 'Change discarded.' }])
  }, [pending])

  const reset = useCallback(() => {
    setMessages([])
    setPending(null)
  }, [])

  return { messages, status, pending, send, apply, dismiss, reset }
}
