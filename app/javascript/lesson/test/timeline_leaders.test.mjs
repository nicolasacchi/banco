// timeline: no leader (the thin connector from an event's label in a further row down to its point) runs through a label. The browser draws
// the plates wider than node's estimate, so every figure is laid out with the estimate and with it grown by 15 % and 30 %; a leader through
// a neighbour is solved by rows and a sideways slide, and when the labels cannot be clear at the widest they wrap narrower (more lines,
// same text size). Positions of the drawings that had no crossing do not change (the vectors' own test fixes the rest).
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const doc = JSON.parse(readFileSync(new URL("test/fixtures/diagrams/types/timeline.json", root), "utf8"))
const { layout } = await import("lesson/diagrams/time/timeline")
const { crosses, estimate, stateCount } = await import("lesson/diagrams/common")

const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]
const GROW = [1, 1.15, 1.3]

const grown = (k) => (text, px, maxW, cls = "") => {
  const m = estimate(text, px, maxW)
  return { w: Math.ceil(m.w * k) + (cls.includes("plate") ? 16 : 0), h: m.h }
}

// the first label a leader runs through (the leader ends against its own label: the top and bottom of every box are left out)
const through = (scene) => {
  for (const s of scene.shapes) {
    if (s.cls !== "dg-connector") continue
    const hit = scene.labels.find((l) => crosses(s, { x: l.x, y: l.y + 3, w: l.w, h: l.h - 6 }, 1))
    if (hit) return `a leader at x ${s.x1.toFixed(0)} runs through ${hit.text_it}`
  }
  return null
}

const FACTS = (n) => Array.from({ length: n }, (_, i) => ({ id: `e${i + 1}`, at: String(-140 + Math.round((i * 110) / Math.max(n - 1, 1))), label_it: ["Primo fatto di prova", "Secondo fatto", "Terzo fatto di prova", "Quarto fatto", "Quinto fatto qui"][i], role: i % 2 ? "effect" : "cause" }))
const LINE = (events, extra = {}) => ({ type: "timeline", alt_it: "Una linea del tempo dal 146 al 27 avanti Cristo con alcuni fatti inventati, vicini tra loro.", scale: "years", from: "-146", to: "-27", every: 10, events, ...extra })

const CASES = [
  // the time gallery's first figure (the state that the render check found a leader through «circa 82 a.C.: Terzo fatto di prova» at 390 px)
  ["the gallery's four facts", LINE([{ id: "e1", at: "-133", label_it: "Primo fatto di prova", role: "cause" }, { id: "e2", at: "-100", label_it: "Secondo fatto", role: "rome" }, { id: "e3", at: "-82", label_it: "Terzo fatto di prova", approx: true, role: "effect" }, { id: "e4", at: "-44", label_it: "Quarto fatto", role: "effect" }], { centuries: true })],
  ["three close facts", LINE(FACTS(3))],
  ["five facts", LINE(FACTS(5))],
  ["two facts at the ends", LINE([{ id: "a", at: "-146", label_it: "Il primo fatto, proprio all'inizio" }, { id: "b", at: "-27", label_it: "L'ultimo fatto, proprio alla fine" }])]
]

for (const [name, data] of CASES) {
  test(`${name}: no leader through a label at any width, text size and measure`, () => {
    for (const k of GROW) {
      for (const width of WIDTHS) {
        for (const fontPx of SIZES) {
          if (name === "five facts" && width === 320 && fontPx === 26) continue // five plates of 120 px or more do not fit side by side nor in rows on 320 px at the largest text: the render check says so
          const scene = layout(data, { width, fontPx, subject: "history", measure: grown(k) })
          assert.ok(!scene.error, `${width}/${fontPx}/x${k}: ${scene.error?.message}`)
          assert.equal(through(scene), null, `${width}/${fontPx}/x${k}`)
          assert.ok(scene.labels.every((l) => l.px >= fontPx && l.x >= -0.5 && l.x + l.w <= width + 0.5), `${width}/${fontPx}/x${k}: labels inside, none under the base size`)
        }
      }
    }
  })
}

test("every drawable vector of the type has no leader through a label, in every state", () => {
  for (const v of doc.vectors.filter((x) => x.schema === "valid" && x.semantic === "ok")) {
    for (const k of GROW) {
      for (const width of WIDTHS) {
        for (const fontPx of SIZES) {
          for (let state = 0; state < stateCount(v.data); state++) {
            const scene = layout(v.data, { width, fontPx, subject: v.subject, state, measure: grown(k) })
            if (scene.error) continue
            assert.equal(through(scene), null, `${v.name} ${width}/${fontPx}/x${k}/${state}`)
          }
        }
      }
    }
  }
})

test("labels that already stood clear keep their place", () => {
  const scene = layout(LINE([{ id: "a", at: "-140", label_it: "Fatto" }, { id: "b", at: "-30", label_it: "Altro fatto" }]), { width: 390, fontPx: 20, subject: "history" })
  const notes = scene.labels.filter((l) => l.cls.includes("evlabel"))
  assert.equal(notes.length, 2)
  assert.equal(new Set(notes.map((l) => l.y + l.h)).size, 1, "one row")
  assert.equal(scene.shapes.filter((s) => s.cls === "dg-connector").length, 0, "no leader")
})
