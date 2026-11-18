// What the render check's host collects as the segments a lesson says aloud (D-359): the walker's output with voice 1, the dialogue's lines with
// their speakers' voices, the text of a listening check, the speaker beside a foreign word. The host (Chrome) is run by
// test/validation/lesson_render_segments_test.rb; here a tiny DOM stands in.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { fixedIn, heardIn } = await import("lesson/speech_segments")

function text(value) { return { nodeType: 3, nodeValue: value } }
function el(tag, attrs = {}, ...kids) {
  const node = { nodeType: 1, tagName: tag.toUpperCase(), attrs, childNodes: kids.map((k) => (typeof k === "string" ? text(k) : k)), getAttribute(n) { return n in attrs ? String(attrs[n]) : null } }
  for (const kid of node.childNodes) kid.parentNode = node
  node.textContent = node.childNodes.map((k) => k.nodeValue ?? k.textContent).join("")
  return node
}

test("what the card says is the walker's text, each with voice 1", () => {
  const card = el("article", {}, el("h2", {}, "Il futuro"), el("p", {}, "Dì ", el("span", { lang: "en", class: "lang" }, "I will call you."), " a Luca."), el("p", { hidden: "" }, "Nascosto."))
  assert.deepEqual(heardIn(card), [
    { lang: "it", text: "Il futuro", voice: 1 }, { lang: "it", text: "Dì", voice: 1 }, { lang: "en", text: "I will call you.", voice: 1 }, { lang: "it", text: "a Luca.", voice: 1 }
  ])
})

test("a dialogue's lines carry their speakers' voices (the place of the speaker when it names none), the listen text voice 1, found anywhere in the card's data", () => {
  const data = {
    n: 3,
    blocks: [
      { type: "dialogue", speakers: [{ id: "t", name: "Tom" }, { id: "a", name: "Amy" }, { id: "z", name: "Zoe", voice: 3 }],
        lines: [{ speaker: "t", text_en: "Hello." }, { speaker: "a", text_en: "Hi there." }, { speaker: "z", text_en: "Hey." }] },
      { type: "try", exercises: [{ n: 1, check: { component: "choice", listen: { text_es: "¿Cómo estás?" } } }] },
      { type: "check", listen: { text_en: "She is reading." } },
      { type: "check", listen: {} }
    ]
  }
  assert.deepEqual(fixedIn(data, null), [
    { lang: "en", text: "Hello.", voice: 1 }, { lang: "en", text: "Hi there.", voice: 2 }, { lang: "en", text: "Hey.", voice: 3 },
    { lang: "es", text: "¿Cómo estás?", voice: 1 }, { lang: "en", text: "She is reading.", voice: 1 }
  ])
})

test("a speaker button says the word before it, in the language of that word", () => {
  const word = el("span", { lang: "es", class: "lang lang-es" }, "hablar")
  const button = el("button", { class: "speak speak-inline" })
  button.previousElementSibling = word
  const other = el("button", { class: "speak speak-inline" })
  other.previousElementSibling = el("span", {}, "senza lingua")
  const card = { querySelectorAll: (selector) => (selector === "button.speak-inline" ? [ button, other ] : []) }
  assert.deepEqual(fixedIn({}, card), [ { lang: "es", text: "hablar", voice: 1 } ])
})
