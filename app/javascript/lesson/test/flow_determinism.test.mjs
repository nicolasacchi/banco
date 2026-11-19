// D-383, after the first real lesson: the same Do While was drawn as a centred tree in one render check and as the indented layout in the next, on
// the same code, the same width and the same size; and the indented layout, when it drew it, led a reader from the loop's body to its exit.
// 1. The choice between the layouts is a pure function of (data, width, size, measure) and a knife edge in the measure: a text 3 % wider (the
//    fallback face before the web font has loaded) moves the width where the tree stops fitting by some 10 px. So a figure must measure with the
//    real face: it forgets what it measured and lays out again when the faces load (fonts.js, makeMeasure.reset, draw.js).
// 2. The indented layout draws every branch of a decision as an arrow of its own.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { audit, indented } from "./flow_audit.mjs"

const { layout } = await import("lesson/diagrams/flow")
const { estimate } = await import("lesson/diagrams/common")
const { onFontsLoaded } = await import("lesson/diagrams/fonts")
const { makeMeasure } = await import("lesson/diagrams/draw")

const vectors = JSON.parse(readFileSync(new URL("../../../../test/fixtures/diagrams/vectors.json", import.meta.url), "utf8")).vectors
const vector = (name) => vectors.find((v) => v.name === name).data
const doWhile = vector("flow-loop-do-while")

// a face k times as wide as the estimate's
const face = (k) => (text, px, maxW) => {
  const m = estimate(text, px, maxW && maxW / k)
  return { w: Math.ceil(m.w * k), h: m.h }
}
const draw = (data, width, k, fontPx = 20) => layout(data, { width, fontPx, subject: "math", measure: face(k) })

test("the same data, width, size and face always give the same scene", () => {
  for (const name of ["flow-loop-do-while", "flow-loop-do-while-indented", "flow-loop-nested-two"]) {
    for (const width of [320, 390, 1280]) {
      assert.deepEqual(draw(vector(name), width, 1), draw(vector(name), width, 1), `${name} ${width}`)
    }
  }
})

test("a face a few per cent wider moves the width where the Do While stops fitting the centred tree: why the figure must measure the real face", () => {
  const edge = (k) => {
    for (let width = 260; width <= 400; width += 1) if (!indented(draw(doWhile, width, k))) return width
    return Infinity
  }
  const [real, fallback] = [edge(1), edge(1.06)]
  assert.ok(fallback - real >= 6, `the edge moves from ${real} to ${fallback}`)
  // between the two edges the two faces draw two layouts of the same Do While
  const between = Math.floor((real + fallback) / 2)
  assert.equal(indented(draw(doWhile, between, 1)), false)
  assert.equal(indented(draw(doWhile, between, 1.06)), true)
})

test("fonts.js: the figure is told when the faces load, once if they were loading, and stops when asked", async () => {
  const listeners = new Map()
  let release
  const fonts = {
    status: "loading",
    ready: new Promise((resolve) => { release = resolve }),
    addEventListener: (type, fn) => listeners.set(type, fn),
    removeEventListener: (type) => listeners.delete(type)
  }
  let calls = 0
  const stop = onFontsLoaded(() => { calls += 1 }, fonts)
  listeners.get("loadingdone")()
  assert.equal(calls, 1, "a batch of faces loaded")
  release()
  await fonts.ready
  await Promise.resolve()
  assert.equal(calls, 2, "the faces that were loading at the call are done")
  stop()
  assert.equal(listeners.size, 0)
  const loaded = { status: "loaded", ready: Promise.resolve(), addEventListener() {}, removeEventListener() {} }
  let never = 0
  onFontsLoaded(() => { never += 1 }, loaded)
  await loaded.ready
  assert.equal(never, 0, "faces already there: nothing to wait for")
  assert.equal(typeof onFontsLoaded(() => {}, undefined), "function", "no font set: a no-op")
})

// the measuring probe, on a stand-in DOM whose boxes have the width of the face now in use
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
  getBoundingClientRect() { return { width: Fake.width, height: 20 } }
  appendChild(child) {
    if (child instanceof Fake && child.tag === "#fragment") { for (const c of child.children) this.appendChild(c); child.children = []; return child }
    this.children.push(child)
    return child
  }
  append(...nodes) { for (const node of nodes) this.appendChild(node) }
}

