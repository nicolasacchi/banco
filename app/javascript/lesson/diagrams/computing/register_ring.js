// The ring view of register (T9): every code of 3 or 4 bits on a circle, clockwise from the top. The unsigned value is written outside,
// the signed one inside; a seam marks where the value jumps; the pointer moves round the circle; an arc along the ring is a move whose
// landing code is computed. The codes themselves are read off the pointer, the highlights and the legend (16 of them would not fit round
// a phone-sized circle at the student's text size).
import { effectiveState, finish, label, plain, shape, stateCount } from "lesson/diagrams/common"
import { MINUS, show } from "lesson/diagrams/computing/bits_common"

export const ringCodes = (width) => Array.from({ length: 2 ** width }, (_, k) => k.toString(2).padStart(width, "0"))

const signedOf = (k, N) => (k < N / 2 ? k : k - N)
const codeOf = (k, n) => k.toString(2).padStart(n, "0")
const around = (cx, cy, r, k, N) => [cx + r * Math.cos(-Math.PI / 2 + (2 * Math.PI * k) / N), cy + r * Math.sin(-Math.PI / 2 + (2 * Math.PI * k) / N)]
const seamAngle = (k, N) => -Math.PI / 2 + (2 * Math.PI * (k - 0.5)) / N // between code k-1 and code k
const f2 = (v) => Math.round(v * 100) / 100

// The pointer's code number, with the stepper's moves (round the circle).
function pointerCode(eff, ctx) {
  if (eff.pointer === undefined) return null
  const N = 2 ** eff.width
  return ((parseInt(eff.pointer, 2) + (ctx.controls?.pointer ?? 0)) % N + N) % N
}

export function ringReadout(eff, k) {
  const N = 2 ** eff.width
  const read = eff.read ?? "unsigned"
  const parts = []
  if (read === "unsigned" || read === "both") parts.push(`senza segno ${k}`)
  if (read === "twos" || read === "both") parts.push(`con segno ${show(signedOf(k, N))}`)
  return parts.join(", ")
}

const landing = (m, N) => (((parseInt(m.from, 2) + m.by) % N) + N) % N

