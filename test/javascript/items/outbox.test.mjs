// The local outbox: an answer leaves only on a JSON "recorded" or "invalid" reply.
// A redirect, a non-JSON 200, a 401/403/5xx or no network keeps it queued.
import assert from "node:assert/strict"
import { test } from "node:test"
import { Outbox } from "../../../app/javascript/items/outbox.js"

class MemoryStorage {
  constructor() { this.map = new Map() }
  get length() { return this.map.size }
  key(i) { return Array.from(this.map.keys())[i] ?? null }
  getItem(k) { return this.map.has(k) ? this.map.get(k) : null }
  setItem(k, v) { this.map.set(k, String(v)) }
  removeItem(k) { this.map.delete(k) }
}

function reply({ status = 200, type = "basic", json = null, contentType = "application/json", redirected = false } = {}) {
  return {
    status, type, redirected,
    headers: { get: (name) => (name.toLowerCase() === "content-type" ? contentType : null) },
    json: async () => { if (json === null) throw new SyntaxError("not json"); return json }
  }
}

function outbox(fetchImpl, storage = new MemoryStorage()) {
  return new Outbox({ url: "/diagnosis/answers", csrf: () => "token", storage, fetchImpl })
}

const entry = (id, raw = "6") => ({ client_attempt_id: id, served_event_id: 1, raw, source: "text" })

test("an answer is stored before it is sent and removed on recorded", async () => {
  const storage = new MemoryStorage()
  const calls = []
  const box = outbox(async (url, options) => { calls.push({ url, options }); return reply({ json: { status: "recorded" } }) }, storage)
  box.add(entry("a1"))
  assert.equal(storage.length, 1)
  assert.ok(storage.key(0).startsWith("banco.outbox."))
  const result = await box.flush()
  assert.equal(result.blocked, false)
  assert.equal(result.results.a1.status, "recorded")
  assert.equal(storage.length, 0)
  assert.equal(calls[0].options.redirect, "manual")
  assert.equal(calls[0].options.credentials, "same-origin")
  assert.equal(calls[0].options.headers["X-CSRF-Token"], "token")
  assert.deepEqual(JSON.parse(calls[0].options.body), { served_event_id: 1, client_attempt_id: "a1", raw: "6", source: "text" })
})

test("invalid also clears the entry: it is an answer the server will not take", async () => {
  const box = outbox(async () => reply({ json: { status: "invalid", message_it: "x" } }))
  box.add(entry("a1"))
  const result = await box.flush()
  assert.equal(result.results.a1.status, "invalid")
  assert.equal(box.size, 0)
})

const BLOCKS = {
  "an opaque redirect (session expired)": () => reply({ type: "opaqueredirect", status: 0 }),
  "a followed redirect": () => reply({ redirected: true }),
  "a 200 that is the login page": () => reply({ contentType: "text/html", json: null }),
  "a 401": () => reply({ status: 401, contentType: "text/plain" }),
  "a 403": () => reply({ status: 403 }),
  "a 500": () => reply({ status: 500 }),
  "a 503": () => reply({ status: 503 }),
  "a JSON body that is not a status": () => reply({ json: { hello: "world" } }),
  "a broken JSON body": () => reply({ json: null })
}

for (const [name, make] of Object.entries(BLOCKS)) {
  test(`${name} keeps the answer queued`, async () => {
    const storage = new MemoryStorage()
    const box = outbox(async () => make(), storage)
    box.add(entry("a1"))
    const result = await box.flush()
    assert.equal(result.blocked, true)
    assert.equal(box.size, 1)
    assert.equal(storage.length, 1)
  })
}

test("no network keeps the answer queued", async () => {
  const box = outbox(async () => { throw new TypeError("Failed to fetch") })
  box.add(entry("a1"))
  const result = await box.flush()
  assert.deepEqual([result.blocked, result.reason], [true, "network"])
  assert.equal(box.size, 1)
})

test("the queue goes out in order and stops at the first one that cannot be delivered", async () => {
  const order = []
  const box = outbox(async (_url, options) => {
    const id = JSON.parse(options.body).client_attempt_id
    order.push(id)
    return id === "a2" ? reply({ status: 503 }) : reply({ json: { status: "recorded" } })
  })
  box.add(entry("a1")); box.add(entry("a2")); box.add(entry("a3"))
  const result = await box.flush()
  assert.equal(result.blocked, true)
  assert.deepEqual(order, ["a1", "a2"])
  assert.deepEqual(box.pending().map((e) => e.client_attempt_id), ["a2", "a3"])
})