test("the measure forgets what it measured in the face before: reset() after the faces loaded", () => {
  globalThis.document = { createElement: (tag) => new Fake(tag), createElementNS: (_n, tag) => new Fake(tag), createDocumentFragment: () => new Fake("#fragment"), createTextNode: (text) => ({ nodeType: 3, textContent: String(text) }) }
  globalThis.window = {}
  try {
    const m = makeMeasure(new Fake("div"), { subject: "math", t: {} })
    Fake.width = 100
    assert.equal(m.measure("torna alla domanda", 20).w, 100)
    Fake.width = 106 // the real face has loaded
    assert.equal(m.measure("torna alla domanda", 20).w, 100, "cached: the figure would keep the fallback face's layout")
    m.reset()
    assert.equal(m.measure("torna alla domanda", 20).w, 106)
  } finally {
    delete globalThis.document
    delete globalThis.window
  }
})

// ---- the indented layout, branch by branch -----------------------------------------------------------------------------------------------------

const indentedDoWhile = layout(vector("flow-loop-do-while-indented"), { width: 390, fontPx: 20, subject: "math" })
const nodeOf = (scene, text) => {
  const l = scene.labels.find((x) => x.text_it === text)
  const boxes = scene.shapes.filter((s) => /\bdg-node\b/.test(s.cls ?? "")).map((s) => (s.kind === "rect" ? { kind: "rect", x: s.x, y: s.y, w: s.w, h: s.h } : (() => {
    const xs = s.points.map((p) => p[0])
    const ys = s.points.map((p) => p[1])
    return { kind: "rhombus", x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) }
  })()))
  const n = boxes.find((b) => l.x >= b.x && l.x + l.w <= b.x + b.w && l.y >= b.y && l.y + l.h <= b.y + b.h)
  return { ...n, cx: n.x + n.w / 2, cy: n.y + n.h / 2 }
}
test("the indented Do While: the Do While vector is drawn indented at 390, and soundly", () => {
  assert.ok(indented(indentedDoWhile))
  assert.deepEqual(audit(indentedDoWhile), [])
})

// the drawn edges (lines and branch paths, not the loop) as chains of segments, and which of them touch: the connected pieces of the drawing
function pieces(scene) {
  const shapes = scene.shapes.filter((s) => (s.kind === "line" && /dg-edge/.test(s.cls)) || (s.kind === "path" && /dg-branch/.test(s.cls)))
  const segs = shapes.map((s) => {
    if (s.kind === "line") return [{ x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2 }]
    const nums = [...s.d.matchAll(/([MVH])(-?[\d.]+)(?:,(-?[\d.]+))?/g)]
    let [x, y] = [0, 0]
    const out = []
    for (const [, op, a, b] of nums) {
      const [nx, ny] = op === "M" ? [+a, +b] : op === "V" ? [x, +a] : [+a, y]
      if (op !== "M") out.push({ x1: x, y1: y, x2: nx, y2: ny })
      ;[x, y] = [nx, ny]
    }
    return out
  })
  const touch = (p, q) => Math.min(p.x1, p.x2) <= Math.max(q.x1, q.x2) + 0.5 && Math.min(q.x1, q.x2) <= Math.max(p.x1, p.x2) + 0.5 && Math.min(p.y1, p.y2) <= Math.max(q.y1, q.y2) + 0.5 && Math.min(q.y1, q.y2) <= Math.max(p.y1, p.y2) + 0.5
  const group = shapes.map((_, i) => i)
  const find = (i) => (group[i] === i ? i : (group[i] = find(group[i])))
  for (let i = 0; i < shapes.length; i++) for (let j = i + 1; j < shapes.length; j++) if (segs[i].some((p) => segs[j].some((q) => touch(p, q)))) group[find(i)] = find(j)
  return { shapes, segs, of: (i) => find(i) }
}
// the piece that ends in an arrowhead at (x, y)
const reaching = (scene, x, y) => {
  const p = pieces(scene)
  const i = p.segs.findIndex((list) => list.some((s) => Math.abs(s.x2 - (x - 8)) < 1.5 && Math.abs(s.y2 - y) < 1.5))
  return { ...p, index: i }
}

