// The render host of a lesson/2 revision (R4, A12.2). Loaded by the harness listener's lesson-render.html, which Chrome
// opens at one viewport and theme. It draws the lesson with the student's renderer, every "more" open, every mistake
// turned and every step shown (config.expand), and answers the server's Chrome through window.bancoLessonRender:
//
//   ready                      Promise { ok, error?, cards: [{ n, level }], exceptions }  (renderAll() done)
//   printSummary()             Promise { ok, n? }  the page set up as "Stampa riassunto e schema" prints it
//   inspect(n, state)          Promise { n, state, findings: [{ code, message, where }], height, states }  for card n (0 is the cover)
//                              in one of its states, after stepping every figure shown in that state through its states
//
// The states of a card (D-311): null is the card as drawn (the first exercise of each «Prova tu» shown); "ex<N>" is the card with
// exercise N of its «Prova tu» shown instead (the pager shows one exercise at a time); "open" and "ex<N>-open" are the same with every
// closed disclosure opened at once (a closed <details>, the hidden text of a listening check, the glossary bubbles). inspect(n) answers
// the card's further states in `states`; each inspect first undoes what the previous one changed, so the states never add up.
//
// Findings (all errors, they depend on the author's data): E-LESSON-RENDER (an exception, a KaTeX error, markup printed as text: D-310),
// E-LESSON-OVERFLOW (something wider than its box or than the page), E-DIAGRAM-LAYOUT (a layout that answered an
// error, two labels overlapping, a label outside the drawing, a box's text or icon outside its box), E-DIAGRAM-SMALL-TEXT
// (a label under the minimum), E-DIAGRAM-TARGET (a select target under 24 x 24 px).
// Nothing here is sent anywhere; the CSP of the host allows no connection.
import { renderLesson } from "lesson/render"
import { preloadFor } from "lesson/preload"
import { rawMarkupIn } from "lesson/raw_markup"

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
// the frames, then the figures' redraw debounce (60 ms in draw.js)
const settle = async () => {
  await frames()
  await new Promise((resolve) => setTimeout(resolve, 90))
}
const text = (node) => (node.textContent || "").replace(/\s+/g, " ").trim().slice(0, 60)
const shown = (node) => node.getClientRects().length > 0 // nothing under display: none (a hidden exercise, a closed card) has a box

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

