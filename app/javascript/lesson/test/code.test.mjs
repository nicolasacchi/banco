// The code block (D-329): the box keeps every space and newline of the program, never wraps, "Copia" puts `text` on the clipboard exactly, and
// "Copiato" shows. The page itself is run in Chrome (test/validation/code_gallery_test.rb, test/system/lesson_code_block_test.rb); here a small
// stand-in for the document is enough to see what the renderer builds and what its button does.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { mock, test } from "node:test"

const { render, lineList, shownText, copyText, COPIED_MS } = await import("lesson/blocks/code")

const T = {
  program: "Programma", region: "Programma, %{n} righe", copy: "Copia", copy_aria: "Copia il programma", copied: "Copiato", copy_failed: "Non riesco a copiare",
  type: "Scrivi:", type_hint: "Dopo ogni riga premi Invio.", screen: "Sullo schermo vedi:", screen_region: "Schermo, %{n} righe", speech: "Un programma di %{n} righe."
}
const ctx = { t: { code: T } }
const PROGRAM = "Imports System\n\nModule Program\n    Sub Main()\n        Console.WriteLine(\"Ciao\")\n    End Sub\nEnd Module\n"

class Fake {
  constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.own = ""; this.listeners = {} }
  set className(v) { this.attrs.class = v }
  get className() { return this.attrs.class ?? "" }
  set textContent(v) { this.children = []; this.own = String(v) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
  setAttribute(name, value) { this.attrs[name] = String(value) }
  getAttribute(name) { return this.attrs[name] ?? null }
  appendChild(child) { this.children.push(child); return child }
  append(...nodes) { for (const node of nodes) this.appendChild(node) }
  addEventListener(name, fn) { this.listeners[name] = fn }
  get classList() {
    const set = () => new Set(this.className.split(/\s+/).filter(Boolean))
    return {
      add: (c) => { const s = set(); s.add(c); this.className = [...s].join(" ") },
      remove: (c) => { const s = set(); s.delete(c); this.className = [...s].join(" ") },
      contains: (c) => set().has(c)
    }
  }
  all(pred, out = []) {
    for (const child of this.children) if (child instanceof Fake) { if (pred(child)) out.push(child); child.all(pred, out) }
    return out
  }
  byClass(cls) { return this.all((n) => n.classList.contains(cls)) }
}

function withDom(fn) {
  const selected = []
  globalThis.document = {
    createElement: (tag) => new Fake(tag),
    createTextNode: (text) => ({ nodeType: 3, textContent: String(text) }),
    createRange: () => ({ selectNodeContents: (node) => selected.push(node) })
  }
  globalThis.window = { getSelection: () => ({ removeAllRanges() {}, addRange() {} }) }
  return Promise.resolve(fn(selected)).finally(() => {
    delete globalThis.document
    delete globalThis.window
  })
}

const setClipboard = (writeText) => Object.defineProperty(globalThis, "navigator", { value: { clipboard: { writeText } }, configurable: true, writable: true })

test("the lines of a program: indentation and empty lines kept, only the newline it ends with is not a line", () => {
  assert.deepEqual(lineList("a\n    b\n\nc\n"), ["a", "    b", "", "c"])
  assert.deepEqual(lineList("a\n\n"), ["a", ""])
  assert.deepEqual(lineList("solo"), ["solo"])
  assert.equal(shownText(PROGRAM), PROGRAM.slice(0, -1))
  assert.equal(shownText("a\n    b\n\n  c"), "a\n    b\n\n  c")
})

test("the box holds the program as text, every space kept, in a named box that the keyboard reaches", async () => {
  await withDom(() => {
    const root = render({ type: "code", lang: "vb", text: PROGRAM }, ctx)
    const [box] = root.byClass("code-box")
    assert.equal(box.tag, "pre")
    assert.equal(box.children[0].tag, "code")
    assert.equal(box.textContent, shownText(PROGRAM))
    assert.match(box.textContent, /\n {4}Sub Main\(\)\n {8}Console\.WriteLine/)
    assert.equal(box.getAttribute("role"), "region")
    assert.equal(box.getAttribute("tabindex"), "0")
    assert.equal(box.getAttribute("aria-label"), "Programma, 7 righe")
    assert.equal(box.getAttribute("translate"), "no")
    assert.equal(box.getAttribute("data-speech-text"), "Un programma di 7 righe.", "Ascolta does not read a listing, it says there is one")
    assert.equal(root.byClass("code-title")[0].textContent, "Programma", "no title: the fixed one")
  })
})

