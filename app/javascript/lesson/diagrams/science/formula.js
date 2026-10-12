// formula (WAVE2 2.8, chemistry.md 2.4; T7): the formula decoder. The formulas are read by lesson/lib/chem (case-exact, one level of brackets); the
// pieces, their labels, the arrows from a subscript back to its symbol, the count table and the molecules are ours: the author never writes a count.
// The Ruby twin is Lessons::Diagrams::Formula (the semantic checks run in the same order); both run test/fixtures/diagrams/types/formula.json.
import schema from "lesson/diagram_schemas/formula"
import * as Chem from "lesson/lib/chem"
import { effectiveState, finish, label, listIt, plain, shape, stateCount } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { PATCH_UNITS, atomsDrawn, atomsPhrase, countRows, elementName, mergeSub, pieces as piecesOf, quantityPhrase, rowOfFormula, unitsFit } from "lesson/diagrams/science/common"
import { drawMolecule, drawPatch, patchPose, pose } from "lesson/diagrams/science/molecule_draw"

export const type = "formula"
export { schema }

const MAX_ATOMS = 30 // lesson2.types.formula.atoms_drawn in validation_rules.yml
const WORDS = { coefficient: "coefficiente", symbol: "simbolo", subscript: "pedice", group: "pacchetto" }
const HINTS = { coefficient: "quante volte tutta la formula", symbol: "il tipo di atomo", subscript: "quanti atomi: conta quello prima", group: "si ripete tutto insieme" }

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::Formula) --------------------------------------------------------

function staticProblem(data) {
  for (let i = 0; i < data.formulas.length; i++) {
    const f = data.formulas[i]
    if (Chem.parse(f)) continue
    const bad = Chem.unknownSymbol(f)
    if (bad) return { path: `/formulas/${i}`, message: `${bad} is not the symbol of an element (symbols are case-exact: Cl, not CL)`, code: "E-CHEM-SYMBOL" }
    return { path: `/formulas/${i}`, message: `${JSON.stringify(f)} is not a formula the grammar reads (a coefficient 2 to 20, subscripts 2 to 99, one level of brackets, a state (s) (l) (g) (aq))` }
  }
  return null
}

