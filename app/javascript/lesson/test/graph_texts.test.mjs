// The words of the graph family live twice, in config/locales/lesson_graph.it.yml (Ruby reads them) and in graph/texts.js (the layouts):
// this test fails when they differ, and when the caps the layouts mirror differ from config/banco/validation_rules.yml.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const { TEXT, AREAS } = await import("lesson/diagrams/graph/texts")
const yml = readFileSync(new URL("config/locales/lesson_graph.it.yml", root), "utf8")
const scene = {}
let inAreas = false
const areas = {}
for (const line of yml.split("\n")) {
  const m = line.match(/^ {6}(\w+): "(.*)"$/)
  if (m) scene[m[1]] = m[2]
  if (/^ {6}areas:/.test(line)) inAreas = true
  const a = line.match(/^ {8}(\w+): "(.*)"$/)
  if (inAreas && a) areas[a[1]] = a[2]
}

test("texts.js says what the locale file says", () => {
  assert.deepEqual(Object.keys(TEXT).sort(), Object.keys(scene).sort())
  for (const [k, v] of Object.entries(TEXT)) assert.equal(v, scene[k], k)
  for (const [k, v] of Object.entries(AREAS)) assert.equal(v.label_it, areas[k], k)
  assert.equal(Object.keys(areas).length, Object.keys(AREAS).length)
})

test("the caps the layouts mirror are those of validation_rules.yml", () => {
  const rules = readFileSync(new URL("config/banco/validation_rules.yml", root), "utf8")
  assert.match(rules, /network: \{nodes: \[2, 8\], edges_per_state: 12, label_words: 6, note_words: 25, badge_words: 4\}/)
  assert.match(rules, /chain: \{nodes: \[3, 10\], node_words: 8, not_causal_links: 2, back_links: 1\}/)
  assert.match(rules, /flow_line: \{stations: 8, branch_stations: 4, returns: 3, station_words: \[2, 4\]\}/)
})
