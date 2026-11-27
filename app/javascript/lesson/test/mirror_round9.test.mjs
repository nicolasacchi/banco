// mirror, round 9 of the bilingual tooling: at a phone's width the words of the link kinds («stesso significato») are a legend, drawn once under the pairs and never
// under every pair, and the two column titles (the two languages) are drawn over the columns as the wide figure names its two lines.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const mirror = await import("lesson/diagrams/words/mirror")
const { estimate } = await import("lesson/diagrams/common")
const measure = (text, px, maxW) => estimate(text, px, maxW)

const ALT = "Una frase italiana sopra la stessa frase nell'altra lingua, pezzo per pezzo, con le coppie."
const row = (links, extra = {}) => ({ pieces_it: ["I", "miei", "cugini"], pieces_es: ["mis", "primos", "viven"], links, ...extra })
const data = (...rows) => ({ type: "mirror", alt_it: ALT, rows })
const SAME_MEANING = [[0, 0, "meaning"], [1, 1, "meaning"], [2, 2, "meaning"]]
const layout = (d, extra = {}) => mirror.layout(d, { width: 390, fontPx: 20, subject: "spanish", measure, forceNarrow: true, ...extra })
const labels = (scene, re) => scene.labels.filter((l) => re.test(l.key ?? ""))

test("390 px: «stesso significato» is printed once for three pairs of that kind, as a legend under the pairs (no word under each pair)", () => {
  const scene = layout(data(row(SAME_MEANING)))
  assert.ok(!scene.error, scene.error?.message)
  assert.equal(labels(scene, /:k\d/).length, 0, "no kind word under a pair")
  const words = scene.labels.filter((l) => l.text_it === "stesso significato")
  assert.equal(words.length, 1)
  assert.equal(words[0].key, "key:meaning:t")
  const lowestBox = Math.max(...scene.shapes.filter((s) => /^r1[it]\d:\d$/.test(s.key ?? "")).map((s) => s.y + s.h))
  assert.ok(words[0].y >= lowestBox, "the legend is under the last pair")
  assert.ok(scene.shapes.some((s) => s.key === "key:meaning:m"), "its mark is in the legend")
})

test("390 px: two rows with the same kind still have one legend, each kind once; a pair with no partner stays out of it", () => {
  const two = layout(data(row(SAME_MEANING), row([[0, 0, "same"], [1, 1, "meaning"], [2, 2, "same"]])))
  assert.ok(!two.error, two.error?.message)
  assert.deepEqual(labels(two, /^key:.*:t$/).map((l) => l.text_it).sort(), ["stesso significato", "uguale"])
  assert.equal(labels(two, /:k\d/).length, 0)
  // a pair with no partner says «senza coppia» in its own place: it has no kind, so no legend entry
  const lone = layout(data(row([[0, 0, "same"], [1, 1, "meaning"]], { notes: [{ side: "it", piece: 2, note_it: "non c'è in spagnolo" }, { side: "es", piece: 2, note_it: "il verbo in più" }] })))
  assert.ok(!lone.error, lone.error?.message)
  assert.deepEqual(labels(lone, /^key:.*:t$/).map((l) => l.text_it), ["uguale", "stesso significato"])
  assert.ok(labels(lone, /:none/).length >= 1)
})

test("the narrowest layout (each pair stacked) has the legend too, once, and no word beside a link", () => {
  const scene = layout(data(row(SAME_MEANING)), { width: 320, fontPx: 26 })
  assert.ok(!scene.error, scene.error?.message)
  assert.ok(scene.shapes.some((s) => /^r1:l\d$/.test(s.key ?? "")), "the links are drawn")
  assert.equal(labels(scene, /:k\d/).length, 0)
  assert.equal(scene.labels.filter((l) => l.text_it === "stesso significato").length, 1)
})

test("390 px draws the two column titles over the pairs, as 1280 px draws its two side names; a bilingual lesson's are in its language", () => {
  const wide = mirror.layout(data(row(SAME_MEANING)), { width: 1280, fontPx: 20, subject: "spanish", measure })
  assert.deepEqual(labels(wide, /:side-/).map((l) => l.text_it).sort(), ["Italiano", "Spagnolo"])
  const narrow = layout(data(row(SAME_MEANING)))
  const [it, tg] = ["r1:side-it", "r1:side-tg"].map((k) => narrow.labels.find((l) => l.key === k))
  assert.deepEqual([it.text_it, tg.text_it], ["Italiano", "Spagnolo"])
  assert.ok(it.x < tg.x && it.y === tg.y, "side by side, the Italian column first")
  const firstBox = Math.min(...narrow.shapes.filter((s) => /^r1[it]\d:\d$/.test(s.key ?? "")).map((s) => s.y))
  assert.ok(it.y + it.h <= firstBox, "over the first pair")
  const box = narrow.shapes.find((s) => s.key === "r1i1:0")
  assert.ok(it.x >= box.x && it.x + it.w <= box.x + box.w, "over the Italian column")
  const bilingual = layout(data(row(SAME_MEANING)), { lang: "es" })
  assert.deepEqual(labels(bilingual, /:side-/).map((l) => [l.text_it, l.lang]), [["italiano", "es"], ["español", "es"]])
  // several rows: each row names its columns under its pair number
  const several = layout(data(row(SAME_MEANING), row(SAME_MEANING)))
  assert.equal(labels(several, /:side-it$/).length, 2)
  assert.ok(several.labels.find((l) => l.key === "r2:title").y < several.labels.find((l) => l.key === "r2:side-it").y)
})
