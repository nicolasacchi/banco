// number_line mark labels: close labels never collide. No label box touches another, a tick number, a mark, and no leader
// (the thin line from a label in a further row to its mark) crosses a tick number, a label or another leader, at the phone's 390 px,
// narrower and wider windows and every text size. Labels that fit side by side keep the place they had.
import "./setup.mjs"
import assert from "node:assert/strict"
import { test } from "node:test"

const { layout } = await import("lesson/diagrams/registry")
const { crosses, overlaps } = await import("lesson/diagrams/common")

const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]
const ALT = "Retta dei numeri con alcuni punti segnati, ciascuno con la sua etichetta"

const line = (min, max, marks, extra = {}) => ({ type: "number_line", alt_it: ALT, min, max, step: "1", labels: "all", marks: marks.map(([at, label_it, kind = "dot"]) => ({ at, label_it, kind })), ...extra })

// Everything that must stay apart in a drawn scene; throws the first pair that does not.
function assertClear(scene, where) {
  const notes = scene.labels.filter((l) => l.cls.includes("dg-note"))
  const ticks = scene.labels.filter((l) => l.cls.includes("dg-tick-label"))
  const leaders = scene.shapes.filter((s) => s.kind === "line" && s.cls === "dg-connector")
  const dots = scene.shapes.filter((s) => s.kind === "circle")
  for (let i = 0; i < scene.labels.length; i++) {
    const a = scene.labels[i]
    assert.ok(a.x >= -0.5 && a.x + a.w <= scene.width + 0.5, `${where}: ${a.text_it} inside the width`)
    assert.ok(a.y >= 0 && a.y + a.h <= scene.height, `${where}: ${a.text_it} inside the height`)
    for (const b of scene.labels.slice(i + 1)) assert.ok(!overlaps(a, b), `${where}: ${a.text_it} overlaps ${b.text_it}`)
    for (const d of a.cls.includes("dg-note") ? dots : []) {
      const box = { x: d.cx - d.r, y: d.cy - d.r, w: 2 * d.r, h: 2 * d.r }
      assert.ok(!overlaps(a, box), `${where}: ${a.text_it} sits on a mark`)
    }
  }
  leaders.forEach((s, i) => {
    for (const l of [...ticks, ...notes]) {
      // a leader ends against its own label: touching that one (within a pixel) is the join, crossing any other is the fault
      const touches = Math.abs(s.y2 - l.y) <= 1 || Math.abs(s.y2 - (l.y + l.h)) <= 1
      if (touches && s.x1 >= l.x && s.x1 <= l.x + l.w) continue
      assert.ok(!crosses(s, l, 1), `${where}: a leader at x ${s.x1.toFixed(0)} crosses ${l.cls.includes("tick") ? "the tick number" : "the label"} ${l.text_it}`)
    }
    for (const t of leaders.slice(i + 1)) assert.ok(Math.abs(t.x1 - s.x1) >= 3 || Math.max(Math.min(s.y1, s.y2), Math.min(t.y1, t.y2)) >= Math.min(Math.max(s.y1, s.y2), Math.max(t.y1, t.y2)), `${where}: two leaders run over each other`)
  })
  return { notes, leaders }
}

function everywhere(name, data) {
  test(name, () => {
    for (const width of WIDTHS) {
      for (const fontPx of SIZES) {
        const scene = layout(data, { width, fontPx, subject: "math" })
        assert.ok(!scene.error, `${width}/${fontPx}: ${scene.error?.message}`)
        assertClear(scene, `${width}/${fontPx}`)
        assert.ok(scene.labels.every((l) => l.px >= fontPx), "no label under the base size")
      }
    }
  })
}

everywhere("two close labels: 17 and 18", line("14", "18", [["17", "UK: auto"], ["18", "Italia: B"]]))
everywhere("three close labels (the lesson's own): 14, 17 and 18", line("14", "18", [["14", "Italia: AM"], ["17", "UK: auto"], ["18", "Italia: B"]]))
everywhere("labels at both ends and next to them", line("0", "10", [["0", "inizio"], ["1", "poco dopo"], ["9", "poco prima"], ["10", "fine"]]))
everywhere("a label at the min end and another beside it", line("0", "5", [["0", "partenza"], ["1", "primo passo"]]))
everywhere("a label at the max end and another beside it", line("0", "5", [["4", "primo passo"], ["5", "arrivo"]]))
everywhere("five labels in a row", line("0", "6", [["1", "uno"], ["2", "due"], ["3", "tre"], ["4", "quattro"], ["5", "cinque"]]))
everywhere("closed, open and cross marks with close labels", line("-3", "3", [["-1", "chiuso", "closed"], ["0", "vuoto", "open"], ["1", "croce", "cross"], ["2", "ancora uno", "dot"]]))
everywhere("close labels under a jump arc", { ...line("14", "18", [["14", "Italia: AM"], ["17", "UK: auto"], ["18", "Italia: B"]]), jumps: [{ from: "14", by: "3", label_it: "+3" }] })
everywhere("a label on an interval and the marks inside it", { ...line("0", "10", [["3", "a metà"], ["4", "fine"]]), intervals: [{ from: "2", to: "4", from_closed: true, to_closed: true, label_it: "da 2 a 4" }] })
everywhere("an interval to infinity beside a mark", { ...line("-5", "5", [["-2", "parti da -2"], ["3", "arrivi a 3"]]), intervals: [{ from: "-inf", to: "-3", from_closed: false, to_closed: true, label_it: "minore di -3" }] })
everywhere("only the marks' tick numbers", { ...line("14", "18", [["14", "Italia: AM"], ["17", "UK: auto"], ["18", "Italia: B"]]), labels: "marks" })
everywhere("only the end tick numbers", { ...line("14", "18", [["14", "Italia: AM"], ["17", "UK: auto"], ["18", "Italia: B"]]), labels: "ends" })

