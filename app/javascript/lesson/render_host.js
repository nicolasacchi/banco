// The render host of a lesson/2 revision (R4, A12.2). Loaded by the harness listener's lesson-render.html, which Chrome
// opens at one viewport and theme. It draws the lesson with the student's renderer, every "more" open, every mistake
// turned and every step shown (config.expand), and answers the server's Chrome through window.bancoLessonRender:
//
//   ready                      Promise { ok, error?, cards: [{ n, level }], exceptions }  (renderAll() done)
//   printSummary()             Promise { ok, n? }  the page set up as "Stampa riassunto e schema" prints it
//   inspect(n, options)        Promise { n, findings: [{ code, message, where }], height }  for card n (0 is the cover),
//                              after stepping every figure of the card through its states
//
// Findings (all errors, they depend on the author's data): E-LESSON-RENDER (an exception, a KaTeX error),
// E-LESSON-OVERFLOW (something wider than its box or than the page), E-DIAGRAM-LAYOUT (a layout that answered an
// error, two labels overlapping, a label outside the drawing), E-DIAGRAM-SMALL-TEXT (a label under the minimum), E-DIAGRAM-TARGET (a select target under 24 x 24 px).
// Nothing here is sent anywhere; the CSP of the host allows no connection.
import { renderLesson } from "lesson/render"
import { preloadFor } from "lesson/preload"

const errors = []
const note = (message) => errors.push(String(message).slice(0, 300))
window.addEventListener("error", (event) => note(event.message || event.error))
window.addEventListener("unhandledrejection", (event) => note(event.reason?.message ?? event.reason))

// two animation frames, but never longer than 120 ms: a page that Chrome throttles (not in front, a busy machine) answers no frame for seconds,
// and a card must not wait for what the check does not need (the render time budget, D-255)
const frames = () => new Promise((resolve) => {
  const timer = setTimeout(resolve, 120)
  requestAnimationFrame(() => requestAnimationFrame(() => { clearTimeout(timer); resolve() }))
})
const text = (node) => (node.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60)

function rectOfText(node) {
  const range = document.createRange()
  range.selectNodeContents(node)
  const rect = range.getBoundingClientRect()
  return rect.width > 0 && rect.height > 0 ? rect : node.getBoundingClientRect()
}

function overlap(a, b) {
  const w = Math.min(a.right, b.right) - Math.max(a.left, b.left)
  const h = Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top)
  return w > 2 && h > 2
}

