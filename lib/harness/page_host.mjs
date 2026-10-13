// The host page of a page validation (D-290, SPEC B7): it embeds the page's shell with the production iframe attributes and plays
// the parent side of the bridge (banco-page/1), logging everything the page says. The runner (Ruby, Chrome) reads this object.
// Served by the harness listener with a run token; no connection of any kind; the frame source is fixed by the server.
const BRIDGE = "banco-page/1"
const KNOWN = ["ready", "resize", "event", "error", "audit-result"]
const params = new URLSearchParams(location.search)
const stage = document.getElementById("stage")

const log = { messages: [], errors: [], events: [], rejected: 0, loads: 0, readyAt: null, startedAt: null, height: 0, ready: false }
const waiting = new Map()
let counter = 0
let iframe = null

function now() { return performance.now() }

function post(message) {
  if (iframe && iframe.contentWindow) iframe.contentWindow.postMessage({ bridge: BRIDGE, ...message }, "*")
}

function init() {
  post({ type: "init", seed: Number(params.get("seed")) >>> 0, level: Number(params.get("level") || 1), theme: params.get("theme") === "dark" ? "dark" : "cream",
         size: "normal", reduced_motion: params.get("reduced") === "1", visible: true })
}

let readyResolve
const readyPromise = new Promise((resolve) => { readyResolve = resolve })

window.addEventListener("message", (event) => {
  const data = event.data
  if (!iframe || event.source !== iframe.contentWindow) return
  if (!data || data.bridge !== BRIDGE || !KNOWN.includes(data.type)) { log.rejected += 1; return }
  if (JSON.stringify(data).length > 2048 && data.type !== "audit-result") { log.rejected += 1; return }
  if (data.type === "audit-result") {
    const done = waiting.get(data.id)
    if (done) { waiting.delete(data.id); done(data) }
    return
  }
  if (log.messages.length < 3000) log.messages.push({ t: Math.round(now() - log.startedAt), type: data.type })
  if (data.type === "ready" && !log.ready) {
    log.ready = true
    log.readyAt = Math.round(now() - log.startedAt)
    log.height = data.height
    init()
    readyResolve({ ok: true, ms: log.readyAt })
  } else if (data.type === "resize") {
    const height = Math.min(2400, Math.max(160, Number(data.height) || 160))
    log.height = height
    iframe.style.height = `${height}px`
  } else if (data.type === "event") {
    if (log.events.length < 500) log.events.push({ kind: data.kind, data: data.data })
  } else if (data.type === "error") {
    if (log.errors.length < 200) log.errors.push(String(data.message).slice(0, 300))
  }
})

function mount() {
  iframe = document.createElement("iframe")
  iframe.setAttribute("sandbox", "allow-scripts")
  iframe.setAttribute("credentialless", "")
  iframe.setAttribute("referrerpolicy", "no-referrer")
  iframe.setAttribute("loading", "eager")
  iframe.setAttribute("title", "page")
  iframe.style.cssText = `border:0;display:block;width:${params.get("width") || "100%"};height:${stage.dataset.minHeight || 320}px`
  iframe.addEventListener("load", () => { log.loads += 1 })
  log.startedAt = now()
  iframe.src = stage.dataset.src
  stage.appendChild(iframe)
}

window.bancoPageHost = {
  log,
  // Resolves {ok, ms} at ready, or {ok: false} after `ms` milliseconds.
  ready(ms) {
    return Promise.race([readyPromise, new Promise((resolve) => setTimeout(() => resolve({ ok: false }), ms))])
  },
  rect() {
    const r = iframe.getBoundingClientRect()
    return { x: r.x, y: r.y, width: r.width, height: r.height }
  },
  setPrefs(prefs) { post({ type: "prefs", ...prefs }) },
  setVisible(visible) { post({ type: "visibility", visible }) },
  resizeFrame(width) { iframe.style.width = `${width}px` },
  focusFrame() { iframe.focus() },
  // Asks audit.mjs (validation mount only) and waits for its answer.
  audit(what, arg, ms = 8000) {
    counter += 1
    const id = counter
    return new Promise((resolve) => {
      const timer = setTimeout(() => { waiting.delete(id); resolve({ ok: false, timeout: true }) }, ms)
      waiting.set(id, (data) => { clearTimeout(timer); resolve(data) })
      post({ type: "audit", id, what, arg })
    })
  },
  state() {
    return { ready: log.ready, readyAt: log.readyAt, loads: log.loads, errors: log.errors.slice(), events: log.events.length, rejected: log.rejected, height: log.height,
             messages: log.messages.length }
  }
}

mount()
