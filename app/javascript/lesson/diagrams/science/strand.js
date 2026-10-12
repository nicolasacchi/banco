// strand (WAVE2 2.8, biology.md 2.2; T7): a nucleotide (phosphate, sugar, base), a single strand or a double strand drawn as a ladder; horizontal when the
// positions fit the width, vertical (two columns, rungs across) when they do not. The pairs are coloured, shaped (angular A and T, rounded C and G) and
// drawn with two or three rungs; the shapes are a memory aid. A position hidden in every state arrives with a placeholder letter, never the complement.
// The Ruby twin is Lessons::Diagrams::Strand (the semantic checks run in the same order); both run test/fixtures/diagrams/types/strand.json.
import schema from "lesson/diagram_schemas/strand"
import { effectiveState, finish, label, listIt, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "strand"
export { schema }

const COMPLEMENT = { A: "T", T: "A", C: "G", G: "C" }
const NAMES = { A: "adenina", C: "citosina", G: "guanina", T: "timina", U: "uracile" }
const PARTS = { phosphate: "fosfato", sugar: "zucchero", base: "base azotata" }
const PAIR_NOTE = "Le forme aiutano a ricordare: le vere basi sono molecole."
const isAT = (ch) => ch === "A" || ch === "T" || ch === "U"

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::Strand) -------------------------------------------------------

function staticProblem(data) {
  const rna = data.kind === "rna"
  const bad = [...data.top].findIndex((ch) => (rna ? ch === "T" : ch === "U"))
  if (bad >= 0) return { path: "/top", message: `${rna ? "RNA has U, not T" : "DNA has T, not U"}: position ${bad + 1} of top` }
  if (data.mode === "nucleotide") {
    if (data.top.length !== 1) return { path: "/top", message: `a nucleotide has one base: top has ${data.top.length}` }
    if (data.bottom !== undefined) return { path: "/bottom", message: "a nucleotide has no bottom strand" }
  } else if (data.mode === "single") {
    if (data.bottom !== undefined) return { path: "/bottom", message: "a single strand has no bottom strand" }
  } else {
    if (rna) return { path: "/kind", message: "an RNA double strand is not drawn yet: it waits for transcription" }
    if (data.bottom === undefined) return { path: "/bottom", message: "a double strand needs bottom" }
    if (data.bottom.length !== data.top.length) return { path: "/bottom", message: `bottom has ${data.bottom.length} bases, top ${data.top.length}` }
    // a position hidden in every state carries a placeholder when served: only the others are held to the complement
    const hidden = alwaysHidden(data)
    const wrong = [...data.top].findIndex((ch, i) => !hidden.includes(i + 1) && COMPLEMENT[ch] !== data.bottom[i])
    if (wrong >= 0) return { path: "/bottom", message: `position ${wrong + 1} of bottom is not the complement of ${data.top[wrong]}: A pairs with T, C with G` }
  }
  return null
}

function stateProblem(eff, path) {
  const hide = eff.hide_bottom ?? []
  for (let i = 0; i < hide.length; i++) {
    if (eff.mode !== "double") return { path: `${path}/hide_bottom`, message: "hide_bottom is for a double strand" }
    if (hide[i] > eff.top.length) return { path: `${path}/hide_bottom/${i}`, message: `position ${hide[i]} is past the last base (${eff.top.length})` }
  }
  if (eff.unzip && eff.mode !== "double") return { path: `${path}/unzip`, message: "unzip is for a double strand" }
  const letters = eff.kind === "rna" ? ["A", "C", "G", "U"] : ["A", "C", "G", "T"]
  const marks = eff.highlight ?? []
  for (let i = 0; i < marks.length; i++) if (!letters.includes(marks[i])) return { path: `${path}/highlight/${i}`, message: `${marks[i]} is not a base of ${eff.kind.toUpperCase()} (${letters.join(", ")})` }
  return null
}

// The positions (1-based) hidden in every state.
function alwaysHidden(data) {
  const n = stateCount(data)
  let hidden = null
  for (let i = 0; i < n; i++) {
    const list = effectiveState(data, i).hide_bottom ?? []
    hidden = hidden === null ? list : hidden.filter((p) => list.includes(p))
  }
  return hidden ?? []
}

export function semantic(data) {
  const top = staticProblem(data)
  if (top) return top
  const count = stateCount(data)
  for (let i = 0; i < count; i++) {
    const found = stateProblem(effectiveState(data, i), data.states?.length ? `/states/${i}` : "")
    if (found) return found
  }
  return null
}

// ---- layout -----------------------------------------------------------------------------------------------------------------------------

