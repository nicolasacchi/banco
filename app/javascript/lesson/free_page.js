// The parent side of a free page (D-290, SPEC B4, B5): what the lesson page accepts from the sandboxed frame, and the watchdog
// that takes a broken page away. Pure (no DOM): lesson/blocks/page.js wires it to the iframe, the tests drive it with fake timers.
//
// A message is accepted only if its source is the frame's own window (the origin of a sandboxed frame is the string "null", so the
// source is the check), data.bridge is "banco-page/1", the type is known, the JSON is at most 2 KB and the rate is at most 20 per
// second and 300 per load. Nothing a page sends changes a state, writes a practice row or reaches another student.
export const BRIDGE = "banco-page/1"
export const KNOWN = ["ready", "resize", "event", "error"]
export const EVENT_KINDS = ["interacted", "answered", "hint", "solution", "done"]
export const LIMITS = { maxBytes: 2048, perSecond: 20, perLoad: 300, rejectedMax: 50, loadMs: 30000, readyMs: 8000, heightMin: 160, heightMax: 2400, eventBytes: 1024 }

// A guard for one load of the frame: decide(event, frameWindow, now) -> { ok, message } or { ok: false, reason }.
export function makeGuard(limits = LIMITS) {
  let total = 0
  let rejected = 0
  let windowStart = 0
  let inWindow = 0
  const reject = (reason) => {
    rejected += 1
    return { ok: false, reason, rejected }
  }
  return {
    get rejected() { return rejected },
    get total() { return total },
    decide(event, frameWindow, now) {
      if (!frameWindow || event.source !== frameWindow) return { ok: false, reason: "source", rejected }
      const data = event.data
      if (!data || typeof data !== "object" || data.bridge !== BRIDGE || !KNOWN.includes(data.type)) return reject("shape")
      let size
      try { size = JSON.stringify(data).length } catch (_e) { return reject("json") }
      if (size > limits.maxBytes) return reject("size")
      if (now - windowStart >= 1000) { windowStart = now; inWindow = 0 }
      inWindow += 1
      if (inWindow > limits.perSecond) return reject("rate")
      total += 1
      if (total > limits.perLoad) return reject("load")
      if (data.type === "event" && !EVENT_KINDS.includes(data.kind)) return reject("kind")
      if (data.type === "event" && JSON.stringify(data.data ?? {}).length > limits.eventBytes) return reject("event_size")
      return { ok: true, message: data }
    }
  }
}

export function clampHeight(value, limits = LIMITS) {
  const n = Number(value)
  if (!Number.isFinite(n)) return limits.heightMin
  return Math.min(limits.heightMax, Math.max(limits.heightMin, Math.round(n)))
}

// The watchdog, timed so that a slow phone is not taken for a broken page: no `load` within 30 s of the click (the network), or no
// `ready` within 8 s of `load` (the page's start: module scripts have run by load), or more than one `load` (the frame navigated
// away), or more than 50 rejected messages. onFail(limit) is called once with load, ready, navigated or rejected.
export function makeWatchdog({ onFail, setTimer = setTimeout, clearTimer = clearTimeout, limits = LIMITS }) {
  let loads = 0
  let failed = false
  let stopped = false
  let timer = setTimer(() => fail("load"), limits.loadMs)
  function fail(limit) {
    if (failed || stopped) return
    failed = true
    clearTimer(timer)
    onFail(limit)
  }
  return {
    get failed() { return failed },
    loaded() {
      loads += 1
      if (loads > 1) return fail("navigated")
      clearTimer(timer)
      timer = setTimer(() => fail("ready"), limits.readyMs)
    },
    // the page started: the timers are done, but a second load or a flood of rejected messages still fails it
    ready() {
      if (failed) return
      clearTimer(timer)
    },
    rejected(count) { if (count > limits.rejectedMax) fail("rejected") },
    stop() { stopped = true; clearTimer(timer) }
  }
}

// What the lesson page tells the frame at ready: the seed (one of eight, chosen by the server), the level, the preferences.
export function initMessage({ seed, theme, size, reduced, visible }) {
  return { bridge: BRIDGE, type: "init", seed, level: 1, theme: theme === "dark" ? "dark" : "cream", size: size || "normal", reduced_motion: !!reduced, visible: visible !== false }
}
