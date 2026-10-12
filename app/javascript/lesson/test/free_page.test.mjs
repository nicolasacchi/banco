import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"

const { makeGuard, makeWatchdog, clampHeight, initMessage, BRIDGE, LIMITS } = await import("lesson/free_page")

const frame = { id: "frame" }
const message = (data, source = frame) => ({ source, data: { bridge: BRIDGE, ...data } })

test("the guard accepts only the frame's own, well formed, known messages", () => {
  const guard = makeGuard()
  assert.equal(guard.decide(message({ type: "ready", height: 300 }), frame, 0).ok, true)
  assert.equal(guard.decide(message({ type: "ready" }, { id: "other" }), frame, 0).reason, "source")
  assert.equal(guard.decide(message({ type: "ready" }, null), frame, 0).reason, "source")
  assert.equal(guard.decide({ source: frame, data: { type: "ready" } }, frame, 0).reason, "shape")
  assert.equal(guard.decide({ source: frame, data: "ready" }, frame, 0).reason, "shape")
  assert.equal(guard.decide(message({ type: "navigate" }), frame, 0).reason, "shape")
  assert.equal(guard.decide(message({ type: "error", message: "x".repeat(2100) }), frame, 0).reason, "size")
  assert.equal(guard.decide(message({ type: "event", kind: "won" }), frame, 0).reason, "kind")
  assert.equal(guard.decide(message({ type: "event", kind: "done", data: { text: "x".repeat(1100) } }), frame, 0).reason, "event_size")
  assert.equal(guard.decide(message({ type: "event", kind: "interacted", data: { a: 1 } }), frame, 0).ok, true)
  assert.equal(guard.rejected, 6, "a message from another source is not counted: it is not the page's")
})

test("the guard limits the rate to 20 a second and 300 a load", () => {
  const guard = makeGuard()
  let accepted = 0
  for (let i = 0; i < 40; i++) if (guard.decide(message({ type: "resize", height: 200 }), frame, 100).ok) accepted += 1
  assert.equal(accepted, LIMITS.perSecond)
  assert.equal(guard.rejected, 20)
  assert.equal(guard.decide(message({ type: "resize", height: 200 }), frame, 1200).ok, true, "a new second")
  const load = makeGuard()
  let total = 0
  for (let t = 0; t < 400; t++) for (let i = 0; i < 1; i++) if (load.decide(message({ type: "resize", height: 200 }), frame, t * 1000).ok) total += 1
  assert.equal(total, LIMITS.perLoad)
})

test("heights are clamped to 160 to 2400", () => {
  assert.equal(clampHeight(10), 160)
  assert.equal(clampHeight(99999), 2400)
  assert.equal(clampHeight(321.4), 321)
  assert.equal(clampHeight("x"), 160)
  assert.equal(clampHeight(undefined), 160)
})

function timers() {
  const pending = []
  return {
    setTimer: (fn, ms) => { const t = { fn, ms, live: true }; pending.push(t); return t },
    clearTimer: (t) => { if (t) t.live = false },
    fire: (ms) => pending.filter((t) => t.live && t.ms === ms).forEach((t) => { t.live = false; t.fn() }),
    live: () => pending.filter((t) => t.live).map((t) => t.ms)
  }
}

test("the watchdog: no load within 30 s, no ready within 8 s of load, a second load, a flood of rejected messages", () => {
  const cases = [
    ["load", (dog, clock) => clock.fire(LIMITS.loadMs)],
    ["ready", (dog, clock) => { dog.loaded(); clock.fire(LIMITS.readyMs) }],
    ["navigated", (dog) => { dog.loaded(); dog.ready(); dog.loaded() }],
    ["rejected", (dog) => { dog.loaded(); dog.ready(); dog.rejected(LIMITS.rejectedMax + 1) }]
  ]
  for (const [limit, act] of cases) {
    const clock = timers()
    const failed = []
    const dog = makeWatchdog({ onFail: (l) => failed.push(l), setTimer: clock.setTimer, clearTimer: clock.clearTimer })
    act(dog, clock)
    assert.deepEqual(failed, [ limit ], limit)
    dog.loaded()
    clock.fire(LIMITS.readyMs)
    assert.deepEqual(failed, [ limit ], `${limit}: it fails once`)
  }
})

test("a page that starts in time is left alone; the timers stop at ready and at stop()", () => {
  const clock = timers()
  const failed = []
  const dog = makeWatchdog({ onFail: (l) => failed.push(l), setTimer: clock.setTimer, clearTimer: clock.clearTimer })
  assert.deepEqual(clock.live(), [ LIMITS.loadMs ])
  dog.loaded()
  assert.deepEqual(clock.live(), [ LIMITS.readyMs ], "the load timer is replaced by the ready timer")
  dog.ready()
  assert.deepEqual(clock.live(), [])
  dog.rejected(LIMITS.rejectedMax)
  assert.deepEqual(failed, [])
  dog.stop()
  dog.loaded()
  assert.deepEqual(failed, [], "a stopped watchdog never fails")
})

test("init carries the seed, the level and the preferences, and nothing about the student", () => {
  const m = initMessage({ seed: 314159265, theme: "dark", size: "large", reduced: 1, visible: true })
  assert.deepEqual(Object.keys(m).sort(), ["bridge", "level", "reduced_motion", "seed", "size", "theme", "type", "visible"])
  assert.equal(m.theme, "dark")
  assert.equal(m.reduced_motion, true)
  assert.equal(initMessage({ seed: 1, theme: "weird" }).theme, "cream")
})