test("the indented Do While: no drawn segment connects the body to the exit", () => {
  const body = nodeOf(indentedDoWhile, "Aggiungi il versamento al totale")
  const exit = nodeOf(indentedDoWhile, "Scrivi il totale finale")
  const toBody = reaching(indentedDoWhile, body.x, body.cy)
  const toExit = reaching(indentedDoWhile, exit.x, exit.cy)
  assert.ok(toBody.index >= 0 && toExit.index >= 0, "each has its own arrow")
  assert.notEqual(toBody.index, toExit.index)
  assert.notEqual(toBody.of(toBody.index), toBody.of(toExit.index), "the line into the body and the line into the exit never touch: one rail would join them")
  // nothing leaves the bottom of the body
  for (const list of toBody.segs) for (const sg of list) assert.ok(!(sg.x1 === sg.x2 && Math.abs(Math.min(sg.y1, sg.y2) - (body.y + body.h)) < 1 && sg.x1 > body.x && sg.x1 < body.x + body.w), "nothing leaves the bottom of the body")
  // and the old drawing joined them: a single trunk line runs from the decision down past the body to the exit
  const trunkLike = indentedDoWhile.shapes.filter((s) => s.kind === "line" && s.x1 === s.x2 && Math.min(s.y1, s.y2) <= body.cy && Math.max(s.y1, s.y2) >= exit.cy)
  assert.equal(trunkLike.length, 0, "no line runs from the body's row to the exit's row")
})

test("the indented Do While: each branch leaves the decision with an arrowhead into its first node; the way in is an arrow of its own", () => {
  const q = nodeOf(indentedDoWhile, "Il totale è sotto cento?")
  const start = nodeOf(indentedDoWhile, "Il totale parte da zero")
  const body = nodeOf(indentedDoWhile, "Aggiungi il versamento al totale")
  const exit = nodeOf(indentedDoWhile, "Scrivi il totale finale")
  const tips = indentedDoWhile.shapes.filter((s) => s.cls === "dg-arrowhead").map((s) => s.points[2])
  const has = (x, y) => tips.some(([tx, ty]) => Math.abs(tx - x) < 1 && Math.abs(ty - y) < 1)
  assert.ok(has(body.x, body.cy), "an arrowhead into the body")
  assert.ok(has(exit.x, exit.cy), "an arrowhead into the exit")
  assert.ok(has(q.cx, q.y), "an arrowhead into the top vertex of the decision")
  const branches = indentedDoWhile.shapes.filter((s) => s.kind === "path" && /dg-branch/.test(s.cls))
  assert.equal(branches.length, 3, "the way into the decision and one path per branch")
  const parse = (s) => s.d.match(/^M(-?[\d.]+),(-?[\d.]+) V(-?[\d.]+) H(-?[\d.]+)$/)
  const rails = branches.map(parse).filter(Boolean).map((m) => ({ rx: +m[1], y0: +m[2], cy: +m[3], tip: +m[4] }))
  const toBody = rails.find((r) => Math.abs(r.cy - body.cy) < 1)
  const toExit = rails.find((r) => Math.abs(r.cy - exit.cy) < 1)
  // each leaves the lower left side of the rhombus: its start is on the rhombus, at the rail's x
  for (const r of [toBody, toExit]) {
    const onEdge = q.cy + ((r.rx - q.x) * q.h) / q.w
    assert.ok(Math.abs(r.y0 - onEdge) < 1, "the rail starts on the rhombus")
    assert.ok(r.rx > q.x && r.rx < q.cx)
  }
  assert.notEqual(toBody.rx, toExit.rx, "two rails, not one shared")
  // the way in comes from the start box and ends on the top vertex
  assert.ok(start.y + start.h < q.y)
  // «Sì» and «No» sit on their own branch: right of their own rail, above their own first node
  const label = (t) => indentedDoWhile.labels.find((l) => l.text_it === t)
  assert.ok(label("Sì").x > toBody.rx && label("Sì").y + label("Sì").h <= body.y + 1)
  assert.ok(label("No").x > toExit.rx && label("No").y + label("No").h <= exit.y + 1)
  assert.ok(label("Sì").y < body.y && label("No").y > body.y + body.h, "each above its own node")
})

test("every indented layout of the vectors with a decision draws arrows of their own, whatever the width", () => {
  for (const name of ["flow-loop-do-while-indented", "flow-loop-nested-two", "flow-loop-long-question", "flow-decisions"]) {
    for (const width of [320, 390]) {
      const scene = layout(vector(name), { width, fontPx: 20, subject: "math" })
      assert.ok(!scene.error, scene.error?.message)
      if (!indented(scene)) continue
      assert.deepEqual(audit(scene), [], `${name} ${width}`)
      const decisions = scene.shapes.filter((s) => s.kind === "polygon" && /dg-decision/.test(s.cls)).length
      const branchPaths = scene.shapes.filter((s) => s.kind === "path" && /dg-branch/.test(s.cls)).length
      assert.ok(branchPaths >= decisions * 2, `${name} ${width}: at least two branches per decision`)
    }
  }
})
