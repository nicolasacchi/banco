// The dialogue block (WAVE2 2.6, T3): what "Ascolta tutto" is given to read. The page (glosses, buttons, print) is run in Chrome by
// test/system/words_family_test.rb; the checks of the block are Ruby's (test/lib/lessons/dialogue_test.rb).
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { segmentsOf, langOf, textOf } = await import("lesson/blocks/dialogue")

const block = {
  type: "dialogue",
  title_it: "Ascolta Tom e Amy",
  speakers: [{ id: "t", name: "Tom", voice: 3 }, { id: "a", name: "Amy" }],
  lines: [
    { speaker: "t", text_en: "Are you coming to the lake on Saturday?", gloss_it: "Vieni al lago sabato?" },
    { speaker: "a", text_en: "Yes, if it doesn't rain.", gloss_it: "Sì, se non piove." }
  ]
}

test("the language and the text of a line are read from its key", () => {
  assert.equal(langOf(block), "en")
  assert.equal(textOf(block.lines[1]), "Yes, if it doesn't rain.")
  assert.equal(langOf({ lines: [{ speaker: "a", text_es: "Hola", gloss_it: "Ciao" }] }), "es")
})

test("the segments carry the language, the text and the speaker's voice (a speaker with none gets the number of its place)", () => {
  assert.deepEqual(segmentsOf(block), [
    { lang: "en", text: "Are you coming to the lake on Saturday?", voice: 3 },
    { lang: "en", text: "Yes, if it doesn't rain.", voice: 2 }
  ])
})