// The box a label is the text of: the shape whose key the label's key extends (`K:t`, `K:label`), else the node under its centre.
function boxOf(figure, label, rect, nodes) {
  const key = label.dataset.key?.replace(/:(t|label)$/, "")
  if (key && key !== label.dataset.key) {
    const keyed = figure.querySelector(`.dg-node[data-key="${CSS.escape(key)}"]`)
    if (keyed) return { node: keyed, rect: keyed.getBoundingClientRect() }
  }
  const cx = (rect.left + rect.right) / 2
  const cy = (rect.top + rect.bottom) / 2
  return nodes.find(({ rect: r }) => cx >= r.left && cx <= r.right && cy >= r.top && cy <= r.bottom) ?? null
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
  // a box's text must clear the box's border (a text measured in another face than it is drawn in touches or crosses it; a word wider
  // than the box runs out of it), and the box's icon must sit inside it, clear of the text (a mirror piece with a role, D-311)
  const nodes = [...figure.querySelectorAll(".dg-node")].map((n) => ({ node: n, rect: n.getBoundingClientRect() }))
  for (const { label, rect } of boxes) {
    if (!label.classList.contains("dg-nodetext") || label.querySelector(".katex")) continue // a formula holds its own hidden MathML twin: its text range is not what is drawn
    const box = boxOf(figure, label, rect, nodes)
    if (!box) continue
    const r = box.rect
    if (rect.left < r.left + 3 || rect.right > r.right - 3 || rect.top < r.top + 1 || rect.bottom > r.bottom - 1)
      out.push({ code: "E-DIAGRAM-LAYOUT", message: `the text "${text(label)}" touches or crosses the border of its box`, where: `${figure.dataset.type} figure, ${tag}` })
    const key = box.node.dataset.key
    const iconNode = key ? figure.querySelector(`[data-key="${CSS.escape(`${key}:icon`)}"]`) : null
    if (iconNode && shown(iconNode)) {
      const ir = iconNode.getBoundingClientRect()
      if (ir.left < r.left - 1 || ir.right > r.right + 1 || ir.top < r.top - 1 || ir.bottom > r.bottom + 1)
        out.push({ code: "E-DIAGRAM-LAYOUT", message: `the icon of the box "${text(label)}" is drawn outside its box`, where: `${figure.dataset.type} figure, ${tag}` })
      else if (overlap(ir, rect))
        out.push({ code: "E-DIAGRAM-LAYOUT", message: `the text "${text(label)}" runs over the icon of its box`, where: `${figure.dataset.type} figure, ${tag}` })
    }
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

const OVERFLOW_CULPRITS = 4

// Something that scrolls or is clipped sideways inside the card, or the page wider than the window.
function overflowFindings(card, out, scope = card) {
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
  // the innermost ones say where the width comes from: a card that clips its content is wide because of what is in it. Each one apart
  // (a few at most), so that a second state of the card that adds its own is not hidden behind the first.
  const inner = wide.filter((node) => !wide.some((other) => other !== node && node.contains(other)))
  // in a state's own scope first, so that the culprits of the rest of the card do not use up the cap
  const culprits = [...inner.filter((n) => scope.contains(n)), ...inner.filter((n) => !scope.contains(n))].slice(0, OVERFLOW_CULPRITS)
  for (const culprit of culprits) {
    out.push({ code: "E-LESSON-OVERFLOW", message: `${culprit.tagName.toLowerCase()}${culprit.className && typeof culprit.className === "string" ? `.${culprit.className.trim().split(/\s+/)[0]}` : ""} is ${culprit.scrollWidth} px wide in a ${culprit.clientWidth} px box`, where: text(culprit) || "card" })
  }
}

function katexFindings(card, out) {
  for (const bad of card.querySelectorAll(".katex-error")) {
    out.push({ code: "E-LESSON-RENDER", message: `KaTeX cannot draw "${text(bad)}": ${bad.getAttribute("title") || "parse error"}`, where: "formula" })
  }
}

// markup the student would read as written ("[[es:hablar]]", "$a^3$"): a field drawn as plain text (D-310)
function markupFindings(card, out) {
  const hit = rawMarkupIn(card)
  if (hit) out.push({ code: "E-LESSON-RENDER", message: `markup printed as text: "${hit.text.slice(0, 60)}"`, where: text(hit.where) || "card" })
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

// ---- the states of a card ----

// What the last state changed, undone before the next one is set up.
const undo = []
const restore = () => {
  for (const fn of undo.splice(0).reverse()) {
    try {
      fn()
    } catch (_error) {
      // a part that is gone (the card was drawn again) has nothing left to close
    }
  }
}

// The exercises of the card's «Prova tu» blocks: { li, n, index, dots } (the pager's number chips are what the student taps).
function exercisesOf(card) {
  return [...card.querySelectorAll(".block.try")].flatMap((block) => {
    const dots = [...block.querySelectorAll(".try-dot")]
    return [...block.querySelectorAll(".exercises > .exercise")].map((li, index) => ({ li, n: li.dataset.n, index, dots }))
  })
}

function showExercise(ex) {
  ex.dots[ex.index]?.click()
  document.activeElement?.blur?.()
  undo.push(() => {
    ex.dots[0]?.click()
    document.activeElement?.blur?.()
  })
}

// The closed disclosures of a part of the page, each with its way to open and to close: a closed <details> (not one hidden on
// purpose) and "Mostra il testo" of a listening check. Only what is on screen (a disclosure inside a closed one is found once the
// outer one is open). The glossary bubbles are looked at one at a time (glossFindings).
const LISTEN = ".listen-show[aria-expanded='false']"
const GLOSS = ".gloss-btn[aria-expanded='false']"
function closedParts(scope) {
  const parts = []
  for (const details of scope.querySelectorAll("details:not([open])")) {
    if (!details.hidden && shown(details)) parts.push({ open: () => { details.open = true }, close: () => { details.open = false } })
  }
  for (const b of scope.querySelectorAll(LISTEN)) {
    if (shown(b)) parts.push({ open: () => b.click(), close: () => { if (b.getAttribute("aria-expanded") === "true") b.click() } })
  }
  return parts
}
const glossButtons = (scope) => [...scope.querySelectorAll(GLOSS)].filter(shown)
const hasClosedParts = (scope) => [...scope.querySelectorAll("details:not([open])")].some((d) => !d.hidden) || scope.querySelector(`${LISTEN}, ${GLOSS}`) !== null

function openParts(scope) {
  for (let pass = 0; pass < 3; pass++) {
    const parts = closedParts(scope)
    if (parts.length === 0) break
    for (const part of parts) {
      part.open()
      undo.push(part.close)
    }
  }
}

// A glossary bubble opens over the text under its word (position: absolute), so it is wider than its paragraph by design: what
// counts is that it stays inside its card and the window (render.js places it so) and that nothing in it is wider than the bubble.
function glossFindings(scope, out) {
  for (const b of glossButtons(scope)) {
    b.click()
    const pop = b.parentElement.querySelector(".gloss-pop")
    if (pop && !pop.hidden) {
      const term = text(b.parentElement.querySelector(".gloss-word") ?? b.parentElement)
      const r = pop.getBoundingClientRect()
      const box = (pop.closest(".card-body, .l2-card") ?? document.documentElement).getBoundingClientRect()
      if (r.left < Math.max(0, box.left) - 1 || r.right > Math.min(window.innerWidth, box.right) + 1)
        out.push({ code: "E-LESSON-OVERFLOW", message: `the glossary bubble of "${term}" leaves its card`, where: term })
      overflowFindings(pop, out)
    }
    b.click()
  }
}

// The further states of a card, in the order the runner asks for them.
function statesOf(card) {
  const states = []
  if (closedParts(card).length > 0 || glossButtons(card).length > 0) states.push("open")
  for (const ex of exercisesOf(card)) {
    if (ex.index === 0) continue
    states.push(`ex${ex.n}`)
    if (hasClosedParts(ex.li)) states.push(`ex${ex.n}-open`)
  }
  return states
}

const STATE = /^ex(\d+)(-open)?$|^open$/

async function inspect(n, state = null) {
  const findings = []
  let states = []
  try {
    restore()
    api.goTo(n, { focus: false })
    await frames()
    const card = root.querySelector(`#scheda-${n}`)
    if (!card) return { n, state, findings: [{ code: "E-LESSON-RENDER", message: `card ${n} was not drawn`, where: "card" }], height: 0, states }
    const match = state ? String(state).match(STATE) : null
    if (state && !match) throw new Error(`unknown state ${state}`)
    let scope = card
    if (match?.[1]) {
      const ex = exercisesOf(card).find((e) => e.n === match[1])
      if (!ex) throw new Error(`card ${n} has no exercise ${match[1]}`)
      showExercise(ex)
      scope = ex.li
      await frames() // what lays itself out when shown (a resize observer) has done so
      // a figure of a hidden exercise waited at width 0: drawn now at the width it has
      for (const figure of api.figures()) if (scope.contains(figure.element)) figure.relayout?.()
    }
    if (state === "open" || match?.[2]) {
      // a disclosure lays out at once (nothing in one is a figure that waits for a redraw): measured as soon as it is open
      openParts(scope)
      overflowFindings(card, findings, scope)
      glossFindings(scope, findings)
    } else {
      // only the figures the student has on screen in this state: one in a hidden exercise is drawn in that exercise's state
      const figures = api.figures().filter((f) => scope.contains(f.element) && shown(f.element))
      if (figures.length === 0) overflowFindings(card, findings, scope)
      for (const figure of figures) {
        const total = figure.total ?? 1
        for (let i = 0; i < total; i++) {
          if (total > 1) figure.setState(i)
          await settle()
          figureFindings(figure.element, minPx, i, findings)
          overflowFindings(card, findings, scope)
        }
      }
    }
    if (!state) {
      katexFindings(card, findings) // a formula is drawn (or refused) when the card is built, shown or not: once is enough
      markupFindings(card, findings) // markup printed as text (D-310), likewise once
      states = statesOf(card)
    }
  } catch (error) {
    findings.push({ code: "E-LESSON-RENDER", message: `exception: ${String(error?.message ?? error).slice(0, 200)}`, where: "card" })
  }
  for (const message of errors.splice(0)) findings.push({ code: "E-LESSON-RENDER", message: `exception: ${message}`, where: "card" })
  const seen = new Set()
  const unique = findings.filter((f) => {
    const key = `${f.code}|${f.message}|${f.where}`
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
  return { n, state, findings: unique, height: document.documentElement.scrollHeight, states }
}

// "Stampa riassunto e schema" (A10): the summary card alone, as render.js prints it; the server's Chrome then counts the
// pages of the PDF (it runs under print media, set by the caller).
async function printSummary() {
  restore()
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
