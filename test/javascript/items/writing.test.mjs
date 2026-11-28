// «Scrivi tu» (D-407): the pure parts of the writing box (the word count the server shares, the refusals, the draft key) and its own outbox: the text is stored
// under banco.woutbox.<item revision>. before it is posted, goes with the same client_writing_id on every resend, and leaves only on a recorded or invalid reply.
import assert from "node:assert/strict"
import { test } from "node:test"
import { DRAFT_PREFIX, TEXT_MAX, check, countWords, draftKey } from "../../../app/javascript/items/writing.js"
import { Outbox, WRITING_PREFIX } from "../../../app/javascript/items/outbox.js"

class MemoryStorage {
  constructor() { this.map = new Map() }
  get length() { return this.map.size }
  key(i) { return Array.from(this.map.keys())[i] ?? null }
  getItem(k) { return this.map.has(k) ? this.map.get(k) : null }
  setItem(k, v) { this.map.set(k, String(v)) }
  removeItem(k) { this.map.delete(k) }
}

function reply({ status = 200, json = null } = {}) {
  return {
    status, type: "basic", redirected: false,
    headers: { get: (name) => (name.toLowerCase() === "content-type" ? "application/json" : null) },
    json: async () => json
  }
}

const outbox = (fetchImpl, storage, prefix = `${WRITING_PREFIX}7.`) =>
  new Outbox({ url: "/topics/t/writings", csrf: () => "token", storage, fetchImpl, prefix, idField: "client_writing_id", fields: ["client_writing_id", "item_revision_id", "text"], httpStatuses: [200, 422] })

test("countWords counts runs of non-space characters, as the server does", () => {
  assert.equal(countWords(""), 0)
  assert.equal(countWords("   \n\t "), 0)
  assert.equal(countWords("ciao"), 1)
  assert.equal(countWords("  Ho  spostato\nil sette,\ta destra. "), 6)
  assert.equal(countWords("l'amico d'infanzia"), 2)
  assert.equal(countWords(null), 0)
})

test("check refuses what the server refuses: nothing but space, and more than 4000 characters", () => {
  assert.equal(check(""), "empty")
  assert.equal(check(" \r\n "), "empty")
  assert.equal(check("a"), null)
  assert.equal(check("a".repeat(TEXT_MAX)), null)
  assert.equal(check("a".repeat(TEXT_MAX + 1)), "too_long")
  assert.equal(check(`  ${"a".repeat(TEXT_MAX)}  `), null, "the space around the text is not part of it")
})

test("a draft has its own key for each task, and one for the teacher's preview", () => {
  assert.equal(draftKey("it-write-1"), `${DRAFT_PREFIX}it-write-1`)
  assert.notEqual(draftKey("it-write-1", true), draftKey("it-write-1", false))
  assert.ok(draftKey("x", true).startsWith(DRAFT_PREFIX))
})

test("the outbox keeps the text until the server records it, resends it with the same client_writing_id, and posts the three fields", async () => {
  const storage = new MemoryStorage()
  const calls = []
  let up = false
  const box = outbox(async (url, options) => {
    calls.push({ url, body: JSON.parse(options.body) })
    if (!up) throw new TypeError("offline")
    return reply({ json: { status: "recorded", submission: { id: 3, text: "Il mio testo." } } })
  }, storage)
  box.add({ client_writing_id: "w-1234abcd", item_revision_id: 7, text: "Il mio testo." })
  assert.ok(storage.key(0).startsWith("banco.woutbox.7."))
  const first = await box.flush()
  assert.equal(first.blocked, true)
  assert.equal(storage.length, 1, "a text that did not get through stays")

  up = true
  const again = new Outbox({ url: "/topics/t/writings", csrf: () => "token", storage, fetchImpl: async (url, options) => { calls.push({ url, body: JSON.parse(options.body) }); return reply({ json: { status: "recorded", submission: { id: 3 } } }) },
                             prefix: "banco.woutbox.7.", idField: "client_writing_id", fields: ["client_writing_id", "item_revision_id", "text"], httpStatuses: [200, 422] })
  assert.equal(again.size, 1, "a reload finds it")
  const result = await again.flush()
  assert.equal(result.blocked, false)
  assert.equal(result.results["w-1234abcd"].status, "recorded")
  assert.equal(storage.length, 0)
  assert.deepEqual(calls.map((c) => c.body), [
    { client_writing_id: "w-1234abcd", item_revision_id: 7, text: "Il mio testo." },
    { client_writing_id: "w-1234abcd", item_revision_id: 7, text: "Il mio testo." }
  ])
})

test("a refusal with a 422 and an invalid body ends the entry; another task's entries are never resent from here", async () => {
  const storage = new MemoryStorage()
  const mine = outbox(async () => reply({ status: 422, json: { status: "invalid", error: "pending" } }), storage)
  const other = outbox(async () => reply({ json: { status: "recorded" } }), storage, `${WRITING_PREFIX}8.`)
  other.add({ client_writing_id: "w-other-0001", item_revision_id: 8, text: "Altro." })
  mine.add({ client_writing_id: "w-mine-00001", item_revision_id: 7, text: "Mio." })
  const result = await mine.flush()
  assert.equal(result.blocked, false)
  assert.equal(result.results["w-mine-00001"].error, "pending")
  assert.equal(storage.length, 1)
  assert.ok(storage.key(0).startsWith("banco.woutbox.8."))
  assert.equal(new Outbox({ url: "/x", csrf: () => "t", storage, prefix: `${WRITING_PREFIX}7.`, idField: "client_writing_id" }).size, 0, "7. is not 78.")
})
