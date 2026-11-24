// mirror: the note of a piece starts clear of the piece. The piece of a note is drawn bold, so it is wider than the same text measured
// plain: measured plain, a wide piece ("the sixth form") ran into its note ("In Inghilterra, a 16-18 anni") on a phone.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const mirror = await import("lesson/diagrams/words/mirror")
const { estimate } = await import("lesson/diagrams/common")

// the browser's probe wears the label's classes; in node the bold piece is a fifth wider
const measure = (text, px, maxW, cls = "") => {
  const m = estimate(text, px, maxW)
  return cls.includes("dg-mr-notepiece") ? { ...m, w: Math.ceil(m.w * 1.2) } : m
}

const data = (piece, note) => ({
  type: "mirror",
  alt_it: "Una frase italiana sopra la stessa frase in inglese, pezzo per pezzo: il pezzo inglese ha una nota.",
  rows: [{ pieces_it: ["Il biennio finale"], pieces_en: [piece], links: [[0, 0, "false_friend"]], notes: [{ side: "en", piece: 0, note_it: note }] }]
})

const MARGIN = 6
const GAP = 8 // the least space between a piece and its note

test("the note of a piece never touches the piece, at the phone's width and the text sizes", () => {
  for (const [piece, note] of [["the sixth form", "In Inghilterra, a 16-18 anni"], ["sixth form college", "Scuola che prepara all'università"], ["form", "Un anno di scuola"]]) {
    for (const width of [320, 360, 390, 768, 1280]) {
      for (const fontPx of [18, 20, 26]) {
        const scene = mirror.layout(data(piece, note), { width, fontPx, subject: "english", measure })
        assert.ok(!scene.error, `${width}/${fontPx}: ${scene.error?.message}`)
        const p = scene.labels.find((l) => l.key === "r1:np0")
        const n = scene.labels.find((l) => l.key === "r1:nt0")
        const drawn = measure(piece, fontPx, undefined, "dg-mr-notepiece").w
        assert.ok(p.w >= drawn, `${width}/${fontPx}: the piece box is the bold one`)
        const sameLine = n.y < p.y + p.h && p.y < n.y + n.h
        if (sameLine) assert.ok(n.x >= p.x + drawn + GAP, `${width}/${fontPx}: the note starts ${n.x - (p.x + drawn)} px after "${piece}"`)
        else assert.ok(n.y >= p.y + p.h, `${width}/${fontPx}: the note is under its piece`)
        assert.ok(p.x >= MARGIN && n.x + n.w <= width, "inside the width")
      }
    }
  }
})