test("the code never wraps: the box is `white-space: pre` and scrolls sideways; only print wraps", () => {
  const css = readFileSync(new URL("../../../assets/stylesheets/lesson.css", import.meta.url), "utf8")
  const screen = css.slice(css.indexOf("/* code (D-329)"))
  const [screenRules, printRules] = screen.split("@media print")
  const box = screenRules.match(/\.block-code \.code-box, \.block-code \.code-screen \{[^}]*\}/)[0]
  assert.match(box, /white-space: pre;/)
  assert.match(box, /overflow-x: auto;/)
  assert.match(box, /max-width: 100%/)
  assert.match(box, /monospace/)
  assert.doesNotMatch(screenRules, /pre-wrap[^}]*code-box|code-box[^}]*pre-wrap/, "no wrapping rule for the program outside print")
  assert.match(printRules, /pre-wrap/)
})

test("\"Copia\" puts the text of the block on the clipboard exactly, and \"Copiato\" shows, then goes", async () => {
  mock.timers.enable({ apis: ["setTimeout"] })
  try {
    await withDom(async () => {
      let written = null
      setClipboard(async (text) => { written = text })
      const block = { type: "code", lang: "vb", text: PROGRAM }
      assert.equal(copyText(block), PROGRAM)
      const root = render(block, ctx)
      const [copy] = root.byClass("code-copy")
      const [status] = root.byClass("code-status")
      assert.equal(copy.textContent, "Copia")
      await copy.listeners.click()
      assert.equal(written, PROGRAM, "the trailing newline, the empty line and the four spaces are all there")
      assert.equal(copy.textContent, "Copiato")
      assert.ok(copy.classList.contains("is-copied"))
      assert.equal(status.textContent, "Copiato")
      assert.equal(status.getAttribute("role"), "status")
      mock.timers.tick(COPIED_MS)
      assert.equal(copy.textContent, "Copia")
      assert.ok(!copy.classList.contains("is-copied"))
      assert.equal(status.textContent, "")
    })
  } finally {
    mock.timers.reset()
  }
})

test("when the clipboard is refused the program is selected and the message says what to press", async () => {
  mock.timers.enable({ apis: ["setTimeout"] })
  try {
    await withDom(async (selected) => {
      setClipboard(async () => { throw new Error("NotAllowedError") })
      const root = render({ type: "code", lang: "vb", text: PROGRAM }, ctx)
      const [copy] = root.byClass("code-copy")
      await copy.listeners.click()
      assert.equal(root.byClass("code-status")[0].textContent, "Non riesco a copiare")
      assert.equal(copy.textContent, "Copia", "no \"Copiato\" for a copy that did not happen")
      assert.equal(selected.length, 1)
      assert.equal(selected[0], root.byClass("code-box")[0])
    })
  } finally {
    mock.timers.reset()
  }
})

test("what S types and what the screen shows come after the box, each only when the block has it", async () => {
  await withDom(() => {
    const bare = render({ type: "code", lang: "vb", text: "x" }, ctx)
    assert.equal(bare.byClass("code-io").length, 0)
    const full = render({ type: "code", lang: "vb", text: "x", input_it: ["35000", "Marta"], output: "Quota: 35000\n  Ciao, Marta\n" }, ctx)
    const [typed, screen] = full.byClass("code-io")
    assert.equal(typed.byClass("code-label")[0].textContent, "Scrivi:")
    assert.deepEqual(typed.byClass("code-key").map((k) => k.textContent), ["35000", "Marta"])
    assert.equal(typed.byClass("code-hint")[0].textContent, "Dopo ogni riga premi Invio.")
    assert.equal(screen.byClass("code-label")[0].textContent, "Sullo schermo vedi:")
    assert.equal(screen.byClass("code-screen")[0].textContent, "Quota: 35000\n  Ciao, Marta")
    assert.equal(screen.byClass("code-screen")[0].getAttribute("aria-label"), "Schermo, 2 righe")
    assert.equal(typed.getAttribute("data-nospeech"), "")
    assert.equal(screen.getAttribute("data-nospeech"), "")
    const onlyOutput = render({ type: "code", lang: "vb", text: "x", output: "ciao" }, ctx)
    assert.equal(onlyOutput.byClass("code-io").length, 1)
    assert.equal(onlyOutput.byClass("code-input").length, 0)
  })
})

test("nothing a program holds is read as markup or HTML: it is a text node", async () => {
  await withDom(() => {
    const text = "Dim s As String = $\"{a} <b>e</b> [[es:no]] $x_1$\""
    const [box] = render({ type: "code", lang: "vb", text }, ctx).byClass("code-box")
    assert.equal(box.textContent, text)
    assert.equal(box.children[0].children.length, 0, "the code element holds no element, only its text")
  })
})
