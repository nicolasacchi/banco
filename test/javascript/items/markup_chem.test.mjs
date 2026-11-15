// \ce{} in items (D-282): the items renderer loads KaTeX's mhchem on the first chemistry formula, so no practice, test or teacher
// page shows `\ce{Na + O2 -> 2Na2O}` as a red error. The vendored KaTeX, a minimal DOM.
import "../../../app/javascript/lesson/test/setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

function node(tag = "span") {
  return {
    tag, className: "", children: [], _text: "",
    set textContent(v) { this._text = v; this.children = [] },
    get textContent() { return this._text + this.children.map((c) => c.textContent).join("") },
    appendChild(c) { this.children.push(c); return c },
    get html() { return this._text + this.children.map((c) => (c.className ?? "") + c.html).join("") }
  }
}
globalThis.document = {
  compatMode: "CSS1Compat",
  createElement: (tag) => node(tag),
  createTextNode: (text) => ({ className: "", textContent: text, html: "", nodeType: 3 }),
  createDocumentFragment: () => node("#fragment")
}

const { renderMath, renderInline, ensureChem } = await import("items/markup")
const katex = (await import("katex")).default

// katex.render fills `target.innerHTML`; capture it in the fake node.
katex.render = (latex, target, options) => {
  const html = katex.renderToString(latex, options)
  target.innerHTML = html
}

const CE = "\\ce{Na + O2 -> 2Na2O}"

test("a formula without chemistry renders at once", () => {
  const span = node()
  renderMath("x^2 + 1", span)
  assert.ok(span.innerHTML.includes("katex"))
  assert.ok(!span.innerHTML.includes("katex-error"))
})

test("\\ce before mhchem is loaded shows plain text, then renders without katex-error", async () => {
  const span = node()
  renderMath(CE, span)
  assert.equal(span.textContent, CE)
  assert.equal(span.innerHTML, undefined)
  await ensureChem()
  await new Promise((resolve) => setTimeout(resolve, 0))
  assert.ok(span.innerHTML.includes("katex"), "drawn by KaTeX")
  assert.ok(!span.innerHTML.includes("katex-error"), span.innerHTML.slice(0, 200))
  assert.ok(span.innerHTML.includes("Na"))
})

test("once mhchem is loaded \\ce and \\pu render synchronously", () => {
  for (const latex of [CE, "\\pu{1.5 mol/L}", "\\ce{H2O}"]) {
    const span = node()
    renderMath(latex, span)
    assert.ok(span.innerHTML.includes("katex"), latex)
    assert.ok(!span.innerHTML.includes("katex-error"), latex)
  }
})

test("a real mistake inside \\ce still shows as a KaTeX error, not as a hang", () => {
  const span = node()
  renderMath("\\ce{H2O", span)
  assert.ok(span.innerHTML.includes("katex-error"))
})

test("renderInline of a $\\ce{}$ prompt draws the formula", () => {
  const p = node("p")
  renderInline(`Equilibra: $${CE}$`, p)
  const math = p.children.find((c) => c.className === "math")
  assert.ok(math.innerHTML.includes("katex"))
  assert.ok(!math.innerHTML.includes("katex-error"))
})