test("the reviewer's figure at 390 px: the label of 18 goes above its mark, no leader runs through a number", () => {
  const scene = layout(line("14", "18", [["14", "Italia: AM"], ["17", "UK: auto"], ["18", "Italia: B"]]), { width: 390, fontPx: 20, subject: "math" })
  const axis = scene.shapes.find((s) => s.cls === "dg-axis").y1
  const byText = Object.fromEntries(scene.labels.map((l) => [l.text_it, l]))
  assert.ok(byText["Italia: B"].y + byText["Italia: B"].h < axis, "above the axis")
  assert.ok(byText["Italia: AM"].y > axis && byText["UK: auto"].y > axis, "the others under the tick numbers")
  const tickBottom = Math.max(...scene.labels.filter((l) => l.cls.includes("tick")).map((l) => l.y + l.h))
  assert.ok(byText["Italia: AM"].y >= tickBottom && byText["UK: auto"].y >= tickBottom)
  assert.equal(scene.shapes.filter((s) => s.cls === "dg-connector").length, 0, "one label alone above: no leader needed")
})

const LONG = [["1", "parti da qui"], ["2", "due passi"], ["3", "arrivo a tre"], ["4", "quattro"], ["5", "a metà strada"]]

test("labels in a further row get a leader that crosses nothing, above the axis", () => {
  const scene = layout(line("0", "6", LONG), { width: 390, fontPx: 20, subject: "math" })
  const { leaders } = assertClear(scene, "390/20")
  assert.ok(leaders.length > 0, "some label needed a leader")
  const axis = scene.shapes.find((s) => s.cls === "dg-axis").y1
  for (const s of leaders) assert.ok(s.y1 < axis && s.y2 < axis, "the leaders run up from the mark, where no tick number is")
})

test("under jump arcs, a leader starts under the tick numbers and crosses nothing", () => {
  const scene = layout({ ...line("0", "6", LONG), jumps: [{ from: "0", by: "1", label_it: "+1" }] }, { width: 390, fontPx: 20, subject: "math" })
  const { leaders } = assertClear(scene, "390/20")
  assert.ok(leaders.length > 0, "some label needed a leader")
  const tickBottom = Math.max(...scene.labels.filter((l) => l.cls.includes("tick")).map((l) => l.y + l.h))
  for (const s of leaders) assert.ok(Math.min(s.y1, s.y2) >= tickBottom, "the leaders start under the tick numbers")
})

test("under jump arcs, five wide labels at 320 px are drawn clear (labels slide over their marks) or refused, never overlapped", () => {
  const scene = layout({ ...line("0", "6", LONG), jumps: [{ from: "0", by: "1", label_it: "+1" }] }, { width: 320, fontPx: 20, subject: "math" })
  if (scene.error) assert.equal(scene.error.code, "E-DIAGRAM-LAYOUT")
  else assertClear(scene, "320/20")
})

test("two labels on one mark under jump arcs cannot both reach it with a straight leader: an error, not a drawing with overlaps", () => {
  const scene = layout({ ...line("0", "6", [["3", "uno"], ["3", "due"]]), jumps: [{ from: "0", by: "1", label_it: "+1" }] }, { width: 390, fontPx: 20, subject: "math" })
  assert.equal(scene.error?.code, "E-DIAGRAM-LAYOUT")
})

test("labels that fit side by side keep their place: centred on the mark, in the row under the tick numbers, no leader", () => {
  const scene = layout(line("-5", "5", [["-4", "inizio"], ["0", "zero"], ["4", "fine"]]), { width: 390, fontPx: 20, subject: "math" })
  const ticks = scene.labels.filter((l) => l.cls.includes("tick"))
  const rowY = Math.max(...ticks.map((l) => l.y + l.h)) + 4
  const notes = scene.labels.filter((l) => l.cls.includes("dg-note"))
  assert.equal(notes.length, 3)
  for (const n of notes) assert.equal(n.y, rowY)
  assert.equal(scene.shapes.filter((s) => s.cls === "dg-connector").length, 0)
  const mid = notes.find((n) => n.text_it === "zero")
  assert.ok(Math.abs(mid.x + mid.w / 2 - 195) <= 1, "centred on the zero")
})

test("random marks and labels: every drawing is either clear or an error, never a leader across a number", () => {
  let seed = 7
  const rnd = (n) => {
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n
  }
  const words = ["uno", "due passi", "arrivo a 3", "parti da qui", "Italia: B", "x", "a metà strada"]
  let drawn = 0
  for (let k = 0; k < 120; k++) {
    const min = -rnd(6)
    const max = min + 2 + rnd(9)
    const marks = []
    for (let i = 0, n = 2 + rnd(4); i < n; i++) marks.push([String(min + rnd(max - min + 1)), words[rnd(words.length)], ["dot", "open", "closed", "cross"][rnd(4)]])
    const data = line(String(min), String(max), marks, rnd(3) === 0 ? { jumps: [{ from: String(min), by: "1", label_it: "+1" }] } : {})
    const width = WIDTHS[rnd(4)]
    const fontPx = SIZES[rnd(3)]
    const scene = layout(data, { width, fontPx, subject: "math" })
    if (scene.error) {
      assert.equal(scene.error.code, "E-DIAGRAM-LAYOUT", scene.error.message)
      continue
    }
    drawn++
    assertClear(scene, `${JSON.stringify(marks)} ${width}/${fontPx}`)
  }
  assert.ok(drawn > 80, `most drawings are possible (${drawn} of 120)`)
})
