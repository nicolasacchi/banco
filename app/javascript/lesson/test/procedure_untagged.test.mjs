// A procedure step may have no tag (D-402, round 7): no chip for it, and the mnemonic line names the tagged steps only; nothing of a lesson with every step tagged changes.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"
import { install } from "./fake_dom.mjs"

install()
const procedure = await import("lesson/blocks/procedure")

const ctx = { subject: "english", t: { example_short: "Esempio" }, noSpeech: true, mount() {}, track() {}, rich(text) { return text } }
const block = (...steps) => ({ n: 2, type: "procedure", title_it: "Come fare", steps })

test("a step without a tag has no chip; the others keep theirs", () => {
  const box = procedure.render(block({ tag: "reread", text_it: "Rileggi il testo." }, { text_it: "Rileggi ancora." }), ctx)
  assert.equal(box.querySelectorAll(".step").length, 2)
  assert.equal(box.querySelectorAll(".step-tag").length, 1, "one chip: the untagged step has none")
  assert.equal(box.querySelectorAll(".step")[1].querySelectorAll(".step-tag").length, 0)
  assert.equal(box.querySelectorAll(".mn-pill").length, 1, "the mnemonic names the tagged step only")
})

test("every step tagged is drawn as it always was; no step tagged has no mnemonic", () => {
  const all = procedure.render(block({ tag: "reread", text_it: "Uno." }, { tag: "reread", text_it: "Due." }), ctx)
  assert.equal(all.querySelectorAll(".step-tag").length, 2)
  assert.equal(all.querySelectorAll(".mn-pill").length, 2)
  assert.equal(all.querySelectorAll(".mn-arrow").length, 1)
  const none = procedure.render(block({ text_it: "Uno." }, { text_it: "Due." }), ctx)
  assert.equal(none.querySelectorAll(".mnemonic").length, 0)
  assert.equal(none.querySelectorAll(".step-tag").length, 0)
  assert.equal(none.querySelectorAll(".step").length, 2)
})
