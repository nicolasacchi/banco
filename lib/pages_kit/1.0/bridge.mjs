// banco-page kit 1.0: the bridge, version 1 (SPEC B5, B6). The one door of a free page to the lesson around it.
// A page imports { banco } from "banco" and never touches window.parent: the scan refuses that.
import { makeRng } from "./rng.mjs"

const BRIDGE = "banco-page/1"
const KINDS = ["interacted", "answered", "hint", "solution", "done"]

let init = null
let initPromise = null
let rng = null
let startedAt = 0
let visible = true
let loops = []
let fallbackShown = false
const handlers = { prefs: [], visibility: [] }

function post(message) {
  window.parent.postMessage({ bridge: BRIDGE, ...message }, "*")
}

function height() {
  const body = document.body
  return Math.ceil(Math.max(body ? body.scrollHeight : 0, document.documentElement ? document.documentElement.scrollHeight : 0))
}

function apply(prefs) {
  const root = document.documentElement
  if (prefs.theme) root.setAttribute("data-theme", prefs.theme === "dark" ? "dark" : "cream")
  if (prefs.size) root.setAttribute("data-size", prefs.size)
  if (prefs.reduced_motion !== undefined) root.setAttribute("data-reduced-motion", prefs.reduced_motion ? "true" : "false")
}

window.addEventListener("message", (event) => {
  const data = event.data
  if (event.source !== window.parent || !data || data.bridge !== BRIDGE) return
  if (data.type === "init" && !init) {
    init = { seed: data.seed >>> 0, level: Math.min(3, Math.max(1, Number(data.level) || 1)), theme: data.theme === "dark" ? "dark" : "cream", size: data.size || "normal",
             reducedMotion: !!data.reduced_motion }
    visible = data.visible !== false
    rng = makeRng(init.seed)
    startedAt = performance.now()
    apply({ theme: init.theme, size: init.size, reduced_motion: init.reducedMotion })
    resolveInit(init)
  } else if (data.type === "prefs" && init) {
    if (data.theme) init.theme = data.theme === "dark" ? "dark" : "cream"
    if (data.size) init.size = data.size
    if (data.reduced_motion !== undefined) init.reducedMotion = !!data.reduced_motion
    apply(data)
    handlers.prefs.forEach((fn) => fn({ ...init }))
  } else if (data.type === "visibility") {
    visible = !!data.visible
    handlers.visibility.forEach((fn) => fn(visible))
    if (visible) loops.forEach((l) => l.wake())
  }
})

let resolveInit = () => {}

function requireInit(name) {
  if (!init) throw new Error(`banco.${name}() before banco.init()`)
}

// Sizes the frame on its own whenever the body changes.
let lastHeight = 0
function reportHeight() {
  const h = height()
  if (h === lastHeight) return
  lastHeight = h
  post({ type: "resize", height: h })
}
if (typeof ResizeObserver === "function") new ResizeObserver(reportHeight).observe(document.body)

export const banco = {
  // Tells the parent the page has started and waits for the seed, the level and the preferences.
  init() {
    if (!initPromise) {
      initPromise = new Promise((resolve) => { resolveInit = resolve })
      post({ type: "ready", height: height() })
    }
    return initPromise
  },

  // The seeded generator: the same code as the generators of the items (lib/harness/rng.mjs).
  random() {
    requireInit("random")
    return rng.next()
  },
  rng() {
    requireInit("rng")
    return rng
  },

  // Milliseconds since init, monotonic: the only clock a page has.
  now() {
    requireInit("now")
    return performance.now() - startedAt
  },

  // The content is drawn: tell the parent its height.
  ready() {
    lastHeight = 0
    reportHeight()
  },
  resize() {
    lastHeight = 0
    reportHeight()
  },

  event(kind, data = {}) {
    if (!KINDS.includes(kind)) throw new Error(`banco.event: kind must be one of ${KINDS.join(", ")}`)
    let text = JSON.stringify(data)
    if (text.length > 1000) text = "{}"
    post({ type: "event", kind, data: JSON.parse(text) })
  },

  onPrefs(fn) { handlers.prefs.push(fn) },
  onVisibility(fn) { handlers.visibility.push(fn) },
  get visible() { return visible },

  // A feature test for WebGL (validation stubs getContext to null to see what the page does).
  webgl() {
    try {
      const canvas = document.createElement("canvas")
      return !!(canvas.getContext("webgl2") || canvas.getContext("webgl"))
    } catch (_e) {
      return false
    }
  },

  // Shows the text for a browser that cannot run the page (the manifest's fallback_it, put in the shell).
  fallback() {
    if (fallbackShown) return
    fallbackShown = true
    const app = document.getElementById("app")
    const text = (app && app.getAttribute("data-fallback-it")) || ""
    if (app) {
      while (app.firstChild) app.removeChild(app.firstChild)
      const box = document.createElement("p")
      box.className = "banco-fallback"
      box.setAttribute("role", "status")
      box.textContent = text
      app.appendChild(box)
    }
    post({ type: "event", kind: "interacted", data: { fallback: true } })
    banco.resize()
  },

  // A requestAnimationFrame loop that stops when the page is not visible, runs one frame under reduced motion,
  // and rests when fn returns false (render on demand: call wake() after the next change). fn gets banco.now().
  loop(fn) {
    requireInit("loop")
    let running = false
    let frame = 0
    const step = () => {
      frame = 0
      running = false
      if (!visible) return
      const again = fn(banco.now())
      if (again === false || init.reducedMotion) return
      running = true
      frame = window.requestAnimationFrame(step)
    }
    const handle = {
      wake() {
        if (running || !visible) return
        running = true
        frame = window.requestAnimationFrame(step)
      },
      stop() {
        if (frame) window.cancelAnimationFrame(frame)
        frame = 0
        running = false
        loops = loops.filter((l) => l !== handle)
      }
    }
    loops.push(handle)
    handle.wake()
    return handle
  }
}