function stateProblem(eff, path) {
  if (eff.formulas.some((f) => Chem.parse(f) === null)) return null // reported once, by the static check
  const show = eff.show ?? ["parts"]
  if (show.includes("molecules")) {
    for (let i = 0; i < eff.formulas.length; i++) {
      const row = rowOfFormula(eff.formulas[i])
      if (!row) return { path: `${path}/show`, message: `molecules draws library formulas only: ${JSON.stringify(eff.formulas[i])} (formulas[${i}]) is not in chem/molecules`, code: "E-LESSON-DATA" }
      if (!unitsFit(row, Chem.parse(eff.formulas[i]).coefficient)) return { path: `${path}/show`, message: `a salt or a metal is drawn as a patch with at most ${PATCH_UNITS} units framed: ${JSON.stringify(eff.formulas[i])} has a coefficient above that` }
    }
    const total = eff.formulas.reduce((s, f) => s + (atomsDrawn(f) ?? 0), 0)
    if (total > MAX_ATOMS) return { path: `${path}/show`, message: `molecules would draw ${total} atoms (at most ${MAX_ATOMS})` }
  }
  if (!eff.focus) return null
  if (!Chem.isSymbol(eff.focus)) return { path: `${path}/focus`, message: `${eff.focus} is not the symbol of an element`, code: "E-CHEM-SYMBOL" }
  if (!eff.formulas.some((f) => eff.focus in Chem.count(f))) return { path: `${path}/focus`, message: `focus ${eff.focus} is in none of the formulas` }
  return null
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

const subContext = (ctx, width) => ({ ...ctx, width, shapes: [], labels: [] })

// The right edge of what a sub context drew (labels and the shapes with a size).
function extent(sub) {
  let right = 0
  for (const l of sub.labels) right = Math.max(right, l.x + l.w)
  for (const s of sub.shapes) {
    if (s.kind === "rect") right = Math.max(right, s.x + s.w)
    else if (s.kind === "circle") right = Math.max(right, s.cx + s.r)
    else if (s.kind === "line") right = Math.max(right, s.x1, s.x2)
  }
  return Math.ceil(right)
}

const roleCls = (role) => `role-${role}`

// The large formula in one line at the size B: the pieces with their boxes (placed), the frames of the bracket groups and the right edge.
function buildRow(sub, parsed, items, B, yRow, select) {
  const F = sub.fontPx
  const placed = []
  const frames = []
  let x = 2
  // in select mode every piece gets a target of at least 24 px, so the pieces are spaced to keep the targets apart
  const put = (text, px, y, cls, role) => {
    const l = label(sub, text, x, y, { anchor: "start", px, cls, role })
    x += select ? Math.max(l.w, 28) + 8 : l.w
    return l
  }
  const subCls = select ? "dg-fsub" : "dg-fsub role-subscript"
  const subRole = select ? undefined : "subscript"
  const lower = yRow + Math.round(B * 0.78)
  let k = 0
  if (parsed.coefficient > 1) {
    const l = put(String(parsed.coefficient), B, yRow, select ? "dg-fbig" : "dg-fbig role-coefficient", select ? undefined : "coefficient")
    placed.push({ piece: items[k++], l, kind: "coefficient" })
    x += Math.round(B * 0.3)
  }
  for (const g of parsed.groups) {
    if (g.group) {
      const xOpen = x
      const open = put("(", B, yRow, "dg-fparen")
      for (const a of g.group) {
        const sy = put(a.symbol, B, yRow, "dg-fbig dg-fsym")
        placed.push({ piece: items[k++], l: sy, kind: "symbol", symbol: a.symbol, inGroup: true })
        if (a.count > 1) placed.push({ piece: items[k++], l: put(String(a.count), F, lower, subCls, subRole), kind: "subscript", of: sy, inGroup: true })
      }
      const close = put(")", B, yRow, "dg-fparen")
      const sbG = put(String(g.count), F, lower, subCls, subRole)
      placed.push({ piece: items[k++], l: sbG, kind: "subscript", ofGroup: true, frame: { x0: xOpen, x1: close.x + close.w, open: open.x + open.w / 2 } })
      frames.push({ x0: xOpen - 3, x1: sbG.x + sbG.w + 3 })
    } else {
      const sy = put(g.symbol, B, yRow, "dg-fbig dg-fsym")
      placed.push({ piece: items[k++], l: sy, kind: "symbol", symbol: g.symbol })
      if (g.count > 1) placed.push({ piece: items[k++], l: put(String(g.count), F, lower, subCls, subRole), kind: "subscript", of: sy })
    }
    x += Math.round(B * 0.08)
  }
  if (parsed.state) put(`(${parsed.state})`, F, yRow + Math.round(B * 0.5), "dg-fstate")
  return { placed, frames, right: x }
}

// One formula block: the large formula, its key and arrows, the count table and the molecules. Coordinates are local to the block.
function drawBlock(sub, block, eff, o) {
  const { parsed, f, i } = block
  const F = sub.fontPx
  const show = o.select ? ["parts"] : eff.show ?? ["parts"]
  const withParts = show.includes("parts") && !o.select
  const items = piecesOf(parsed)
  const hasSub = items.some((p) => p.kind === "subscript")
  const arrowH = withParts && hasSub ? Math.round(F * 1.4) : 0
  const yRow = arrowH + 4
  const targets = []
  // the largest size at which the formula fits the room: 2.2 times the text, down to 1.4 times
  let B = Math.max(40, Math.round(F * 2.2))
  for (; B > Math.round(F * 1.4); B -= 2) if (buildRow(subContext(sub, 4000), parsed, items, B, yRow, o.select).right <= sub.width - 4) break
  const lineB = Math.ceil(B * 1.4)
  const { placed, frames } = buildRow(sub, parsed, items, B, yRow, o.select)
  const subBottom = Math.max(0, ...placed.filter((p) => p.kind === "subscript").map((p) => p.l.y + p.l.h))
  const rowBottom = Math.max(yRow + lineB, subBottom)

  // the frames of the bracket groups sit behind the formula (drawn first)
  const behind = []
  for (const fr of frames) behind.push({ kind: "rect", x: fr.x0, y: yRow + 2, w: fr.x1 - fr.x0, h: lineB - 4, r: 10, cls: o.select ? "dg-neutral-frame" : "dg-gframe" })
  if (!o.select && eff.focus) {
    for (const p of placed) {
      if (p.kind === "symbol" && p.symbol === eff.focus) {
        const sbs = placed.find((q) => q.kind === "subscript" && q.of === p.l)
        const right = (sbs ? sbs.l : p.l).x + (sbs ? sbs.l : p.l).w
        behind.push({ kind: "rect", x: p.l.x - 4, y: yRow + 4, w: right - p.l.x + 8, h: lineB - 6, r: 8, cls: "dg-focus" })
      }
    }
  }
  // the select targets: a padded box on each piece, all alike
  let y = rowBottom + 4
  if (o.select) {
    placed.forEach((p, idx) => {
      const pad = 4
      const w = Math.max(24, p.l.w + 2 * pad)
      const h = Math.max(24, p.l.h + 2 * pad)
      const bx = p.l.x + p.l.w / 2 - w / 2
      const by = p.l.y + p.l.h / 2 - h / 2
      const t = `t${o.firstTarget + idx}`
      behind.push({ kind: "rect", x: bx, y: by, w, h, r: 8, cls: "dg-piece", target: t })
      targets.push({ target: t, id: `f${i + 1}p${idx + 1}`, bbox: { x: bx, y: by, w, h } })
    })
    sub.shapes.unshift(...behind)
    return { h: y + 4, targets }
  }
  sub.shapes.unshift(...behind)

  // arrows from a subscript back to the symbol (or the frame) it counts, above the formula
  if (withParts) {
    for (const p of placed) {
      if (p.kind !== "subscript") continue
      const from = p.l.x + p.l.w / 2
      const to = p.ofGroup ? p.frame.open : p.of.x + p.of.w / 2
      const top = yRow + 6
      const rise = Math.min(arrowH - 2, Math.round(F * 1.1))
      const sy = yRow + Math.round(B * 0.78)
      shape(sub, "path", { d: `M${from.toFixed(1)},${sy} C${from.toFixed(1)},${top - rise} ${to.toFixed(1)},${top - rise} ${to.toFixed(1)},${top + 2}`, cls: "dg-arrow" })
      shape(sub, "polygon", { points: [[to - 5, top - 2], [to + 5, top - 2], [to, top + 7]], cls: "dg-arrowhead" })
    }
  }

  // the key of the pieces: one row per kind, the piece as it is written in the formula (in its colour) and what it counts
  if (withParts) {
    const kinds = []
    for (const p of placed) {
      const kind = p.kind === "subscript" && p.ofGroup ? "group" : p.kind
      if (!kinds.some((k) => k.kind === kind)) kinds.push({ kind, sample: kind === "group" ? `(${parsed.groups.find((g) => g.group).group.map((a) => `${a.symbol}${a.count > 1 ? a.count : ""}`).join("")})` : p.l.text_it })
    }
    const sampleW = Math.max(...kinds.map((k) => sub.measure(k.sample, F).w)) + 18
    for (const k of kinds) {
      const role = k.kind === "symbol" ? null : k.kind
      const sampleCls = `dg-keysample${role ? ` role-${role}` : ""}${k.kind === "group" ? " dg-keygroup" : ""}`
      const text = role ? `[[${role}:${WORDS[k.kind]}]]: ${HINTS[k.kind]}` : `${WORDS[k.kind]}: ${HINTS[k.kind]}`
      const probe = sub.measure(text, F, Math.max(120, sub.width - sampleW - 6))
      label(sub, k.sample, 2, y + Math.max(0, Math.round((probe.h - sub.lineH) / 2)), { anchor: "start", cls: sampleCls, role: role ?? undefined })
      label(sub, text, 2 + sampleW, y, { anchor: "start", cls: "dg-keytext", maxW: Math.max(120, sub.width - sampleW - 6) })
      y += Math.max(probe.h, sub.lineH) + 6
    }
    y += 4
  }

  // the count table
  if (show.includes("count")) {
    const rows = countRows(parsed)
    label(sub, "Atomi in tutto", 2, y, { anchor: "start", cls: "dg-tablehead" })
    y += sub.lineH + 2
    const symW = Math.max(...rows.map((r) => sub.measure(r.symbol, F).w)) + 14
    for (const r of rows) {
      const groupNums = r.terms.map(([u, g]) => `${u > 1 || g ? `[[subscript:${u}]]` : "1"}${g ? ` × [[group:${g}]]` : ""}`)
      const inner = groupNums.length > 1 ? `(${groupNums.join(" + ")})` : groupNums[0]
      const chain = r.coefficient > 1 ? `${inner} × [[coefficient:${r.coefficient}]] = ${r.total}` : r.terms.length > 1 || r.terms[0][1] ? `${inner} = ${r.total}` : `${r.total}`
      label(sub, r.symbol, 2, y, { anchor: "start", cls: `dg-rowsym${eff.focus === r.symbol ? " dg-rowfocus" : ""}` })
      label(sub, chain, 2 + symW, y, { anchor: "start", cls: "dg-rowchain" })
      y += sub.lineH + 4
    }
    y += 4
  }

  // the molecules
  if (show.includes("molecules")) {
    const row = rowOfFormula(f)
    if (row) {
      const gap = Math.round(F * 2)
      if (row.kind === "molecular") {
        const p = pose(row, F)
        let cx = 2
        let cy = y
        let rowH = 0
        for (let c = 0; c < parsed.coefficient; c++) {
          if (cx + p.w > sub.width && cx > 2) {
            cx = 2
            cy += rowH + gap
            rowH = 0
          }
          drawMolecule(sub, p, cx, cy, row, { symbols: true })
          cx += p.w + gap
          rowH = Math.max(rowH, p.h)
        }
        y = cy + rowH + 6
      } else {
        const p = patchPose(row, sub, parsed.coefficient)
        label(sub, "unità", 4, y, { anchor: "start", cls: "dg-unitword" })
        const out = drawPatch(sub, p, 8, y + sub.lineH + 10)
        y = y + sub.lineH + 10 + p.h + 8
      }
      label(sub, row.name_it, 2, y, { anchor: "start", cls: "dg-molname" })
      y += sub.lineH + 2
    }
  }
  return { h: y + 4, targets }
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const blocks = eff.formulas.map((f, i) => ({ f, i, parsed: Chem.parse(f) }))
  // natural widths with room to spare, then side by side when they fit, one below the other when they do not
  const natural = blocks.map((b) => {
    const sub = subContext(ctx, 4000)
    drawBlock(sub, b, eff, { select, firstTarget: 1 })
    return extent(sub) + 4
  })
  const gap = Math.round(ctx.fontPx * 1.6)
  const sideBySide = natural.reduce((s, w) => s + w, 0) + gap * (blocks.length - 1) <= ctx.width
  let y = 0
  let x = 0
  let rowH = 0
  let nextTarget = 1
  const targets = []
  const place = (b, i, width, dx) => {
    const sub = subContext(ctx, width)
    const out = drawBlock(sub, b, eff, { select, firstTarget: nextTarget })
    nextTarget += out.targets.length
    mergeSub(ctx, sub, dx, y)
    for (const t of out.targets) targets.push({ ...t, bbox: { ...t.bbox, x: t.bbox.x + dx, y: t.bbox.y + y } })
    return out.h
  }
  blocks.forEach((b, i) => {
    if (sideBySide) {
      rowH = Math.max(rowH, place(b, i, natural[i], x))
      x += natural[i] + gap
    } else {
      y += place(b, i, ctx.width, 0) + (i < blocks.length - 1 ? gap / 2 : 0)
    }
  })
  y += sideBySide ? rowH : 0
  const out = finish(ctx, y + 4, { states: stateCount(data), state: ctx.state })
  if (!out.error && select) out.targets = targets.map(({ target, bbox }) => ({ target, bbox }))
  if (!out.error) out.live = describeState(data, ctx.state, ctx)
  return out
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- description, speech, targets, printed ------------------------------------------------------------------------------------------------

// "il coefficiente 3", "il simbolo H con il pedice 2", "il pacchetto NO3 con il pedice 2": the parts of a formula in reading order.
function partPhrases(parsed) {
  const out = []
  if (parsed.coefficient > 1) out.push(`il coefficiente ${parsed.coefficient}`)
  const atom = (a) => `il simbolo ${a.symbol}${a.count > 1 ? ` con il pedice ${a.count}` : ""}`
  for (const g of parsed.groups) {
    if (!g.group) out.push(atom(g))
    else out.push(`il pacchetto ${g.group.map((a) => `${a.symbol}${a.count > 1 ? a.count : ""}`).join("")} con il pedice ${g.count}`)
  }
  return out
}

// What the figure says of one formula in the state (only what is on show, L10).
function describeFormula(f, eff, { meaningOnly = false } = {}) {
  const parsed = Chem.parse(f)
  const show = eff.show ?? ["parts"]
  const out = []
  const row = show.includes("molecules") ? rowOfFormula(f) : null
  if (meaningOnly) {
    if (row) out.push(`${quantityPhrase(row, parsed.coefficient)}.`)
    else out.push(`${f}.`)
  } else if (row) out.push(`${f}: ${quantityPhrase(row, parsed.coefficient)}.`)
  if (show.includes("parts") && !meaningOnly) {
    out.push(`La formula ${f} ha ${listIt(partPhrases(parsed))}.`)
  }
  if (show.includes("count")) {
    const totals = Chem.count(f)
    out.push(`In tutto ${atomsPhrase(totals)}.`)
  }
  if (eff.focus && Object.hasOwn(Chem.count(f), eff.focus)) out.push(`Evidenziato: ${elementName(eff.focus)}.`)
  return out.join(" ")
}

function describeState(data, i, ctx) {
  const eff = effectiveState(data, i)
  return eff.formulas.map((f) => describeFormula(f, eff)).join(" ")
}

export function describe(data, ctx) {
  const single = ctx?.state
  const count = stateCount(data)
  const one = (i) => `${count > 1 ? `Passo ${i + 1}. ${data.states[i]?.op_it ? `${plain(data.states[i].op_it)}. ` : ""}` : ""}${describeState(data, i, ctx)}`
  if (single !== undefined || count === 1) return one(Math.min(single ?? 0, count - 1))
  return Array.from({ length: count }, (_, i) => one(i)).join(" ")
}

// The speech reads the meaning, not the letters: "tre molecole d'acqua. In tutto 6 atomi di idrogeno e 3 di ossigeno." (never "acca due o").
export function speechSegments(data, ctx) {
  const eff = effectiveState(data, ctx?.state ?? 0)
  const text = eff.formulas.map((f) => describeFormula(f, eff, { meaningOnly: true })).join(" ")
  return text ? [{ lang: "it", text }] : []
}

// targets(data, set) -> [{ key, bbox, neutral_it }] in reading order: the pieces of the formulas ("f1p3").
export function targets(data, set, opts = {}) {
  if (set !== "pieces") return []
  const scene = layout(data, { width: 360, fontPx: 20, subject: "chemistry", ...opts, mode: "select", state: 0 })
  if (scene.error) return []
  const ids = []
  data.formulas.forEach((f, i) => piecesOf(Chem.parse(f)).forEach((_, k) => ids.push(`f${i + 1}p${k + 1}`)))
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `Pezzo ${i + 1} di ${ids.length}` }))
}

// Every string the state prints (L4); Ruby's printed() returns the same set.
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const show = eff.show ?? ["parts"]
  const out = new Set()
  for (const f of eff.formulas) {
    out.add(f)
    const parsed = Chem.parse(f)
    if (!parsed) continue
    if (show.includes("parts")) {
      const items = piecesOf(parsed)
      for (const p of items) out.add(p.text)
      const kinds = ["coefficient", "symbol", "subscript"].filter((k) => items.some((p) => p.kind === k))
      if (parsed.groups.some((g) => g.group)) kinds.push("group")
      for (const k of kinds) {
        out.add(WORDS[k])
        out.add(HINTS[k])
      }
    }
    if (show.includes("count")) {
      for (const r of countRows(parsed)) {
        out.add(r.symbol)
        out.add(String(r.total))
        for (const [u, g] of r.terms) {
          out.add(String(u))
          if (g) out.add(String(g))
        }
        if (r.coefficient > 1) out.add(String(r.coefficient))
      }
    }
    if (show.includes("molecules")) {
      const row = rowOfFormula(f)
      if (row) out.add(row.name_it)
    }
  }
  if (eff.focus) out.add(eff.focus)
  const op = data.states?.[state]?.op_it
  if (op) out.add(op)
  return [...out]
}
