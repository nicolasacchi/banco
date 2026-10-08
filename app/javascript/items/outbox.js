// The local outbox (E-10): an answer is written here before it is posted and leaves
// only when the server says it has recorded it (or has refused it as invalid). It
// lives in memory and in localStorage under banco.outbox.<client_attempt_id>, on the
// app origin, so a reload, a closed tab or a login in between never loses it.
//
// A reply that is not JSON, a redirect (Authelia answers a lapsed session with one;
// with redirect: "manual" it shows up as an opaque redirect), a 401, 403, 5xx or no
// network at all leaves the entry queued and reports "blocked". The server's
// unique index on client_attempt_id makes every resend safe.

// The prefix tells whose entries these are: the diagnosis keeps banco.outbox., the practice pages
// banco.poutbox. (option prefix), so an entry of one can never be resent to the endpoint of the other.
// A page may also name the fields it posts (fields), the JSON statuses that end an entry (statuses) and
// the HTTP statuses whose JSON body is an answer, not a failure (httpStatuses, e.g. 409 for a closed serve).
export const DIAGNOSIS_PREFIX = "banco.outbox."
export const PRACTICE_PREFIX = "banco.poutbox."
const DEFAULT_FIELDS = ["served_event_id", "client_attempt_id", "raw", "source"]

export class Outbox {
  constructor({ url, csrf, storage = null, fetchImpl = (...args) => window.fetch(...args), prefix = DIAGNOSIS_PREFIX,
                fields = DEFAULT_FIELDS, statuses = ["recorded", "invalid"], httpStatuses = [200] }) {
    this.url = url
    this.prefix = prefix
    this.fields = fields
    this.statuses = statuses
    this.httpStatuses = httpStatuses
    this.csrf = csrf
    this.fetchImpl = fetchImpl
    this.memory = new Map()
    this.storage = storage || safeStorage(prefix)
    this.flushing = null
    this.restore()
  }

  restore() {
    if (!this.storage) return
    for (let i = 0; i < this.storage.length; i++) {
      const key = this.storage.key(i)
      if (!key || !key.startsWith(this.prefix)) continue
      try {
        const entry = JSON.parse(this.storage.getItem(key))
        if (entry && entry.client_attempt_id) this.memory.set(entry.client_attempt_id, entry)
      } catch (_error) {
        // an unreadable entry is left alone, never guessed at
      }
    }
  }

  add(entry) {
    const stored = { ...entry, queued_at: Date.now() }
    this.memory.set(stored.client_attempt_id, stored)
    try {
      this.storage?.setItem(this.prefix + stored.client_attempt_id, JSON.stringify(stored))
    } catch (_error) {
      // storage full or refused: the memory copy still serves this page
    }
    return stored
  }

  remove(id) {
    this.memory.delete(id)
    try {
      this.storage?.removeItem(this.prefix + id)
    } catch (_error) {
      // nothing to do
    }
  }

  pending() {
    return Array.from(this.memory.values()).sort((a, b) => a.queued_at - b.queued_at)
  }

  get size() {
    return this.memory.size
  }

  // Sends the queue in order. Resolves to {blocked: false, results: {id: reply}} or,
  // at the first entry that cannot be delivered, {blocked: true, reason}.
  flush() {
    this.flushing ||= this.run().finally(() => { this.flushing = null })
    return this.flushing
  }

  async run() {
    const results = {}
    for (const entry of this.pending()) {
      const reply = await this.post(entry)
      if (reply.blocked) return { blocked: true, reason: reply.reason, results }
      results[entry.client_attempt_id] = reply.body
      this.remove(entry.client_attempt_id)
    }
    return { blocked: false, results }
  }

  async post(entry) {
    let response
    try {
      response = await this.fetchImpl(this.url, {
        method: "POST",
        redirect: "manual",
        credentials: "same-origin",
        headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": this.csrf() },
        body: JSON.stringify(Object.fromEntries(this.fields.map((field) => [field, entry[field]])))
      })
    } catch (_error) {
      return { blocked: true, reason: "network" }
    }
    if (response.type === "opaqueredirect" || response.redirected) return { blocked: true, reason: "redirect" }
    if (!this.httpStatuses.includes(response.status)) return { blocked: true, reason: `status ${response.status}` }
    if (!(response.headers.get("content-type") || "").includes("json")) return { blocked: true, reason: "not json" }
    let body
    try {
      body = await response.json()
    } catch (_error) {
      return { blocked: true, reason: "not json" }
    }
    if (!this.statuses.includes(body?.status)) return { blocked: true, reason: "unexpected reply" }
    return { blocked: false, body }
  }
}

function safeStorage(prefix = DIAGNOSIS_PREFIX) {
  try {
    const storage = window.localStorage
    storage.getItem(prefix) // throws when storage is denied
    return storage
  } catch (_error) {
    return null
  }
}

export function newId() {
  if (window.crypto?.randomUUID) return window.crypto.randomUUID()
  const bytes = new Uint8Array(16)
  window.crypto.getRandomValues(bytes)
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("")
}
