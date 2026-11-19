// Every flow of the production lessons still draws (D-383, the decision as a rhombus): the 20 trickiest tree flows, content only, laid out at
// a phone and a desktop width and in the three font sizes. None errs, none has two nodes over each other or a text out of its node, and the
// indented layout (a node joined twice, a narrow screen) is among them. FLOW_PRODUCTION=/path/to/production_flows.json runs a whole export
// ([{ lesson, path, diagram }]) instead, every diagram of layout tree, the way the change was checked against the 207 of the day.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { audit } from "./flow_audit.mjs"

const { layout } = await import("lesson/diagrams/flow")

const fixture = JSON.parse(readFileSync(new URL("../../../../test/fixtures/diagrams/flow_production.json", import.meta.url), "utf8")).diagrams
const everything = process.env.FLOW_PRODUCTION
  ? JSON.parse(readFileSync(process.env.FLOW_PRODUCTION, "utf8")).filter((x) => x.diagram.layout !== "line").map((x) => ({ ...x, subject: x.lesson.split(".")[1] }))
  : null
const cases = everything ?? fixture
const drawn = (scene) => scene.shapes.some((s) => s.cls === "dg-arrowhead")

test("the fixture holds 20 tree flows, with the two layouts among them", () => {
  assert.equal(fixture.length, 20)
  assert.ok(fixture.every((x) => x.diagram.type === "flow" && x.diagram.layout !== "line"))
  const kinds = new Set(fixture.map((x) => drawn(layout(x.diagram, { width: 1280, fontPx: 20, subject: x.subject }))))
  assert.deepEqual([...kinds].sort(), [false, true], "some are centred trees, some take the indented layout, at 1280")
})

for (const x of cases) {
  test(`${x.lesson} ${x.path}: draws soundly at 390 and 1280`, () => {
    for (const width of [390, 1280]) {
      for (const fontPx of [18, 20, 26]) {
        const scene = layout(x.diagram, { width, fontPx, subject: x.subject })
        assert.deepEqual(audit(scene), [], `${width}/${fontPx}`)
        for (const l of scene.labels) assert.ok(l.px >= fontPx, "no text under the base size")
        assert.ok(scene.height > 0)
      }
    }
  })
}
