// The flow (the schema of the summary): a tree that fits is drawn centred with arrows and a dark first box; on a phone, or when a
// node is joined twice, the indented layout draws it.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { layout } = await import("lesson/diagrams/flow")

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