function figureFindings(figure, minPx, state, out) {
  const tag = `state ${state + 1}`
  if (figure.dataset.error) {
    const code = figure.dataset.error.startsWith("E-DIAGRAM-SMALL-TEXT") ? "E-DIAGRAM-SMALL-TEXT" : "E-DIAGRAM-LAYOUT"
    out.push({ code, message: `the layout answered an error: ${figure.dataset.error}`, where: `${figure.dataset.type} figure, ${tag}` })
    return
  }
  const stage = figure.querySelector(".dg-stage")?.getBoundingClientRect()
  const labels = [...figure.querySelectorAll(".dg-label:not(.dg-measure)")].filter((l) => l.textContent.trim() !== "" && l.getClientRects().length > 0) // a hidden label (the print views) has no box to judge
  const boxes = labels.map((l) => ({ label: l, rect: rectOfText(l) }))
  for (const { label, rect } of boxes) {
    const px = parseFloat(getComputedStyle(label).fontSize)
    if (px < minPx - 0.01) out.push({ code: "E-DIAGRAM-SMALL-TEXT", message: `the label "${text(label)}" is drawn at ${px.toFixed(1)} px, under ${minPx} px`, where: `${figure.dataset.type} figure, ${tag}` })
    if (stage && (rect.left < stage.left - 2 || rect.right > stage.right + 2))
      out.push({ code: "E-DIAGRAM-LAYOUT", message: `the label "${text(label)}" is drawn outside the figure`, where: `${figure.dataset.type} figure, ${tag}` })
  }
  // a select figure draws exactly the targets of the check's own set (none drawn is as wrong as a different number)
  if (typeof figure.selectTotal === "function") {
    const expected = figure.selectTotal()
    const drawn = figure.querySelectorAll(".dg-target").length
    if (drawn === 0 || drawn !== expected)
      out.push({ code: "E-DIAGRAM-TARGET", message: `the figure draws ${drawn} of the ${expected} targets of the check`, where: `${figure.dataset.type} figure, ${tag}` })
  }
  // a select check's tap targets are at least 24 x 24 CSS px (WCAG 2.2 target size, A2)
  for (const target of figure.querySelectorAll(".dg-target")) {
    const r = target.getBoundingClientRect()
    if (r.width < 23.5 || r.height < 23.5)
      out.push({ code: "E-DIAGRAM-TARGET", message: `a select target is ${r.width.toFixed(0)} x ${r.height.toFixed(0)} px, under 24 x 24`, where: `${figure.dataset.type} figure, ${tag}` })
  }
  // a node's text must clear the node's border (a text measured in another face than it is drawn in touches or crosses it)
  const nodeRects = [...figure.querySelectorAll(".dg-node")].map((n) => n.getBoundingClientRect())
  for (const { label, rect } of boxes) {
    if (!label.classList.contains("dg-nodetext") || label.querySelector(".katex")) continue // a formula holds its own hidden MathML twin: its text range is not what is drawn
    const cx = (rect.left + rect.right) / 2
    const cy = (rect.top + rect.bottom) / 2
    const node = nodeRects.find((r) => cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom)
    if (node && (rect.left < node.left + 3 || rect.right > node.right - 3 || rect.top < node.top + 1 || rect.bottom > node.bottom - 1))
      out.push({ code: "E-DIAGRAM-LAYOUT", message: `the text "${text(label)}" touches or crosses the border of its box`, where: `${figure.dataset.type} figure, ${tag}` })
  }
  for (let i = 0; i < boxes.length; i++) {
    for (let j = i + 1; j < boxes.length; j++) {
      if (overlap(boxes[i].rect, boxes[j].rect))
        out.push({ code: "E-DIAGRAM-LAYOUT", message: `the labels "${text(boxes[i].label)}" and "${text(boxes[j].label)}" overlap`, where: `${figure.dataset.type} figure, ${tag}` })
    }
  }
  for (const t of figure.querySelectorAll("svg text")) {
    const px = parseFloat(getComputedStyle(t).fontSize)
    if (px < minPx - 0.01) out.push({ code: "E-DIAGRAM-SMALL-TEXT", message: `a drawing text is at ${px.toFixed(1)} px, under ${minPx} px`, where: `${figure.dataset.type} figure, ${tag}` })
  }
}

// Something that scrolls or is clipped sideways inside the card, or the page wider than the window.
function overflowFindings(card, out) {
  const doc = document.documentElement
  if (doc.scrollWidth > window.innerWidth + 1)
    out.push({ code: "E-LESSON-OVERFLOW", message: `the page is ${doc.scrollWidth} px wide in a ${window.innerWidth} px window`, where: "page" })
  const nodes = [card, ...card.querySelectorAll("*")]
  const wide = []
  for (const node of nodes) {
    if (node.closest(".sr-only") || node.namespaceURI !== "http://www.w3.org/1999/xhtml") continue
    if (node.closest("thead")?.clientWidth <= 2) continue // a stacked table's head is visually hidden (1 px, clipped): its cells overflow nothing the student sees
    if (node.clientWidth < 3 || node.closest(".dg-labels")) continue // a label's own box is exact to within rounding: figureFindings reads the labels
    if (node.scrollWidth > node.clientWidth + 3 && getComputedStyle(node).display !== "inline") wide.push(node)
  }
  // the innermost one says where the width comes from: a card that clips its content is wide because of what is in it
  const culprit = wide.find((node) => !wide.some((other) => other !== node && node.contains(other)))
  if (culprit) {
    out.push({ code: "E-LESSON-OVERFLOW", message: `${culprit.tagName.toLowerCase()}${culprit.className && typeof culprit.className === "string" ? `.${culprit.className.trim().split(/\s+/)[0]}` : ""} is ${culprit.scrollWidth} px wide in a ${culprit.clientWidth} px box`, where: text(culprit) || "card" })
  }
}

