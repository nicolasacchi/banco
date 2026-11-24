// The render host of one instance of an item revision (D-336). Loaded by the harness listener's item-render.html, which Chrome opens at one
// viewport and theme. It draws the instance with the student's own renderer (items/render.js: the templates, KaTeX, MathLive, the figure's <img>),
// unanswered, in the frame the page already holds, and answers the server's Chrome through window.bancoItemRender:
//
//   ready       Promise { ok, error?, findings: [{ code, message, where }], height, exceptions }   (the instance drawn and measured)
//   measure()   the page's height now (the runner calls it after it has made the window as tall as the page, to take the whole instance)
//
// Findings (aids for the reviewer, never a verdict of the item): E-ITEM-OVERFLOW (the page wider than the window, something wider than its box,
// a long formula that scrolls sideways inside its box), E-ITEM-RENDER (an exception or a console error, a KaTeX error, markup printed as text,
// a figure that did not draw). The item is what the student is told: the page holds no key, and nothing here is sent anywhere (the CSP of the
// host allows no connection).
import { renderItem } from "items/render"
import { ensureChem } from "items/markup"
import { rawMarkupIn } from "lesson/raw_markup"
import { refresh } from "items/translation"

const errors = []
const note = (message) => errors.push(String(message).slice(0, 300))
window.addEventListener("error", (event) => note(event.message || event.error))
window.addEventListener("unhandledrejection", (event) => note(event.reason?.message ?? event.reason))
window.addEventListener("securitypolicyviolation", (event) => note(`blocked by the page's policy: ${event.violatedDirective} ${event.blockedURI}`))
for (const level of ["error", "warn"]) {
  const original = console[level].bind(console)
  console[level] = (...args) => { note(`console.${level}: ${args.map(String).join(" ")}`); original(...args) }
}

const presentation = JSON.parse(document.getElementById("item-presentation").textContent)
const config = JSON.parse(document.getElementById("item-config").textContent)
const box = document.getElementById("item-box")
// ?tr=1 (D-402): the item as the student sees it with «Traduzione» open: the item box is a translation scope that is on. Without it the Italian is drawn but
// hidden, as the student first sees the exercise.
const translationOpen = new URLSearchParams(location.search).get("tr") === "1"

// A bound on every wait: a page that never settles answers by name instead of leaving the server's Chrome to give up on it.
const READY_LIMIT_MS = Math.min(Number(new URLSearchParams(location.search).get("ready_ms")) || 20000, 20000)
const readyBy = performance.now() + READY_LIMIT_MS
const waitFor = (what, promise) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`waited more than ${READY_LIMIT_MS / 1000} s for ${what}`)), Math.max(0, readyBy - performance.now()))
  Promise.resolve(promise).then(resolve, reject).finally(() => clearTimeout(timer))
})
const frames = () => new Promise((resolve) => {
  const timer = setTimeout(resolve, 120)
  requestAnimationFrame(() => requestAnimationFrame(() => { clearTimeout(timer); resolve() }))
})
const settle = async () => {
  await frames()
  await new Promise((resolve) => setTimeout(resolve, 90))
}
const text = (node) => (node.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60)
const describe = (node) => `${node.tagName.toLowerCase()}${typeof node.className === "string" && node.className.trim() ? `.${node.className.trim().split(/\s+/)[0]}` : ""}`

const uses = (pattern) => pattern.test(JSON.stringify(presentation))
const withExpression = () => presentation.component === "expression" || (presentation.sub_items || []).some((sub) => sub.component === "expression")

const height = () => Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)

const OVERFLOW_CULPRITS = 4

// What is really cut or pushes the page, not a layout that is meant to bleed (the action bar's negative margins reach the card's edges, so the box
// of its parent holds 30 px more than it shows: nothing is lost there). Three things count, as the lesson render check reads them:
//  - the page wider than the window;
//  - a box that clips or scrolls (overflow-x hidden, clip, auto or scroll) whose content is wider than it: a long formula that scrolls sideways, a
//    box that cuts its text;
//  - something drawn outside the window (its own box crosses the left or right edge) that no such box holds: the culprit of a wide page.
const clips = (style) => style.overflowX !== "visible"
function clipperOf(node) {
  for (let up = node.parentElement; up && up !== document.body && up !== document.documentElement; up = up.parentElement) {
    if (clips(getComputedStyle(up))) return up
  }
  return null
}