const labelsOf = (eff) => eff.labels ?? (eff.mode === "nucleotide" ? "parts" : "none")

// A shape's points in strand space (u along the strand, v across it) mapped to the page: horizontal u = x, v = y; vertical u = y, v = x.
function mapper(vertical, ox = 0, oy = 0) {
  return (u, v) => (vertical ? [ox + v, oy + u] : [ox + u, oy + v])
}

function baseShape(ctx, P, ch, uc, vc, a, b, cls, extra = {}) {
  // a along the strand, b across it, centred on (uc, vc)
  const [cx, cy] = P(uc, vc)
  const w = ctx.vertical ? b : a
  const h = ctx.vertical ? a : b
  if (extra.neutral || extra.empty) return shape(ctx, "rect", { x: cx - w / 2, y: cy - h / 2, w, h, r: 8, cls, ...extra.attrs })
  if (isAT(ch)) {
    const c = Math.round(Math.min(w, h) * 0.28)
    const pts = [[cx - w / 2 + c, cy - h / 2], [cx + w / 2 - c, cy - h / 2], [cx + w / 2, cy - h / 2 + c], [cx + w / 2, cy + h / 2 - c], [cx + w / 2 - c, cy + h / 2], [cx - w / 2 + c, cy + h / 2], [cx - w / 2, cy + h / 2 - c], [cx - w / 2, cy - h / 2 + c]]
    return shape(ctx, "polygon", { points: pts, cls, ...extra.attrs })
  }
  return shape(ctx, "rect", { x: cx - w / 2, y: cy - h / 2, w, h, r: Math.round(Math.min(w, h) / 2), cls, ...extra.attrs })
}

