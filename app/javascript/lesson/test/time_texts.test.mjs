// The words of the time family live twice, in config/locales/lesson_time.it.yml (Ruby reads them) and in time/texts.js (the layouts):
// this test fails when they differ, and when the caps the layouts mirror differ from config/banco/validation_rules.yml.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const { TEXT } = await import("lesson/diagrams/time/texts")
const { CAPS: YEARS } = await import("lesson/diagrams/time/years")
const { CAPS: TENSE } = await import("lesson/diagrams/time/tense")
const yml = readFileSync(new URL("config/locales/lesson_time.it.yml", root), "utf8")
const scene = {}
for (const line of yml.split("\n")) {
  const m = line.match(/^ {6}(\w+): "(.*)"$/)
  if (m) scene[m[1]] = m[2]
}

test("texts.js says what the locale file says", () => {
  assert.deepEqual(Object.keys(TEXT).sort(), Object.keys(scene).sort())
  for (const [k, v] of Object.entries(TEXT)) assert.equal(v, scene[k], k)
})

test("the caps the layouts mirror are those of validation_rules.yml", () => {
  const rules = readFileSync(new URL("config/banco/validation_rules.yml", root), "utf8")
  assert.match(rules, /timeline: \{lanes: \[1, 3\], periods_per_state: 6, events_per_state: 12, marks: \[1, 8\], tense_mark_words: 8, spans: 4, label_words: 6, note_words: 25, ticks: 40\}/)
  assert.deepEqual(YEARS, { label_words: 6, note_words: 25, ticks: 40 })
  assert.equal(TENSE.tense_mark_words, 8)
})