function overflowFindings(out) {
  const doc = document.documentElement
  if (doc.scrollWidth > window.innerWidth + 1)
    out.push({ code: "E-ITEM-OVERFLOW", message: `the page is ${doc.scrollWidth} px wide in a ${window.innerWidth} px window`, where: "page" })
  const wide = []
  for (const node of document.body.querySelectorAll("*")) {
    if (node.closest(".sr-only") || node.namespaceURI !== document.documentElement.namespaceURI) continue // SVG and MathML inside are not boxes
    if (node.clientWidth < 3 || node.closest(".katex-mathml")) continue
    const style = getComputedStyle(node)
    if (clips(style) && node.scrollWidth > node.clientWidth + 3) {
      wide.push({ node, scrolls: style.overflowX === "auto" || style.overflowX === "scroll" })
      continue
    }
    if (clips(style) || clipperOf(node)) continue // a box that holds it clips or scrolls it: that box is the finding, not this
    const rect = node.getBoundingClientRect()
    if (rect.width > 0 && (rect.right > window.innerWidth + 1 || rect.left < -1) && getComputedStyle(node).display !== "inline")
      wide.push({ node, scrolls: false, outside: true })
  }
  // the innermost ones say where the width comes from
  const inner = wide.filter(({ node }) => !wide.some((other) => other.node !== node && node.contains(other.node)))
  for (const { node, scrolls, outside } of inner.slice(0, OVERFLOW_CULPRITS)) {
    const where = text(node) || describe(node)
    let message
    if (outside) message = `${describe(node)} is drawn outside the window (${Math.round(node.getBoundingClientRect().left)} to ${Math.round(node.getBoundingClientRect().right)} px of ${window.innerWidth})`
    else if (scrolls) message = `${describe(node)} scrolls sideways: ${node.scrollWidth} px of content in a ${node.clientWidth} px box`
    else message = `${describe(node)} cuts its content: ${node.scrollWidth} px of content in a ${node.clientWidth} px box`
    out.push({ code: "E-ITEM-OVERFLOW", message, where })
  }
}

function renderFindings(out) {
  for (const bad of box.querySelectorAll(".katex-error"))
    out.push({ code: "E-ITEM-RENDER", message: `KaTeX cannot draw "${text(bad)}": ${bad.getAttribute("title") || "parse error"}`, where: "formula" })
  const hit = rawMarkupIn(box)
  if (hit) out.push({ code: "E-ITEM-RENDER", message: `markup printed as text: "${hit.text.slice(0, 60)}"`, where: text(hit.where) || "item" })
  for (const image of box.querySelectorAll("img")) {
    if (!image.complete || image.naturalWidth === 0)
      out.push({ code: "E-ITEM-RENDER", message: `a figure did not draw (${image.getAttribute("src") || "no source"})`, where: image.getAttribute("alt") || "figure" })
  }
  for (const message of errors.splice(0)) out.push({ code: "E-ITEM-RENDER", message: `exception: ${message}`, where: "page" })
}

const ready = (async () => {
  try {
    await waitFor("the fonts", document.fonts?.ready)
    // a web font is fetched when text first wears it: every face is loaded before the instance is measured, or its text is measured in the fallback
    if (document.fonts) await waitFor("the fonts", Promise.allSettled([...document.fonts].map((face) => face.load())))
    // The shots are the solver's pictures too: the passage's Italian (withheld from the student until the answer) is not in the presentation, so it is not drawn.
    const handle = await waitFor("the item", renderItem(presentation, { t: config.texts }))
    box.setAttribute("data-tr-scope", "item")
    box.setAttribute("data-translation", translationOpen ? "on" : "off")
    box.appendChild(handle.element)
    handle.mounted()
    refresh(box)
    // a chemistry formula is drawn as plain text until mhchem arrives (items/markup.js); the redraw is queued on the same promise
    if (uses(/\\(?:ce|pu)\{/)) await waitFor("mhchem", ensureChem().catch(() => {}))
    // MathLive's field is a custom element that draws once defined; its fonts come from the app origin
    if (withExpression()) await waitFor("the maths field", customElements.whenDefined("math-field"))
    // a figure is an <img> of the stored copy: drawn when the bytes are here
    await waitFor("the figure", Promise.all([...box.querySelectorAll("img")].map((image) => image.decode().catch(() => {}))))
    await settle()
    const findings = []
    overflowFindings(findings)
    renderFindings(findings)
    return { ok: true, findings, height: height(), exceptions: [] }
  } catch (error) {
    return { ok: false, error: String(error?.message ?? error).slice(0, 300), findings: [], height: height(), exceptions: errors.splice(0) }
  }
})()

window.bancoItemRender = { ready, measure: height }
