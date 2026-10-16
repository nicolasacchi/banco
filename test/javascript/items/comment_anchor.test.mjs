// The comment mode's pure parts (D-304): the anchor path, the ids a node carries, the payload and its limits.
import assert from "node:assert/strict"
import { test } from "node:test"
import { anchorPath, buildComment, clip, describeAnchor, listTargets, refsOf, REASONS, TEXT_MAX, validSegment } from "../../../app/javascript/items/comment_anchor.js"

// a node with just what the module reads
const node = (attrs = {}, parent = null, id = "", text = "") => ({
  getAttribute: (name) => (name in attrs ? attrs[name] : null), parentElement: parent, id, textContent: text
})

test("the anchor is the segments of the node and its ancestors, top-down", () => {
  const card = node({ "data-comment-anchor": "card:3" })
  const block = node({ "data-comment-anchor": "block:2" }, card)
  const option = node({ "data-comment-anchor": "option:1" }, block)
  const bare = node({}, option)
  assert.equal(anchorPath(bare), "card:3/block:2/option:1")
  assert.equal(anchorPath(block), "card:3/block:2")
})

test("the walk stops at the root", () => {
  const root = node({ "data-comment-anchor": "page" })
  const inner = node({ "data-comment-anchor": "section:x" }, root)
  assert.equal(anchorPath(inner, root), "section:x")
})

test("without an anchor attribute the nearest id stands in, and with nothing the whole page", () => {
  const section = node({}, node({}, null), "entry-test")
  assert.equal(anchorPath(node({}, section)), "id:entry-test")
  assert.equal(anchorPath(node({}, node({}))), null)
  assert.equal(anchorPath(null), null)
})

test("a segment that the server would refuse is never produced", () => {
  assert.equal(validSegment("card:3"), true)
  assert.equal(validSegment("cover"), true)
  assert.equal(validSegment("Card:3"), false)
  assert.equal(validSegment("card:3/block"), false)
  assert.equal(validSegment("card:<script>"), false)
  const evil = node({ "data-comment-anchor": "../x" })
  assert.equal(anchorPath(evil), null)
})

test("no more than eight segments", () => {
  let n = null
  for (let i = 0; i < 12; i++) n = node({ "data-comment-anchor": `block:${i}` }, n)
  assert.equal(anchorPath(n).split("/").length, 8)
})

test("the ids come from the node or an ancestor, then from the document, and only as positive integers", () => {
  const box = node({ "data-comment-served-event-id": "41" })
  const inner = node({}, box)
  assert.deepEqual(refsOf(inner), { served_event_id: 41 })
  const doc = { querySelector: (sel) => (sel.includes("serve-id") ? { getAttribute: () => "7" } : null) }
  assert.deepEqual(refsOf(null, doc), { serve_id: 7 })
  assert.deepEqual(refsOf(node({ "data-comment-serve-id": "-3" })), {})
  assert.deepEqual(refsOf(node({ "data-comment-serve-id": "abc" })), {})
  assert.deepEqual(refsOf(node({ "data-comment-lesson-revision-id": "12" })), { lesson_revision_id: 12 })
})

test("the payload carries the five reasons, an optional text of at most 500 characters and 300 of selected text", () => {
  assert.deepEqual(REASONS, ["not_understood", "error", "not_working", "like", "other"])
  const base = { id: "abcdefgh1", reason: "like", text: "  bello   così \n ", selected: "x".repeat(400), anchor: "card:1", refs: { serve_id: 2 }, pagePath: "/today",
                 viewport: { width: 390, height: 800 }, theme: "cream", size: "normal" }
  const payload = buildComment(base)
  assert.equal(payload.text_it, "bello così")
  assert.equal(payload.selected_text.length, 300)
  assert.equal(payload.client_comment_id, "abcdefgh1")
  assert.deepEqual(payload.refs, { serve_id: 2 })
  assert.equal(payload.viewport_width, 390)
  assert.equal(buildComment({ ...base, text: "" }).text_it, null)
  assert.equal(buildComment({ ...base, text: "y".repeat(TEXT_MAX) }).text_it.length, TEXT_MAX)
  assert.deepEqual(buildComment({ ...base, text: "y".repeat(TEXT_MAX + 1) }), { error: "text" })
  assert.deepEqual(buildComment({ ...base, reason: "angry" }), { error: "reason" })
  assert.deepEqual(buildComment({ ...base, reason: undefined }), { error: "reason" })
})

test("clip squeezes spaces and cuts", () => {
  assert.equal(clip(" a \n b ", 10), "a b")
  assert.equal(clip("abcdef", 3), "abc")
  assert.equal(clip(null, 3), "")
})

test("the list of targets starts with the whole page and follows the document", () => {
  const a = node({ "data-comment-anchor": "card:1" }, null, "", "Prima scheda")
  const b = node({ "data-comment-anchor": "card:2", "data-comment-label": "Seconda" }, null, "", "xxx")
  const doc = { querySelectorAll: () => [a, b] }
  const list = listTargets(doc, "Tutta la pagina")
  assert.deepEqual(list.map((t) => t.label), ["Tutta la pagina", "Prima scheda", "Seconda"])
  assert.deepEqual(list.map((t) => t.anchor), [null, "card:1", "card:2"])
})

test("an anchor path is said in words for the box (D-305)", () => {
  const names = { card: "Scheda %{n}", block: "Blocco %{n}", option: "Risposta %{n}", question: "La domanda", menu: "Il menu" }
  assert.equal(describeAnchor("card:3/block:2/option:1", names), "Scheda 3 · Blocco 2 · Risposta 1")
  assert.equal(describeAnchor("question", names), "La domanda")
  assert.equal(describeAnchor("card:1/block:2/row:9/option:3", names), "Scheda 1 · Blocco 2 · Risposta 3", "an unknown segment is left out")
  assert.equal(describeAnchor("card:1/block:2/option:3/menu", { ...names, row: "Riga" }), "Blocco 2 · Risposta 3 · Il menu", "at most the last three words")
  assert.equal(describeAnchor("card", names), null, "a template with a number needs the number")
  assert.equal(describeAnchor("id:entry-test", names), null)
  assert.equal(describeAnchor(null, names), null)
  assert.equal(describeAnchor("menu", null), null)
})