test("a new page finds what the last one left in storage and sends it", async () => {
  const storage = new MemoryStorage()
  const first = outbox(async () => reply({ status: 401 }), storage)
  first.add(entry("a1", "42"))
  await first.flush()
  const sent = []
  const second = outbox(async (_url, options) => { sent.push(JSON.parse(options.body)); return reply({ json: { status: "recorded" } }) }, storage)
  assert.equal(second.size, 1)
  const result = await second.flush()
  assert.equal(result.blocked, false)
  assert.equal(sent[0].raw, "42")
  assert.equal(storage.length, 0)
})

test("flushing twice at once sends once", async () => {
  let count = 0
  const box = outbox(async () => { count += 1; await new Promise((r) => setTimeout(r, 10)); return reply({ json: { status: "recorded" } }) })
  box.add(entry("a1"))
  await Promise.all([box.flush(), box.flush()])
  assert.equal(count, 1)
})

test("without any storage the memory copy still works", async () => {
  const box = new Outbox({ url: "/x", csrf: () => "t", storage: { length: 0, key: () => null, getItem: () => null, setItem: () => { throw new Error("full") }, removeItem: () => {} },
                           fetchImpl: async () => reply({ json: { status: "recorded" } }) })
  box.add(entry("a1"))
  assert.equal(box.size, 1)
  assert.equal((await box.flush()).blocked, false)
})

// ---- the practice outbox: its own prefix, its own fields and statuses ---------------------------

import { PRACTICE_PREFIX } from "../../../app/javascript/items/outbox.js"

function practiceBox(fetchImpl, storage = new MemoryStorage()) {
  return new Outbox({ url: "/practice/answers", csrf: () => "token", storage, fetchImpl, prefix: PRACTICE_PREFIX,
                      fields: ["serve_id", "client_attempt_id", "raw", "source"], statuses: ["graded", "invalid", "closed"],
                      httpStatuses: [200, 409] })
}

test("a practice entry lives under banco.poutbox. and posts the serve id", async () => {
  const storage = new MemoryStorage()
  const calls = []
  const box = practiceBox(async (url, options) => { calls.push(options); return reply({ json: { status: "graded" } }) }, storage)
  box.add({ client_attempt_id: "p1", serve_id: 7, raw: "3", source: "text", served_event_id: 99 })
  assert.ok(storage.key(0).startsWith("banco.poutbox."))
  await box.flush()
  assert.deepEqual(JSON.parse(calls[0].body), { serve_id: 7, client_attempt_id: "p1", raw: "3", source: "text" })
  assert.equal(storage.length, 0)
})

test("a diagnosis outbox never restores or resends a practice entry, and the reverse", async () => {
  const storage = new MemoryStorage()
  storage.setItem("banco.poutbox.p1", JSON.stringify({ client_attempt_id: "p1", serve_id: 7, raw: "3", source: "text", queued_at: 1 }))
  storage.setItem("banco.outbox.d1", JSON.stringify({ client_attempt_id: "d1", served_event_id: 3, raw: "4", source: "text", queued_at: 2 }))
  const diagnosis = outbox(async () => reply({ json: { status: "recorded" } }), storage)
  assert.deepEqual(diagnosis.pending().map((e) => e.client_attempt_id), ["d1"])
  const practice = practiceBox(async () => reply({ json: { status: "graded" } }), storage)
  assert.deepEqual(practice.pending().map((e) => e.client_attempt_id), ["p1"])
})

test("a 409 closed serve is an answer, a 503 retry keeps the entry queued", async () => {
  const closed = practiceBox(async () => reply({ status: 409, json: { status: "closed", message_it: "x" } }))
  closed.add({ client_attempt_id: "p1", serve_id: 7, raw: "3", source: "text" })
  const done = await closed.flush()
  assert.equal(done.blocked, false)
  assert.equal(done.results.p1.status, "closed")
  const retry = practiceBox(async () => reply({ status: 503, json: { status: "retry" } }))
  retry.add({ client_attempt_id: "p2", serve_id: 7, raw: "3", source: "text" })
  const blocked = await retry.flush()
  assert.equal(blocked.blocked, true)
  assert.equal(retry.size, 1)
})