function pentagon(ctx, P, uc, vc, s, up, cls) {
  // points a pentagon whose point faces the bases (up: -v when `up` is false the point faces +v)
  const dir = up ? 1 : -1
  const pts = [[0, -0.5], [0.5, -0.12], [0.31, 0.5], [-0.31, 0.5], [-0.5, -0.12]].map(([du, dv]) => P(uc + du * s, vc - dir * dv * s))
  return shape(ctx, "polygon", { points: pts, cls })
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const set = ctx.set ?? "bases"
  const F = ctx.fontPx
  const n = eff.top.length
  const double = eff.mode === "double"
  const nucleotide = eff.mode === "nucleotide"
  const hidden = new Set(eff.hide_bottom ?? [])
  const labels = select ? "none" : labelsOf(eff)
  const lit = new Set()
  const controls = {}
  const targets = []
  // sizes
  const bw0 = Math.max(34, Math.round(F * 1.7))
  const room = ctx.width - 8
  const vertical = !nucleotide && n * (bw0 + 14) + 4 > room
  // a short strand on a wide page grows (up to 1.7 times) instead of floating small in the middle of the room
  const k = vertical || nucleotide ? 1 : Math.min(1.7, Math.max(1, (room - 6) / n / (bw0 + 14)))
  const bw = Math.round(bw0 * k) // along the strand
  const bh = Math.round(bw0 * k) // across
  const sh = Math.round(F * 1.0 * k) // sugar
  const ph = Math.round(F * 0.8 * k) // phosphate
  const colW = bw + 14
  ctx.vertical = vertical
  const gap = eff.unzip ? Math.round(F * 3.2) : Math.round(F * 1.7)
  const sc = nucleotide ? 1.5 : 1
  const mark = (ctrl) => Boolean(ctx.controls?.[ctrl])
  // across the strands: top backbone, top base, gap, bottom base, bottom backbone
  const vB1 = Math.round(sh * sc / 2) + 6
  const vT0 = vB1 + Math.round(sh * sc / 2) + 4
  const vT = vT0 + Math.round(bh * sc / 2)
  const vTbottom = vT0 + Math.round(bh * sc)
  const vU = vTbottom + gap + Math.round(bh / 2)
  const vUtop = vTbottom + gap
  const vB2 = vUtop + bh + 4 + Math.round(sh / 2)
  const across = double ? vB2 + Math.round(sh / 2) + 6 : vTbottom + 4
  const along = nucleotide ? Math.round(bw * sc * 3) : n * colW + (vertical ? 0 : 6)
  // the width of the drawing
  const W = vertical ? across : along
  const ox = vertical ? Math.max(0, Math.round((ctx.width - W) / 2)) : Math.max(0, Math.round((ctx.width - W) / 2))
  const P = mapper(vertical, ox, 2)
  const u0 = nucleotide ? Math.round(bw * sc) : 3
  const ucol = (i) => u0 + i * colW + colW / 2 + (nucleotide ? Math.round(bw * sc * 0.4) : 0)
  // which pairs are lit by a tap
  const topChars = [...eff.top]
  const botChars = double ? [...eff.bottom] : []
  if (double && !select) {
    for (let i = 0; i < n; i++) {
      if (mark(`top-${i}`) || (!hidden.has(i + 1) && mark(`bottom-${i}`))) lit.add(i)
    }
  }
  // backbones first
  const rail = (v) => {
    const [x1, y1] = P(u0 - (nucleotide ? 0 : 2), v)
    const [x2, y2] = P(nucleotide ? ucol(0) : u0 + n * colW + 2, v)
    shape(ctx, "line", { x1, y1, x2, y2, cls: "dg-backbone" })
  }
  if (!nucleotide) {
    rail(vB1)
    if (double) rail(vB2)
  } else {
    const [x1, y1] = P(ucol(0) - Math.round(bw * sc * 0.9), vB1)
    const [x2, y2] = P(ucol(0), vB1)
    shape(ctx, "line", { x1, y1, x2, y2, cls: "dg-backbone" })
    const [x3, y3] = P(ucol(0), vB1)
    const [x4, y4] = P(ucol(0), vT0)
    shape(ctx, "line", { x1: x3, y1: y3, x2: x4, y2: y4, cls: "dg-backbone" })
  }
  const parts = []
  const addTarget = (id, bbox, s) => {
    const t = `t${targets.length + 1}`
    s.target = t
    targets.push({ target: t, id, bbox })
  }
  // the rungs, then the bases, then the sugars and phosphates over the rails
  if (double) {
    for (let i = 0; i < n; i++) {
      const uc = ucol(i)
      const isHidden = hidden.has(i + 1)
      if (!isHidden && !eff.unzip && !select) {
        const count = isAT(topChars[i]) ? 2 : 3
        for (let k = 0; k < count; k++) {
          const off = (k - (count - 1) / 2) * 9
          const [x1, y1] = P(uc + off, vTbottom + 2)
          const [x2, y2] = P(uc + off, vUtop - 2)
          shape(ctx, "line", { x1, y1, x2, y2, cls: `dg-rung${lit.has(i) ? " dg-rung-lit" : ""}` })
        }
      }
      if (select && set === "rungs") {
        const [x, y] = P(uc - bw / 2, vTbottom)
        const w = vertical ? gap : bw
        const h = vertical ? bw : gap
        const bx = vertical ? P(uc - bw / 2, vTbottom)[0] : x
        const rect = shape(ctx, "rect", { x: bx, y: vertical ? y : y, w: Math.max(w, 24), h: Math.max(h, 24), r: 6, cls: "dg-piece" })
        addTarget(`r${i + 1}`, { x: rect.x, y: rect.y, w: rect.w, h: rect.h }, rect)
      }
    }
  }
  const drawBase = (ch, i, strandTop) => {
    const uc = ucol(i)
    const vc = strandTop ? vT : vU
    const isEmpty = !strandTop && hidden.has(i + 1)
    const neutral = select
    const cls = isEmpty ? "dg-sbase dg-sempty" : neutral ? "dg-sbase dg-neutral" : `dg-sbase ${isAT(ch) ? "dg-sbase-at" : "dg-sbase-cg"}`
    const s = baseShape(ctx, P, ch, uc, vc, nucleotide ? bw * sc : bw, nucleotide ? bh * sc : bh, cls, { neutral, empty: isEmpty })
    const [cx, cy] = P(uc, vc)
    const w = vertical ? (nucleotide ? bh * sc : bh) : (nucleotide ? bw * sc : bw)
    const h = vertical ? (nucleotide ? bw * sc : bw) : (nucleotide ? bh * sc : bh)
    if (!isEmpty) label(ctx, ch, cx, cy, { anchor: "middle", valign: "middle", cls: "dg-sletter", px: nucleotide ? Math.round(F * 1.4) : F })
    const marked = !select && (eff.highlight ?? []).includes(ch) && !isEmpty
    if (marked) shape(ctx, "rect", { x: cx - w / 2 - 4, y: cy - h / 2 - 4, w: w + 8, h: h + 8, r: 10, cls: "dg-shl" })
    if (lit.has(i) && !select) shape(ctx, "rect", { x: cx - w / 2 - 4, y: cy - h / 2 - 4, w: w + 8, h: h + 8, r: 10, cls: "dg-slit" })
    if (select && set === "bases") addTarget(`${strandTop ? "top" : "bot"}${i + 1}`, { x: cx - w / 2, y: cy - h / 2, w, h }, s)
    if (double && !select && !isEmpty) {
      const ctrl = `${strandTop ? "top" : "bottom"}-${i}`
      controls[ctrl] = { x: cx - w / 2, y: cy - h / 2, w, h, on: mark(ctrl), label_it: `Base ${ch}, posizione ${i + 1} ${strandTop ? "sopra" : "sotto"}: tocca per accendere la compagna` }
    }
    return { cx, cy }
  }
  for (let i = 0; i < n; i++) {
    drawBase(topChars[i], i, true)
    if (double) drawBase(botChars[i], i, false)
  }
  // the sugars and phosphates
  const ps = []
  for (let i = 0; i < n; i++) {
    const uc = ucol(i)
    const sp = pentagon(ctx, P, uc, vB1, sh * sc, true, "dg-sugar")
    const [pcx, pcy] = P(nucleotide ? u0 : uc - colW / 2, vB1)
    const pc = shape(ctx, "circle", { cx: pcx, cy: pcy, r: Math.round(ph * sc / 2), cls: "dg-phosphate" })
    if (select && nucleotide && set === "backbone") {
      addTarget("phosphate", { x: pcx - ph, y: pcy - ph, w: 2 * ph, h: 2 * ph }, pc)
      const [sx, sy] = P(uc, vB1)
      addTarget("sugar", { x: sx - sh, y: sy - sh, w: 2 * sh, h: 2 * sh }, sp)
    }
    if (double) {
      pentagon(ctx, P, uc, vB2, sh, false, "dg-sugar")
      const [qx, qy] = P(uc - colW / 2, vB2)
      shape(ctx, "circle", { cx: qx, cy: qy, r: Math.round(ph / 2), cls: "dg-phosphate" })
    }
    ps.push(pc)
  }
  if (select && set === "backbone" && !nucleotide) {
    const band = (v, id) => {
      const [x1, y1] = P(u0, v - sh / 2 - 2)
      const w = vertical ? sh + 4 : n * colW
      const h = vertical ? n * colW : sh + 4
      const rect = shape(ctx, "rect", { x: x1, y: y1, w: Math.max(w, 24), h: Math.max(h, 24), r: 8, cls: "dg-piece" })
      addTarget(id, { x: rect.x, y: rect.y, w: rect.w, h: rect.h }, rect)
    }
    band(vB1, "top")
    if (double) band(vB2, "bot")
  }
  // key and notes under the drawing
  let y = (vertical ? n * colW + 4 : across) + 6
  const room2 = ctx.width - 6
  const row = (markerShape, cls, text) => {
    shape(ctx, "marker", { shape: markerShape, x: 2, y: y + Math.round((ctx.lineH - 18) / 2), w: 18, h: 18, cls })
    label(ctx, text, 28, y, { anchor: "start", cls: "dg-keytext", maxW: room2 - 28 })
    y += Math.max(ctx.measure(text, F, room2 - 28).h, ctx.lineH) + 4
  }
  const visibleLetters = [...topChars, ...(double ? botChars.filter((_, i) => !hidden.has(i + 1)) : [])]
  if (!select) {
    if (labels === "parts") {
      row("circle", "mk-phosphate", PARTS.phosphate)
      row("pentagon", "mk-sugar", PARTS.sugar)
      row("box", "mk-base", PARTS.base)
    }
    if (labels === "bases") {
      const names = [...new Set(visibleLetters)].map((ch) => `${ch} ${NAMES[ch]}`)
      label(ctx, names.join(" · "), 2, y, { anchor: "start", cls: "dg-keytext", maxW: room2 })
      y += ctx.measure(names.join(" · "), F, room2).h + 4
    }
    if (double && labels !== "none") {
      row("diamond", "mk-pair_at", "coppia A-T")
      row("triangle", "mk-pair_cg", "coppia C-G")
      label(ctx, PAIR_NOTE, 2, y, { anchor: "start", cls: "dg-hint", maxW: room2 })
      y += ctx.measure(PAIR_NOTE, F, room2).h + 4
    }
    if ((eff.highlight ?? []).length) {
      const counts = eff.highlight.map((ch) => `${ch} ${visibleLetters.filter((x) => x === ch).length}`)
      label(ctx, counts.join(" · "), 2, y, { anchor: "start", cls: "dg-count" })
      y += ctx.lineH + 4
    }
  }
  const out = finish(ctx, y + 4, { states: stateCount(data), state: ctx.state })
  if (out.error) return out
  if (select) out.targets = targets.map(({ target, bbox }) => ({ target, bbox }))
  else {
    out.controls = controls
    if (lit.size) out.live = `Evidenziata la coppia ${[...lit].map((i) => i + 1).join(", ")}.`
  }
  return out
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- controls, description, targets, printed -----------------------------------------------------------------------------------------------

// Tap a base: its partner lights. The boxes are the visible bases (the scene gives a box to those only).
export function controls(data) {
  if (data.mode !== "double") return []
  const list = []
  for (let i = 0; i < data.top.length; i++) {
    list.push({ id: `top-${i}`, kind: "toggle", label_it: "Basi del filamento di sopra" })
    list.push({ id: `bottom-${i}`, kind: "toggle", label_it: "Basi del filamento di sotto" })
  }
  return list
}

function describeState(data, i) {
  const eff = effectiveState(data, i)
  const hidden = eff.hide_bottom ?? []
  const spell = (s) => [...s].join(", ")
  const out = []
  if (eff.mode === "nucleotide") out.push(`Un nucleotide: un fosfato, uno zucchero e la base ${eff.top}.`)
  else out.push(`Un filamento di ${eff.top.length} basi${eff.kind === "rna" ? " di RNA" : ""}: ${spell(eff.top)}, da sinistra a destra.`)
  if (eff.mode === "double") {
    const shown = [...eff.bottom].map((ch, k) => (hidden.includes(k + 1) ? null : `${k + 1} ${ch}`)).filter(Boolean)
    if (hidden.length === 0) out.push(`Sotto, il filamento complementare: ${spell(eff.bottom)}. A sta con T con due legami, C con G con tre.`)
    else out.push(`Del filamento di sotto si vedono ${shown.length ? listIt(shown.map((s) => `la base ${s}`)) : "nessuna base"}; le altre sono nascoste.`)
    if (eff.unzip) out.push("I due filamenti sono separati.")
  }
  const letters = [...eff.top, ...(eff.mode === "double" ? [...eff.bottom].filter((_, k) => !hidden.includes(k + 1)) : [])]
  if ((eff.highlight ?? []).length) out.push(`Evidenziate: ${listIt(eff.highlight.map((ch) => `${letters.filter((x) => x === ch).length} ${ch}`))}.`)
  return out.join(" ")
}

export function describe(data, ctx) {
  const single = ctx?.state
  const count = stateCount(data)
  const one = (i) => `${count > 1 ? `Passo ${i + 1}. ${data.states[i]?.op_it ? `${data.states[i].op_it}. ` : ""}` : ""}${describeState(data, i)}`
  if (single !== undefined || count === 1) return one(Math.min(single ?? 0, count - 1))
  return Array.from({ length: count }, (_, i) => one(i)).join(" ")
}

export function targetIds(data, set) {
  const n = data.top.length
  if (set === "bases") return [...Array.from({ length: n }, (_, i) => `top${i + 1}`), ...(data.mode === "double" ? Array.from({ length: n }, (_, i) => `bot${i + 1}`) : [])]
  if (set === "backbone") return data.mode === "nucleotide" ? ["phosphate", "sugar"] : data.mode === "double" ? ["top", "bot"] : ["top"]
  if (set === "rungs") return data.mode === "double" ? Array.from({ length: n }, (_, i) => `r${i + 1}`) : []
  return []
}

// targets(data, set) -> [{ key, bbox, neutral_it }]
export function targets(data, set, opts = {}) {
  const ids = targetIds(data, set)
  if (ids.length === 0) return []
  const scene = layout(data, { width: 360, fontPx: 20, subject: "biology", ...opts, mode: "select", set, state: 0 })
  if (scene.error) return []
  const noun = set === "bases" ? "Base" : set === "rungs" ? "Piolo" : "Parte"
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `${noun} ${i + 1} di ${ids.length}` }))
}

// Every string the state prints (L4); Ruby's printed() returns the same set.
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const labels = labelsOf(eff)
  const hidden = eff.hide_bottom ?? []
  const out = new Set([...eff.top])
  if (eff.mode === "double") [...eff.bottom].forEach((ch, i) => { if (!hidden.includes(i + 1)) out.add(ch) })
  const visible = [...eff.top, ...(eff.mode === "double" ? [...eff.bottom].filter((_, i) => !hidden.includes(i + 1)) : [])]
  if (labels === "parts") for (const w of Object.values(PARTS)) out.add(w)
  if (labels === "bases") for (const ch of new Set(visible)) out.add(NAMES[ch])
  if (eff.mode === "double" && labels !== "none") {
    out.add("coppia A-T")
    out.add("coppia C-G")
    out.add(PAIR_NOTE)
  }
  for (const ch of eff.highlight ?? []) out.add(`${ch} ${visible.filter((x) => x === ch).length}`)
  const op = data.states?.[state]?.op_it
  if (op) out.add(op)
  return [...out]
}
