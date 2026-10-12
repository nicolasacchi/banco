// The audit of a free page in validation (D-281, SPEC B7): served on the validation mount only, loaded between the kit's boot and the
// page's main module. It counts frames, long tasks and heap, runs axe, lists the controls, and answers the host page by postMessage.
// `?nowebgl=1` in the shell address makes getContext refuse WebGL before the page runs (the fallback check).
const BRIDGE = "banco-page/1"
const stats = { frames: 0, longtasks: [], initAt: null }

if (new URLSearchParams(location.search).get("nowebgl") === "1") {
  const real = HTMLCanvasElement.prototype.getContext
  HTMLCanvasElement.prototype.getContext = function getContext(kind, ...rest) {
    if (kind === "webgl" || kind === "webgl2" || kind === "experimental-webgl") return null
    return real.call(this, kind, ...rest)
  }
}

const raf = window.requestAnimationFrame.bind(window)
window.requestAnimationFrame = (callback) => raf((t) => { stats.frames += 1; callback(t) })

try {
  new PerformanceObserver((list) => {
    for (const entry of list.getEntries()) stats.longtasks.push({ start: Math.round(entry.startTime), ms: Math.round(entry.duration) })
  }).observe({ type: "longtask", buffered: true })
} catch (_e) { /* the browser has no long task entries */ }

window.addEventListener("message", (event) => {
  const d = event.data
  if (event.source !== window.parent || !d || d.bridge !== BRIDGE) return
  if (d.type === "init" && stats.initAt === null) stats.initAt = performance.now()
  if (d.type === "audit") answer(d)
})

const FOCUSABLE = 'a[href], button, input, select, textarea, summary, [tabindex], [contenteditable="true"]'
const controls = []

function visible(el) {
  const r = el.getBoundingClientRect()
  const style = getComputedStyle(el)
  return r.width > 0 && r.height > 0 && style.visibility !== "hidden" && style.display !== "none"
}

function nameOf(el) {
  const label = el.getAttribute("aria-label")
  if (label) return label.trim()
  const by = el.getAttribute("aria-labelledby")
  if (by) return by.split(/\s+/).map((id) => (document.getElementById(id) || {}).textContent || "").join(" ").trim()
  if (el.labels && el.labels.length) return Array.from(el.labels).map((l) => l.textContent).join(" ").trim()
  const title = el.getAttribute("title")
  return ((el.textContent || "").trim() || (title || "").trim() || el.getAttribute("alt") || "").trim()
}

function describe(el, index) {
  const r = el.getBoundingClientRect()
  const type = el.getAttribute("type") || ""
  return { index, tag: el.tagName.toLowerCase(), type, role: el.getAttribute("role") || "", name: nameOf(el), disabled: !!el.disabled,
           rect: { x: r.x, y: r.y, width: r.width, height: r.height } }
}

function list() {
  controls.length = 0
  for (const el of document.querySelectorAll(FOCUSABLE)) {
    if (el.disabled || el.getAttribute("tabindex") === "-1" || !visible(el)) continue
    controls.push(el)
  }
  return controls.map((el, i) => describe(el, i))
}

function focusRing(el) {
  const s = getComputedStyle(el)
  const outline = s.outlineStyle !== "none" && parseFloat(s.outlineWidth) > 0
  const shadow = s.boxShadow && s.boxShadow !== "none"
  return outline || !!shadow
}

async function answer(d) {
  let result = {}
  try {
    switch (d.what) {
      case "axe": {
        const run = await window.axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"] }, resultTypes: ["violations"], preload: false })
        result = { violations: run.violations.map((v) => ({ id: v.id, impact: v.impact, help: v.help, nodes: v.nodes.length, target: v.nodes[0] && v.nodes[0].target && String(v.nodes[0].target[0]).slice(0, 80) })) }
        break
      }
      case "controls": {
        const canvases = Array.from(document.querySelectorAll("canvas")).map((c) => {
          const r = c.getBoundingClientRect()
          const alt = c.getAttribute("aria-label") || c.getAttribute("role") === "img" || (c.textContent || "").trim() !== "" || c.hasAttribute("aria-labelledby")
          return { rect: { x: r.x, y: r.y, width: r.width, height: r.height }, text_alternative: !!alt }
        })
        result = { controls: list(), canvases }
        break
      }
      case "focus": {
        const el = controls[d.arg]
        if (el) el.focus()
        result = { focused: document.activeElement === el }
        break
      }
      case "active": {
        const el = document.activeElement
        const index = controls.indexOf(el)
        result = el && el !== document.body ? { index, tag: el.tagName.toLowerCase(), name: nameOf(el), ring: focusRing(el) } : { index: -1 }
        break
      }
      case "resources":
        result = { urls: performance.getEntriesByType("resource").map((e) => e.name) }
        break
      case "frames": result = { frames: stats.frames, now: performance.now() }; break
      case "longtasks": result = { tasks: stats.longtasks, initAt: stats.initAt }; break
      case "heap": result = { bytes: performance.memory ? performance.memory.usedJSHeapSize : null }; break
      case "text": result = { text: document.body.innerText.slice(0, 2000) }; break
      case "width": result = { scrollWidth: document.documentElement.scrollWidth, innerWidth: window.innerWidth }; break
      default: result = { error: "unknown audit" }
    }
  } catch (e) {
    result = { error: String(e && e.message || e).slice(0, 200) }
  }
  window.parent.postMessage({ bridge: BRIDGE, type: "audit-result", id: d.id, what: d.what, ...result }, "*")
}
