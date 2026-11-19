// The flow (the schema of the summary): a tree that fits is drawn centred with arrows and a dark first box; on a phone, or when a
// node is joined twice, the indented layout draws it.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { audit } from "./flow_audit.mjs"

const { layout, describe, printed, rhombus } = await import("lesson/diagrams/flow")
const { makeContext } = await import("lesson/diagrams/common")

const tree = {
  type: "flow", alt_it: "Schema: due passi, poi una domanda con due risposte.",
  nodes: [
    { id: "a", kind: "step", text_it: "Primo passo" }, { id: "b", kind: "step", text_it: "Secondo passo" }, { id: "q", kind: "decision", text_it: "Domanda?" },
    { id: "s", kind: "end", text_it: "Risposta sì" }, { id: "n", kind: "end", text_it: "Risposta no" }
  ],
  edges: [["a", "b"], ["b", "q"], ["q", "s", "sì"], ["q", "n", "no"]]
}
const classes = (scene) => scene.shapes.map((s) => s.cls ?? "")

test("a wide tree is centred, with arrowheads and a dark first box", () => {
  const scene = layout(tree, { width: 760, fontPx: 20, subject: "math" })
  assert.ok(!scene.error, scene.error?.message)
  assert.equal(classes(scene).filter((c) => c === "dg-arrowhead").length, 4)
  assert.ok(classes(scene).some((c) => /dg-start/.test(c)))
  const first = scene.labels.find((l) => l.text_it === "Primo passo")
  assert.ok(Math.abs(first.x + first.w / 2 - 380) < 2, "the first box is on the middle line")
})

test("a narrow screen, or a node joined twice, takes the indented layout", () => {
  const narrow = layout(tree, { width: 240, fontPx: 20, subject: "math" })
  assert.ok(!narrow.error, narrow.error?.message)
  assert.equal(classes(narrow).filter((c) => c === "dg-arrowhead").length, 0)
  const joined = {
    ...tree,
    nodes: [{ id: "q", kind: "decision", text_it: "Domanda?" }, { id: "x", kind: "step", text_it: "Via sì" }, { id: "y", kind: "step", text_it: "Via no" }, { id: "z", kind: "end", text_it: "Fine" }],
    edges: [["q", "x", "sì"], ["q", "y", "no"], ["x", "z"], ["y", "z"]]
  }
  const wide = layout(joined, { width: 760, fontPx: 20, subject: "math" })
  assert.ok(!wide.error, wide.error?.message)
  assert.equal(classes(wide).filter((c) => c === "dg-arrowhead").length, 0)
})

// ---- D-383: the decision as a rhombus, and the loop (the way back to a decision) ----------------------------------------------------------------

const vectors = JSON.parse(readFileSync(new URL("../../../../test/fixtures/diagrams/vectors.json", import.meta.url), "utf8")).vectors
const vector = (name) => vectors.find((v) => v.name === name).data
const doWhile = vector("flow-loop-do-while")
const paths = (scene) => scene.shapes.filter((s) => s.kind === "path")
const heads = (scene) => scene.shapes.filter((s) => s.cls === "dg-arrowhead")

test("a decision is drawn as a rhombus that holds its text, in both layouts", () => {
  for (const width of [240, 390, 1280]) {
    const scene = layout(tree, { width, fontPx: 20, subject: "math" })
    assert.ok(!scene.error, scene.error?.message)
    const diamonds = scene.shapes.filter((s) => s.kind === "polygon" && /dg-decision/.test(s.cls))
    assert.equal(diamonds.length, 1, `${width}: one rhombus`)
    const [top, right, bottom, left] = diamonds[0].points
    assert.equal(top[0], bottom[0], "the vertices are on the vertical axis")
    assert.equal(left[1], right[1], "and on the horizontal one")
    assert.ok(right[0] - left[0] > bottom[1] - top[1], "a rhombus wider than tall")
    assert.deepEqual(audit(scene), [])
  }
})

test("a long question is wrapped, then the rhombus widens; the text is never under the base size", () => {
  const ctx = makeContext({}, { width: 1280, fontPx: 20 })
  const short = rhombus(ctx, "n < 50?", 320)
  assert.equal(short.mt.h, ctx.lineH, "a short question stays on one line")
  const long = rhombus(ctx, "Il saldo del conto è ancora sotto la soglia stabilita dal contratto?", 320)
  assert.ok(long.mt.h > ctx.lineH, "a long one is wrapped")
  assert.ok(long.w <= 320 && long.w > short.w)
  // a text that no rhombus of that width can hold in the usual shape takes a taller, narrower one, never a smaller text; none that fits is null
  const narrow = rhombus(ctx, "Il saldo del conto è ancora sotto la soglia stabilita dal contratto?", 260)
  assert.ok(narrow.h > long.h && narrow.w <= 260)
  assert.equal(rhombus(ctx, "Il saldo del conto è ancora sotto la soglia stabilita dal contratto?", 150), null)
  for (const fontPx of [18, 20, 26]) {
    const scene = layout(vector("flow-loop-long-question"), { width: 390, fontPx, subject: "math" })
    assert.ok(scene.labels.every((l) => l.px >= fontPx))
  }
})

