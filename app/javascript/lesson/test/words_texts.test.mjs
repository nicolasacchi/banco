// The words of the words family live twice, in config/locales/lesson_words.it.yml (Ruby reads them) and in diagrams/words/texts.js (the layouts):
// this test fails when they differ, and when the caps the layouts mirror differ from config/banco/validation_rules.yml.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const { TEXT, CAPS } = await import("lesson/diagrams/words/texts")
const yml = readFileSync(new URL("config/locales/lesson_words.it.yml", root), "utf8")
const scene = {}
let inScene = false
for (const line of yml.split("\n")) {
  if (/^ {4}scene:/.test(line)) inScene = true
  else if (/^ {4}\w+:/.test(line)) inScene = false
  const m = line.match(/^ {6}(\w+): "(.*)"$/)
  if (inScene && m) scene[m[1]] = m[2]
}

test("texts.js says what the locale file says", () => {
  assert.deepEqual(Object.keys(TEXT).sort(), Object.keys(scene).sort())
  for (const [k, v] of Object.entries(TEXT)) assert.equal(v, scene[k], k)
})

test("the caps the layouts mirror are those of validation_rules.yml", () => {
  const rules = readFileSync(new URL("config/banco/validation_rules.yml", root), "utf8")
  const caps = CAPS.word_parts
  assert.match(rules, new RegExp(`word_parts: \\{words: \\[${caps.words.join(", ")}\\], parts: ${caps.parts}, letters: ${caps.letters}, syllables: ${caps.syllables}, meaning_words: ${caps.meaning_words}\\}`))
  assert.match(rules, new RegExp(`mirror: \\{rows: \\[${CAPS.mirror.rows.join(", ")}\\], words_per_side: ${CAPS.mirror.words_per_side}\\}`))
  assert.match(rules, /dialogue: \{lines: \[2, 12\], line_words: 12, speakers: \[1, 3\], speaker_name_chars: 12\}/)
})
