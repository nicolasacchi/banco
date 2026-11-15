// A formula and its mark are glued in prose (span.nowrap, D-335) but never in a diagram label: the layout measures a label, and a nowrap span
// changed the width it was measured and wrapped at, so a flow node «$\Delta < 0$?» overlapped its edge label «sì» (E-DIAGRAM-LAYOUT).
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { layout } = await import("lesson/diagrams/flow")
const { makeMeasure } = await import("lesson/diagrams/draw")
const { renderRich, renderInlineRich } = await import("lesson/text")

class Fake {
  constructor(tag) { this.tag = tag; this.attrs = {}; this.children = []; this.own = ""; this.style = {}; this.classList = { add() {}, remove() {} } }
  set className(v) { this.attrs.class = v }
  get className() { return this.attrs.class ?? "" }
  set textContent(v) { this.children = []; this.own = String(v) }
  get textContent() { return this.own + this.children.map((c) => c.textContent).join("") }
  setAttribute(name, value) { this.attrs[name] = String(value) }
  getAttribute(name) { return this.attrs[name] ?? null }
  get firstChild() { return this.children[0] ?? null }
  removeChild(child) { this.children = this.children.filter((c) => c !== child); return child }
  remove() {}
  replaceChildren() { this.children = [] }
  getBoundingClientRect() { return { width: 40, height: 20 } }
  appendChild(child) {
    if (child instanceof Fake && child.tag === "#fragment") { for (const c of child.children) this.appendChild(c); child.children = []; return child }
    this.children.push(child)
    return child
  }
  append(...nodes) { for (const node of nodes) this.appendChild(node) }
  all(pred, out = []) {
    for (const child of this.children) if (child instanceof Fake) { if (pred(child)) out.push(child); child.all(pred, out) }
    return out
  }
}
function withDom(fn) {
  globalThis.document = {
    createElement: (tag) => new Fake(tag),
    createElementNS: (_ns, tag) => new Fake(tag),
    createDocumentFragment: () => new Fake("#fragment"),
    createTextNode: (text) => ({ nodeType: 3, textContent: String(text) })
  }
  globalThis.window = {}
  try { return fn() } finally { delete globalThis.document; delete globalThis.window }
}
const wrappers = (root) => root.all((n) => n.getAttribute("class") === "nowrap")
const ctx = { subject: "math", t: {} }
const LABEL = "$\\Delta < 0$?"

test("a flow whose node is «$\\Delta < 0$?» with a «sì» edge lays out with no overlap", () => {
  const flow = {
    type: "flow", alt_it: "Schema: il segno del discriminante.",
    nodes: [{ id: "q", kind: "decision", text_it: LABEL }, { id: "s", kind: "end", text_it: "Due soluzioni" }, { id: "n", kind: "end", text_it: "Nessuna soluzione" }],
    edges: [["q", "s", "sì"], ["q", "n", "no"]]
  }
  for (const width of [240, 390, 760]) {
    const scene = layout(flow, { width, fontPx: 20, subject: "math" })
    assert.ok(!scene.error, `${width}: ${scene.error?.message}`)
  }
})

test("the text a diagram measures and draws carries no wrapper; prose still does", () => {
  withDom(() => {
    const host = new Fake("div")
    const m = makeMeasure(host, ctx)
    m.measure(LABEL, 20, 120)
    assert.equal(wrappers(m.probe).length, 0, "the measuring probe is not glued")
    const prose = renderRich(`Se ${LABEL}`, ctx)
    assert.equal(wrappers(prose).length, 1)
    const label = new Fake("div")
    renderInlineRich(LABEL, label, { ...ctx, noGlue: true })
    assert.equal(wrappers(label).length, 0)
  })
})