function katexFindings(card, out) {
  for (const bad of card.querySelectorAll(".katex-error")) {
    out.push({ code: "E-LESSON-RENDER", message: `KaTeX cannot draw "${text(bad)}": ${bad.getAttribute("title") || "parse error"}`, where: "formula" })
  }
}

const config = JSON.parse(document.getElementById("lesson-config").textContent)
const body = JSON.parse(document.getElementById("lesson-body").textContent)
const root = document.getElementById("lesson-root")
const minPx = config.minPx ?? 18
let api = null

const ready = (async () => {
  try {
    await document.fonts?.ready
    // a web font is fetched when text first wears it: the figures measure their labels in the DOM, so every face of the page is loaded
    // before the first card is drawn, or a label is measured in the fallback face and drawn wider in the real one (its text then touches the box)
    if (document.fonts) await Promise.allSettled([...document.fonts].map((face) => face.load()))
    await preloadFor(body)
    api = renderLesson(root, body, {
      mode: "render", expand: true, view: "scroll", reduceMotion: true, labels: config.labels, items: config.items, topic: body.key,
      revisionId: 0, urls: { check: "", solution: "", practice: "#" }, savePreferences: () => {}
    })
    api.renderAll()
    await frames()
    api.setView("cards", false)
    await frames()
    return { ok: true, cards: body.cards.map((c) => ({ n: c.n, level: c.level })), exceptions: errors.splice(0) }
  } catch (error) {
    return { ok: false, error: String(error?.message ?? error).slice(0, 300), cards: [], exceptions: errors.splice(0) }
  }
})()

async function inspect(n) {
  const findings = []
  try {
    api.goTo(n, { focus: false })
    await frames()
    const card = root.querySelector(`#scheda-${n}`)
    if (!card) return { n, findings: [{ code: "E-LESSON-RENDER", message: `card ${n} was not drawn`, where: "card" }], height: 0 }
    const figures = api.figures().filter((f) => card.contains(f.element))
    if (figures.length === 0) overflowFindings(card, findings)
    const settle = async () => {
      await frames()
      await new Promise((resolve) => setTimeout(resolve, 90))
    }
    for (const figure of figures) {
      const total = figure.total ?? 1
      for (let i = 0; i < total; i++) {
        if (total > 1) figure.setState(i)
        await settle()
        figureFindings(figure.element, minPx, i, findings)
        overflowFindings(card, findings)
      }
    }
    katexFindings(card, findings)
  } catch (error) {
    findings.push({ code: "E-LESSON-RENDER", message: `exception: ${String(error?.message ?? error).slice(0, 200)}`, where: "card" })
  }
  for (const message of errors.splice(0)) findings.push({ code: "E-LESSON-RENDER", message: `exception: ${message}`, where: "card" })
  const seen = new Set()
  const unique = findings.filter((f) => {
    const key = `${f.code}|${f.message}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
  return { n, findings: unique, height: document.documentElement.scrollHeight }
}

// "Stampa riassunto e schema" (A10): the summary card alone, as render.js prints it; the server's Chrome then counts the
// pages of the PDF (it runs under print media, set by the caller).
async function printSummary() {
  const summary = body.cards.find((c) => c.role === "summary" && c.level === "core")
  if (!summary) return { ok: true, skipped: true }
  api.goTo(summary.n, { focus: false })
  root.dataset.print = "summary"
  api.relayout()
  await frames()
  api.relayout()
  await frames()
  return { ok: true, n: summary.n }
}

window.bancoLessonRender = { ready, inspect, printSummary }