test("a Do While: a loop is an orthogonal arrow from the body up to the question, beside the chain", () => {
  for (const width of [390, 1280]) {
    const scene = layout(doWhile, { width, fontPx: 20, subject: "math" })
    assert.ok(!scene.error, scene.error?.message)
    assert.deepEqual(audit(scene), [], String(width))
    const [loop] = paths(scene)
    assert.equal(paths(scene).length, 1)
    const [, x0, y0, X, Y, x1] = loop.d.match(/^M(-?[\d.]+),(-?[\d.]+) H(-?[\d.]+) V(-?[\d.]+) H(-?[\d.]+)$/).map(Number)
    assert.ok(Y < y0, "it runs up")
    assert.ok((X - x0) * (X - x1) > 0, "out and in on the same side")
    // 4 arrowheads of the tree (a to q, q to b, q to e... three edges) and the loop's own: pointing into the question's vertex
    assert.equal(heads(scene).length, 4)
    const head = heads(scene).at(-1)
    assert.equal(head.points[2][1], Y, "the arrowhead enters at the height of the question")
    assert.ok(scene.labels.some((l) => l.text_it === "torna alla domanda"), "the label of the loop")
    assert.ok(classes(scene).includes("dg-node dg-decision st-muted"))
  }
})

test("the loops of the vectors draw at every width and size, in the centred tree or the indented layout, with no arrow over a node", () => {
  for (const name of ["flow-loop-do-while", "flow-loop-nested-two", "flow-loop-long-question"]) {
    for (const width of [320, 390, 768, 1280]) {
      for (const fontPx of [18, 20, 26]) {
        const scene = layout(vector(name), { width, fontPx, subject: "math" })
        assert.ok(!scene.error, `${name} ${width}/${fontPx}: ${scene.error?.message}`)
        assert.deepEqual(audit(scene), [], `${name} ${width}/${fontPx}`)
        assert.equal(paths(scene).length, vector(name).loops.length, "one arrow per loop")
        assert.ok(scene.labels.every((l) => l.px >= fontPx))
      }
    }
  }
})

test("on a phone a loop takes the room it needs: the tree moves off the middle, or the indented layout draws it", () => {
  const phone = layout(doWhile, { width: 390, fontPx: 20, subject: "math" })
  assert.ok(heads(phone).length > 0, "the centred tree fits a Do While on a phone")
  const nested = layout(vector("flow-loop-nested-two"), { width: 390, fontPx: 20, subject: "math" })
  assert.equal(heads(nested).length, 2, "the nested flow takes the indented layout at 390: no arrow of the tree, the two of the loops")
  assert.equal(paths(nested).length, 2)
})

test("the description and the printed texts say the way back", () => {
  const text = describe(doWhile, {})
  assert.match(text, /Passo: n = n \* 3, poi si torna a «n < 50\?» \(torna alla domanda\)\./)
  assert.match(describe(vector("flow-loop-nested-two"), {}), /Passo: n = 3 \* n \+ 1, poi si torna a «n è diverso da 1\?»\./)
  assert.ok(printed(doWhile).includes("torna alla domanda"))
})

test("the audit is not vacuous: a text out of its node, a loop over a node and two loops that cross are found", () => {
  const scene = layout(doWhile, { width: 1280, fontPx: 20, subject: "math" })
  const moved = { ...scene, labels: scene.labels.map((l) => (l.text_it === "n = n * 3" ? { ...l, x: l.x + 60 } : l)) }
  assert.ok(audit(moved).some((p) => /not inside one node/.test(p)))
  const over = { ...scene, shapes: scene.shapes.map((s) => (s.kind === "path" ? { ...s, d: "M10,10 H4000 V400 H10" } : s)) }
  assert.ok(audit(over).some((p) => /crosses/.test(p)))
  const [loop] = paths(scene)
  const crossing = { ...scene, shapes: [...scene.shapes, { ...loop, d: "M0,150 H4000 V0 H0" }, { ...loop, d: "M-100,50 H10 V400 H20" }] }
  assert.ok(audit(crossing).some((p) => /two loops cross/.test(p)))
})

test("the rules: a loop goes back to a decision, from under it, from a node that is no end; a step with a loop has no edge; cycles among edges stay refused", () => {
  const ok = (extra) => layout({ ...doWhile, ...extra }, { width: 390, fontPx: 20, subject: "math" })
  assert.ok(!ok({}).error)
  assert.equal(ok({ loops: [{ from: "b", to: "a" }] }).error.path, "/loops/0/to")
  assert.equal(ok({ loops: [{ from: "e", to: "q" }] }).error.path, "/loops/0/from")
  assert.equal(ok({ loops: [{ from: "a", to: "q" }] }).error.path, "/loops/0/from")
  assert.equal(ok({ loops: [{ from: "q", to: "q" }] }).error.path, "/loops/0/from")
  assert.equal(ok({ loops: [{ from: "zz", to: "q" }] }).error.path, "/loops/0")
  assert.equal(ok({ edges: [...doWhile.edges, ["b", "e"]] }).error.path, "/nodes/2", "a step with an edge and a loop")
  assert.equal(ok({ loops: [] }).error?.path ?? "schema", "/loops", "an empty list is refused by the schema")
  const { loops, ...plain } = doWhile
  assert.equal(layout({ ...plain, edges: [...doWhile.edges, ["b", "q"]] }, { width: 390, fontPx: 20, subject: "math" }).error.message, "a flow has no cycles among its edges (a way back to a decision is written in loops)")
})