export function drawRing(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const n = eff.width
  const N = 2 ** n
  const read = eff.read ?? "unsigned"
  const showU = !select && (read === "unsigned" || read === "both")
  const showS = !select && (read === "twos" || read === "both")
  const f = ctx.fontPx
  const lineH = ctx.lineH
  const wU = ctx.measure(String(N - 1), f).w
  const margin = showU ? wU + 18 : 16
  const R = Math.max(56, Math.min(150, Math.floor((ctx.width - 2 * margin) / 2)))
  const top = showU ? lineH + 16 : 16
  const cx = Math.round(ctx.width / 2)
  const cy = top + R
  const point = select ? null : pointerCode(eff, ctx)
  const highlights = select ? [] : (eff.highlight ?? []).map((h) => ({ ...h, k: parseInt(h.code, 2) }))
  const moves = select ? [] : (eff.moves ?? []).map((m) => ({ ...m, k: parseInt(m.from, 2), to: landing(m, N) }))
  const targets = []

  // the circle, the seams, the moves, the pointer
  shape(ctx, "circle", { cx, cy, r: R, cls: "dg-ringpath" })
  if (eff.cliff && !select) {
    const seams = []
    if (showU) seams.push(0)
    if (showS) seams.push(N / 2)
    for (const k of seams) {
      const a = seamAngle(k, N)
      shape(ctx, "line", { x1: f2(cx + (R - 16) * Math.cos(a)), y1: f2(cy + (R - 16) * Math.sin(a)), x2: f2(cx + (R + 16) * Math.cos(a)), y2: f2(cy + (R + 16) * Math.sin(a)), cls: "dg-cliff" })
    }
  }
  for (const m of moves) {
    const [x1, y1] = around(cx, cy, R, m.k, N)
    const [x2, y2] = around(cx, cy, R, m.to, N)
    const forward = m.by >= 0
    const steps = Math.abs(m.by)
    const large = steps > N / 2 ? 1 : 0
    const role = m.role ?? "carry"
    if (steps > 0) {
      shape(ctx, "path", { d: `M${f2(x1)},${f2(y1)} A${R},${R} 0 ${large} ${forward ? 1 : 0} ${f2(x2)},${f2(y2)}`, cls: `dg-arc st-${role}` })
      // an arrowhead at the landing, pointing along the ring
      const a = -Math.PI / 2 + (2 * Math.PI * m.to) / N
      const dir = forward ? 1 : -1
      const tx = -Math.sin(a) * dir
      const ty = Math.cos(a) * dir
      const nx = Math.cos(a)
      const ny = Math.sin(a)
      const tip = [x2 + tx * 12, y2 + ty * 12]
      shape(ctx, "polygon", { points: [tip, [x2 + nx * 8, y2 + ny * 8], [x2 - nx * 8, y2 - ny * 8]].map((p) => p.map(f2)), cls: `mk-${role}` })
    }
  }
  if (point !== null) {
    const [px, py] = around(cx, cy, R, point, N)
    shape(ctx, "circle", { cx: f2(px), cy: f2(py), r: 17, cls: "dg-pointer-ring st-reference" })
  }
  for (const h of highlights) {
    const [hx, hy] = around(cx, cy, R, h.k, N)
    shape(ctx, "circle", { cx: f2(hx), cy: f2(hy), r: 13, cls: "dg-highlight-ring" })
  }
  // the nodes: the codes that start with 1 are filled
  for (let k = 0; k < N; k++) {
    const [x, y] = around(cx, cy, R, k, N)
    const s = shape(ctx, "circle", { cx: f2(x), cy: f2(y), r: select ? 11 : 8, cls: `dg-codenode${k >= N / 2 ? " dg-on" : ""}${point === k ? " mk-reference" : ""}` })
    if (select) {
      s.target = `t${k + 1}`
      targets.push({ target: `t${k + 1}`, bbox: { x: f2(x - 14), y: f2(y - 14), w: 28, h: 28 } })
    }
  }

  // the numbers, in order of importance; a label that would touch one already placed is left out
  if (showU || showS) {
    const placed = []
    const forced = new Set([0, N - 1, N / 2 - 1, N / 2])
    for (const h of highlights) forced.add(h.k)
    for (const m of moves) {
      forced.add(m.k)
      forced.add(m.to)
    }
    if (point !== null) forced.add(point)
    const order = [...Array(N).keys()].sort((a, b) => Number(forced.has(b)) - Number(forced.has(a)) || a - b)
    const free = (box) => placed.every((p) => box.x + box.w + 4 <= p.x || p.x + p.w + 4 <= box.x || box.y + box.h + 2 <= p.y || p.y + p.h + 2 <= box.y)
    for (const k of order) {
      for (const [on, text, outside] of [[showU, String(k), true], [showS, show(signedOf(k, N)), false]]) {
        if (!on) continue
        const m = ctx.measure(text, f)
        const a = -Math.PI / 2 + (2 * Math.PI * k) / N
        const ext = Math.abs(Math.cos(a)) * m.w / 2 + Math.abs(Math.sin(a)) * m.h / 2
        const r = outside ? R + 14 + ext : R - 14 - ext
        const [lx, ly] = around(cx, cy, r, k, N)
        const box = { x: Math.round(lx - m.w / 2), y: Math.round(ly - m.h / 2), w: m.w, h: m.h }
        if (box.x < 0 || box.x + box.w > ctx.width || box.y < 0) continue
        if (!free(box)) continue
        placed.push(box)
        label(ctx, text, lx, ly, { valign: "middle", cls: `dg-ringnum ${outside ? "dg-ringnum-out" : "dg-ringnum-in"}${forced.has(k) ? " dg-forced" : ""}` })
      }
    }
  }

  // below the ring: what the pointer says, the highlights, the moves, the seam
  let y = cy + R + (showU ? lineH + 16 : 16) + 4
  const lines = []
  if (!select) {
    if (point !== null) lines.push({ text: `Puntatore ${codeOf(point, n)}: ${ringReadout(eff, point)}`, cls: "dg-readout-line", marker: "reference" })
    for (const h of highlights) lines.push({ text: `${h.code}: ${h.label_it ?? ringReadout(eff, h.k)}`, cls: "dg-legend", marker: "highlight" })
    for (const m of moves) lines.push({ text: `${m.label_it ? `${plain(m.label_it)}: ` : ""}${m.from} arriva a ${codeOf(m.to, n)} (${ringReadout(eff, m.to)})`, cls: "dg-legend", marker: `move-${m.role ?? "carry"}` })
    if (eff.cliff) {
      if (showS) lines.push({ text: `Il salto: da ${codeOf(N / 2 - 1, n)} a ${codeOf(N / 2, n)}, cioè da ${N / 2 - 1} a ${MINUS}${N / 2}`, cls: "dg-legend", marker: "cliff" })
      if (showU) lines.push({ text: `Il salto: da ${codeOf(N - 1, n)} a ${codeOf(0, n)}, cioè da ${N - 1} a 0`, cls: "dg-legend", marker: "cliff" })
    }
  }
  const pad = Math.max(8, Math.round((ctx.width - Math.min(ctx.width - 16, 440)) / 2))
  for (const line of lines) {
    const mark = 22
    const item = label(ctx, line.text, pad + mark, y, { anchor: "start", cls: line.cls, maxW: ctx.width - pad * 2 - mark })
    const cyl = y + Math.min(item.h, lineH) / 2
    if (line.marker === "reference") shape(ctx, "circle", { cx: pad + 8, cy: cyl, r: 7, cls: "dg-pointer-ring st-reference" })
    else if (line.marker === "highlight") shape(ctx, "circle", { cx: pad + 8, cy: cyl, r: 7, cls: "dg-highlight-ring" })
    else if (line.marker === "cliff") shape(ctx, "line", { x1: pad + 8, y1: cyl - 8, x2: pad + 8, y2: cyl + 8, cls: "dg-cliff" })
    else shape(ctx, "line", { x1: pad + 1, y1: cyl, x2: pad + 15, y2: cyl, cls: `dg-arc st-${line.marker.replace("move-", "")}` })
    y += item.h + 6
  }
  const out = finish(ctx, y + 2, { states: stateCount(data), state: ctx.state })
  if (!out.error) {
    out.controls = {}
    out.live = point !== null ? `Il puntatore è su ${codeOf(point, n)}: ${ringReadout(eff, point)}.` : `Una ruota di ${N} codici di ${n} bit.`
    if (select) out.targets = targets
  }
  return out
}

