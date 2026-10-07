// "Come si risponde" (D-216): which lines the help shows for the component on screen.
import assert from "node:assert/strict"
import { test } from "node:test"
import { helpSections } from "../../../app/javascript/items/help_sections.js"

const help = {
  common: ["Premi Invia."],
  number: ["Scrivi il numero."], number_unit: ["Non scrivere l'unità."],
  fraction: ["Due caselle."], fraction_mixed: ["Parte intera."],
  expression: ["Usa la tastiera."], choice: ["Scegli una."], ordering: ["Su e Giù."],
  matching: ["Un menu."], matching_reuse: ["Più voci."], normalized_text: ["Scrivi."], normalized_text_accents: ["Accenti."],
  short_answer: ["Parole tue."], testlet: ["Leggi il brano."],
  component_names: { number: "Numeri", choice: "Scelta" }
}
const t = { help }
const lines = (item) => helpSections(item, t).flatMap((s) => s.lines)

test("each component has its own lines and the common ones", () => {
  assert.deepEqual(lines({ component: "number" }), ["Scrivi il numero.", "Premi Invia."])
  assert.deepEqual(lines({ component: "choice" }), ["Scegli una.", "Premi Invia."])
  assert.deepEqual(lines({ component: "short_answer" }), ["Parole tue.", "Premi Invia."])
})

test("options of the item add lines: unit, mixed number, reused answers, accents", () => {
  assert.ok(lines({ component: "number", unit: "cm" }).includes("Non scrivere l'unità."))
  assert.ok(lines({ component: "fraction", mixed: true }).includes("Parte intera."))
  assert.ok(!lines({ component: "fraction" }).includes("Parte intera."))
  assert.ok(lines({ component: "matching", reuse_right: true }).includes("Più voci."))
  assert.ok(lines({ component: "normalized_text", accents: "es" }).includes("Accenti."))
  assert.ok(!lines({ component: "normalized_text" }).includes("Accenti."))
})

test("a testlet shows its own lines, then each distinct component of its sub items once", () => {
  const item = { component: "testlet", sub_items: [{ component: "choice" }, { component: "number" }, { component: "choice" }] }
  const sections = helpSections(item, t)
  assert.deepEqual(sections[0].lines, ["Leggi il brano."])
  assert.deepEqual(sections.slice(1, 3).map((s) => s.heading), ["Scelta", "Numeri"])
  assert.deepEqual(sections.at(-1).lines, ["Premi Invia."])
  assert.equal(sections.length, 4)
})

test("an unknown component or missing texts give no error", () => {
  assert.deepEqual(helpSections({ component: "nope" }, { help: {} }), [{ heading: null, lines: [] }])
  assert.deepEqual(helpSections({ component: "number" }, {}), [{ heading: null, lines: [] }])
})
