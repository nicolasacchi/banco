// The graph router (WAVE2 2.1, T4b): fixed positions per layout, routes with arrowheads, the FLIP sets and the phone's list of moves.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { LAYOUTS, place, route, flip, moveList } = await import("lesson/diagrams/graph/router")

const node = (id, w = 120, h = 44, extra = {}) => ({ id, w, h, ...extra })
const ids = (n) => Array.from({ length: n }, (_, i) => `n${i}`)
const nodesOf = (n) => ids(n).map((id) => node(id))
const overlap = (a, b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h

const CASES = [
  ["pair", 2, {}], ["row", 5, {}], ["triangle", 3, {}], ["hub", 6, { centre: "n0" }], ["fan", 5, { into: "n4" }], ["grid", 4, {}], ["ring", 6, {}], ["line", 6, {}], ["tree", 4, {}]
]

test("every layout places every node inside the width, none over another, at 390 and 768 px", () => {
  for (const [layout, n, options] of CASES) {
    assert.ok(LAYOUTS.includes(layout))
    for (const width of [390, 768, 1100]) {
      const boxes = place(layout, nodesOf(n), { width, narrow: width < 600 }, options)
      assert.equal(boxes.size, n, layout)
      const list = [...boxes.values()]
      for (const b of list) assert.ok(b.x >= 0 && b.x + b.w <= width + 0.5, `${layout}/${width}: inside the width`)
      list.forEach((a, i) => list.slice(i + 1).forEach((b) => assert.ok(!overlap(a, b), `${layout}/${width}: no overlap`)))
    }
  }
})

test("the placement is the same every time (no force layout) and a narrow box stacks the nodes", () => {
  const a = place("hub", nodesOf(6), { width: 700 }, { centre: "n0" })
  const b = place("hub", nodesOf(6), { width: 700 }, { centre: "n0" })
  assert.deepEqual([...a], [...b])
  const stacked = place("triangle", nodesOf(3), { width: 360, narrow: true }, {})
  const ys = [...stacked.values()].map((r) => r.y)
  assert.deepEqual(ys, [...ys].sort((p, q) => p - q))
  assert.equal(new Set([...stacked.values()].map((r) => r.x)).size, 1)
})

test("a hub keeps its centre in the middle; a fan puts the target on the right, level with the middle of the sources", () => {
  const hub = place("hub", nodesOf(5), { width: 800 }, { centre: "n2" })
  const c = hub.get("n2")
  assert.equal(Math.round(c.x + c.w / 2), 400)
  const fan = place("fan", nodesOf(4), { width: 600 }, { into: "n3" })
  assert.ok(fan.get("n3").x > fan.get("n0").x + 200)
})

test("a line runs its stations in order and hangs lane 1 under the stretch of the branch", () => {
  const nodes = [...nodesOf(5), node("b1", 100, 44, { lane: 1 })]
  const boxes = place("line", nodes, { width: 900 }, { branch: { from: "n1", to: "n3" } })
  const xs = ids(5).map((id) => boxes.get(id).x)
  assert.deepEqual(xs, [...xs].sort((p, q) => p - q))
  const lane = boxes.get("b1")
  assert.ok(lane.y > boxes.get("n1").y + 44)
  assert.ok(lane.x + lane.w / 2 > boxes.get("n1").x && lane.x + lane.w / 2 < boxes.get("n3").x + 120)
  const narrow = place("line", nodes, { width: 360, narrow: true }, { branch: { from: "n1", to: "n3" } })
  assert.ok(narrow.get("b1").y > narrow.get("n1").y && narrow.get("b1").y < narrow.get("n2").y)
  assert.ok(narrow.get("b1").x > narrow.get("n1").x)
})

test("a route leaves one box and arrives at the other with the arrow pointing at it; opposite edges run side by side", () => {
  const boxes = place("pair", nodesOf(2), { width: 600 }, {})
  const [go, back] = route(boxes, [{ id: "e1", from: "n0", to: "n1", label: "x" }, { id: "e2", from: "n1", to: "n0", label: "y" }])
  const a = boxes.get("n0")
  const b = boxes.get("n1")
  assert.ok(go.points[0][0] >= a.x + a.w && go.arrow.x <= b.x)
  assert.ok(Math.abs(go.arrow.angle) < 1)
  assert.ok(Math.abs(Math.abs(back.arrow.angle) - 180) < 1)
  assert.ok(Math.abs(go.points[0][1] - back.points[0][1]) > 10, "two lanes")
  assert.ok(go.label && go.label.x > a.x + a.w && go.label.x < b.x)
  const [none] = route(boxes, [{ id: "e3", from: "n0", to: "n1" }])
  assert.equal(none.label, null)
})

test("a return edge is an arc over the stations; an orthogonal route has right angles", () => {
  const boxes = place("row", nodesOf(4), { width: 800 }, {})
  const [arc] = route(boxes, [{ id: "r", from: "n3", to: "n0", back: true, label: "indietro" }])
  const top = Math.min(boxes.get("n0").y, boxes.get("n3").y)
  assert.ok(arc.points.length > 6 && Math.min(...arc.points.map((p) => p[1])) < top - 15)
  const stair = new Map([["a", { x: 0, y: 0, w: 100, h: 40 }], ["b", { x: 300, y: 200, w: 100, h: 40 }]])
  const [el] = route(stair, [{ id: "o", from: "a", to: "b" }], { orthogonal: true })
  for (let i = 1; i < el.points.length; i++) assert.ok(el.points[i][0] === el.points[i - 1][0] || el.points[i][1] === el.points[i - 1][1])
})

test("flip tells what stays, enters and leaves, and never takes longer than 300 ms", () => {
  assert.deepEqual(flip(["a", "b"], ["b", "c"], 300), { keep: ["b"], enter: ["c"], leave: ["a"], ms: 300 })
  assert.equal(flip(["a"], ["a"], 0).ms, 0)
  assert.equal(flip([], ["a"], 900).ms, 300)
})

test("the list of moves names who, to whom and what, with the short name before the comma", () => {
  const nodes = [{ id: "anna", label_it: "Anna, venditrice" }, { id: "paolo", label_it: "Paolo, compratore" }]
  assert.deepEqual(moveList(nodes, [{ from: "anna", to: "paolo", label_it: "consegna la bicicletta" }, { from: "paolo", to: "anna" }]), [
    { n: 1, text_it: "Da Anna a Paolo: consegna la bicicletta" },
    { n: 2, text_it: "Da Paolo ad Anna" }
  ])
})