export function ringDescribe(eff, ctx) {
  const n = eff.width
  const N = 2 ** n
  const read = eff.read ?? "unsigned"
  const bits = [`Una ruota con tutti i ${N} codici di ${n} bit, da ${codeOf(0, n)} a ${codeOf(N - 1, n)}, in senso orario dall'alto.`]
  if (read === "unsigned" || read === "both") bits.push(`Fuori c'è il valore senza segno, da 0 a ${N - 1}.`)
  if (read === "twos" || read === "both") bits.push(`${read === "both" ? "Dentro" : "Sulla ruota"} c'è il valore con segno, da ${MINUS}${N / 2} a ${N / 2 - 1}.`)
  if (eff.cliff) {
    if (read !== "unsigned") bits.push(`Il valore con segno salta tra ${codeOf(N / 2 - 1, n)} e ${codeOf(N / 2, n)}.`)
    if (read !== "twos") bits.push(`Il valore senza segno salta tra ${codeOf(N - 1, n)} e ${codeOf(0, n)}.`)
  }
  const point = pointerCode(eff, ctx ?? {})
  if (point !== null) bits.push(`Il puntatore è su ${codeOf(point, n)}: ${ringReadout(eff, point)}.`)
  for (const h of eff.highlight ?? []) bits.push(`Il codice ${h.code} è segnato${h.label_it ? `: ${plain(h.label_it)}` : ""}.`)
  for (const m of eff.moves ?? []) bits.push(`Da ${m.from} ${m.by >= 0 ? "avanti" : "indietro"} di ${Math.abs(m.by)} si arriva a ${codeOf(landing(m, N), n)}, che vale ${ringReadout(eff, landing(m, N))}.`)
  return bits.join(" ")
}

// Every string the state prints (L4): the codes of the pointer, the highlights and the landings, the numbers on the ring, the labels.
export function ringPrinted(eff) {
  const n = eff.width
  const N = 2 ** n
  const read = eff.read ?? "unsigned"
  const out = new Set()
  for (let k = 0; k < N; k++) {
    if (read === "unsigned" || read === "both") out.add(String(k))
    if (read === "twos" || read === "both") out.add(show(signedOf(k, N)))
  }
  if (eff.pointer !== undefined) out.add(eff.pointer)
  for (const h of eff.highlight ?? []) {
    out.add(h.code)
    if (h.label_it) out.add(h.label_it)
  }
  for (const m of eff.moves ?? []) {
    out.add(codeOf(landing(m, N), n))
    out.add(m.from)
    if (m.label_it) out.add(m.label_it)
  }
  return [...out]
}
