// molecule (WAVE2 2.8, chemistry.md 2.5; T7): 2D molecules from chem/molecules. A coefficient draws copies ('2 O2' is two molecules). An ionic row (NaCl) and a
// metal row (Fe) have no molecules: they are drawn as a small patch with the first units framed and labelled "unità", never "molecola".
// The Ruby twin is Lessons::Diagrams::Molecule (the semantic checks run in the same order); both run test/fixtures/diagrams/types/molecule.json.
import schema from "lesson/diagram_schemas/molecule"
import * as Chem from "lesson/lib/chem"
import { finish, label, shape, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"
import { PATCH_UNITS, atomsPhrase, drawnCount, ionGroups, quantityPhrase, rowOfFormula, unitsFit } from "lesson/diagrams/science/common"
import { angleText, drawMolecule, drawPatch, ionText, patchPose, pose } from "lesson/diagrams/science/molecule_draw"

export const type = "molecule"
export { schema }

const MAX_ATOMS = 30 // lesson2.types.formula.atoms_drawn in validation_rules.yml
const LABEL_WORDS = 6 // lesson2.label_words_max

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::Molecule) ---------------------------------------------------------

export function semantic(data) {
  const rows = []
  for (let i = 0; i < data.items.length; i++) {
    const item = data.items[i]
    const f = item.formula
    const path = `/items/${i}/formula`
    const parsed = Chem.parse(f)
    if (!parsed) {
      const bad = Chem.unknownSymbol(f)
      if (bad) return { path, message: `${bad} is not the symbol of an element (symbols are case-exact: Cl, not CL)`, code: "E-CHEM-SYMBOL" }
      return { path, message: `${JSON.stringify(f)} is not a formula the grammar reads (a coefficient 2 to 20, subscripts 2 to 99, one level of brackets, a state (s) (l) (g) (aq))` }
    }
    const row = rowOfFormula(f)
    if (!row) return { path, message: `${JSON.stringify(f)} is not in chem/molecules: a molecule is drawn from the library only`, code: "E-LESSON-DATA" }
    rows.push([row, parsed.coefficient])
    if (!unitsFit(row, parsed.coefficient)) return { path, message: `a salt or a metal is drawn as a patch with at most ${PATCH_UNITS} units framed: ${JSON.stringify(f)} has a coefficient above that` }
    if (item.label_it && words(item.label_it) > LABEL_WORDS) return { path: `/items/${i}/label_it`, message: `a label has ${words(item.label_it)} words (at most ${LABEL_WORDS})` }
  }
  const total = rows.reduce((s, [row, k]) => s + drawnCount(row, k), 0)
  if (total > MAX_ATOMS) return { path: "/items", message: `the figure would draw ${total} atoms (at most ${MAX_ATOMS})` }
  const show = data.show ?? ["symbols"]
  if (show.includes("angle") && rows.every(([row]) => !row.angle)) return { path: "/show", message: "angle is drawn for a molecule of three atoms from the library (CO2, H2O, O3): no item has one" }
  if (show.includes("partial") && rows.every(([row]) => !row.partial_charges)) return { path: "/show", message: "partial charges are drawn from the library (H2O, CO2, H2O2, NH3): no item has them" }
  return null
}

// ---- layout -----------------------------------------------------------------------------------------------------------------------------

// One block per item: the copies (or the patch), and the caption under it.
function planBlock(ctx, item, i, o) {
  const F = ctx.fontPx
  const parsed = Chem.parse(item.formula)
  const row = rowOfFormula(item.formula)
  const caption = o.select ? null : item.label_it ?? row.name_it
  const gap = Math.round(F * 1.4)
  const margin = o.margin
  let content
  if (row.kind === "molecular") {
    const p = pose(row, F, { style: o.style, neutral: o.select, margin })
    const perRow = Math.max(1, Math.floor((o.maxW + gap) / (p.w + gap)))
    const cols = Math.min(parsed.coefficient, perRow)
    const rows = Math.ceil(parsed.coefficient / cols)
    content = { kind: "molecular", p, cols, rows, gap, w: cols * p.w + (cols - 1) * gap, h: rows * p.h + (rows - 1) * gap }
  } else {
    const p = patchPose(row, ctx, parsed.coefficient)
    const head = o.select ? 0 : ctx.lineH + 8
    content = { kind: row.kind, p, head, w: p.w + 16, h: p.h + head + 10 }
  }
  let cap = null
  if (caption) {
    const capW = Math.min(o.maxW, 240)
    const m = ctx.measure(caption, F, capW)
    cap = { text: caption, w: Math.min(m.w, capW), h: m.h, maxW: capW }
  }
  const w = Math.max(content.w, cap?.w ?? 0)
  return { i, item, parsed, row, content, cap, w, h: content.h + (cap ? cap.h + 6 : 0) }
}

function drawBlock(ctx, b, x, y0, o) {
  const c = b.content
  const dx = x + (b.w - c.w) / 2
  const y = y0 + (o.rowContentH - c.h) / 2 // the contents of a row are centred on one line, their captions share another
  const boxes = []
  let n = o.firstTarget
  if (c.kind === "molecular") {
    for (let copy = 0; copy < b.parsed.coefficient; copy++) {
      const col = copy % c.cols
      const r = Math.floor(copy / c.cols)
      const out = drawMolecule(ctx, c.p, dx + col * (c.p.w + c.gap), y + r * (c.p.h + c.gap), b.row, { symbols: o.symbols, partial: o.partial, angle: o.angle, neutral: o.select, sticks: o.style === "sticks", atomTargets: o.set === "atoms" && o.select, firstTarget: n })
      boxes.push(...out.boxes)
      n = out.next
    }
  } else {
    if (!o.select) label(ctx, "unità", dx + 8, y, { anchor: "start", cls: "dg-unitword" })
    const out = drawPatch(ctx, c.p, dx + 8, y + c.head, { symbols: o.symbols, neutral: o.select, atomTargets: o.set === "atoms" && o.select, firstTarget: n })
    boxes.push(...out.boxes)
    n = out.next
  }
  if (b.cap) label(ctx, b.cap.text, x + b.w / 2, y0 + o.rowContentH + 6, { anchor: "middle", cls: "dg-molname", maxW: b.cap.maxW })
  return { boxes, next: n, box: { x: dx, y, w: c.w, h: c.h } }
}

function build(data, ctx) {
  const F = ctx.fontPx
  const select = ctx.mode === "select"
  const set = ctx.set ?? "atoms"
  const show = select ? [] : data.show ?? ["symbols"]
  const style = data.style ?? "balls"
  const margin = show.includes("partial") || show.includes("angle") ? [Math.round(F * 0.7), Math.round(F * 2.1)] : 0
  const room = ctx.width - 6 // a label is drawn two pixels wider than its text: the last one must not touch the edge
  const o = { select, set, style, margin, maxW: room, symbols: show.includes("symbols"), partial: show.includes("partial"), angle: show.includes("angle"), firstTarget: 1 }
  const blocks = data.items.map((item, i) => planBlock(ctx, item, i, o))
  // rows of blocks, each row centred
  const gap = Math.round(F * 2)
  const lines = []
  let line = { blocks: [], w: 0 }
  for (const b of blocks) {
    if (line.blocks.length && line.w + gap + b.w > room) {
      lines.push(line)
      line = { blocks: [], w: 0 }
    }
    line.w += (line.blocks.length ? gap : 0) + b.w
    line.blocks.push(b)
  }
  lines.push(line)
  let y = 2
  const targets = []
  let next = 1
  for (const l of lines) {
    let x = Math.max(0, Math.round((ctx.width - l.w) / 2))
    const rowContentH = Math.max(...l.blocks.map((b) => b.content.h))
    const h = rowContentH + Math.max(0, ...l.blocks.map((b) => (b.cap ? b.cap.h + 6 : 0)))
    for (const b of l.blocks) {
      const out = drawBlock(ctx, b, x, y, { ...o, firstTarget: next, rowContentH })
      next = out.next
      if (select && set === "atoms") targets.push(...out.boxes)
      if (select && set === "items") {
        const t = `t${b.i + 1}`
        const pad = 4
        shape(ctx, "rect", { x: out.box.x - pad, y: out.box.y - pad, w: out.box.w + 2 * pad, h: out.box.h + 2 * pad, r: 10, cls: "dg-piece", target: t })
        targets.push({ target: t, bbox: { x: out.box.x - pad, y: out.box.y - pad, w: out.box.w + 2 * pad, h: out.box.h + 2 * pad } })
      }
      x += b.w + gap
    }
    y += h + Math.round(F * 0.9)
  }
  const out = finish(ctx, y, {})
  if (!out.error && select) out.targets = targets
  return out
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- description, targets, printed -----------------------------------------------------------------------------------------------------

const BOND_WORDS = { 1: ["un legame semplice", "legami semplici"], 2: ["un legame doppio", "legami doppi"], 3: ["un legame triplo", "legami tripli"] }

// "2 legami semplici", "un legame doppio e uno semplice"
function bondsPhrase(row) {
  const counts = {}
  for (const [, , order] of row.bonds) counts[order] = (counts[order] ?? 0) + 1
  const parts = Object.keys(counts).sort().map((order) => (counts[order] === 1 ? BOND_WORDS[order][0] : `${counts[order]} ${BOND_WORDS[order][1]}`))
  return parts.length === 0 ? "" : `con ${parts.length === 1 ? parts[0] : `${parts.slice(0, -1).join(", ")} e ${parts[parts.length - 1].replace(/^un legame /, "uno ").replace(/^1 /, "")}`}`
}

function describeItem(item, show) {
  const parsed = Chem.parse(item.formula)
  const row = rowOfFormula(item.formula)
  const name = item.label_it ?? row.name_it
  if (row.kind !== "molecular") {
    const what = row.kind === "metal" ? "un reticolo di atomi di" : "un reticolo di ioni"
    return `${quantityPhrase(row, parsed.coefficient)} (${item.formula}): ${what}${row.kind === "metal" ? ` ${name}` : ""}, con una unità in un riquadro. Non ci sono molecole.`
  }
  const each = parsed.coefficient > 1 ? "ogni molecola ha " : ""
  const out = [`${quantityPhrase(row, parsed.coefficient)} (${item.formula}): ${each}${atomsPhrase(Chem.count(Chem.base(item.formula)))}${row.bonds.length ? `, ${bondsPhrase(row)}` : ""}.`]
  if (show.includes("angle") && row.angle) out.push(`L'angolo tra i due legami è di ${row.angle.replace(/,0$/, "")} gradi.`)
  if (show.includes("partial") && row.partial_charges) {
    const neg = []
    const pos = []
    row.atoms.forEach((a, i) => {
      const c = Number(row.partial_charges[i].replace(",", "."))
      const list = c < 0 ? neg : pos
      if (!list.includes(a.symbol)) list.push(a.symbol)
    })
    const names = (list) => list.map((s) => Chem.element(s).name_it).join(" e ")
    out.push(`Carica parziale negativa: ${names(neg)}. Positiva: ${names(pos)}.`)
  }
  return out.join(" ")
}

export function describe(data) {
  const show = data.show ?? ["symbols"]
  const items = data.items.map((it) => describeItem(it, show))
  return data.items.length > 1 ? `${data.items.length === 2 ? "Due" : ["", "", "", "Tre", "Quattro", "Cinque", "Sei"][data.items.length]} gruppi. ${items.join(" ")}` : items[0]
}

export function targetIds(data, set) {
  if (set === "items") return data.items.map((_, i) => `i${i + 1}`)
  if (set !== "atoms") return []
  return data.items.flatMap((item, i) => {
    const parsed = Chem.parse(item.formula)
    const row = parsed && rowOfFormula(item.formula)
    if (!row) return []
    if (row.kind === "molecular") return Array.from({ length: parsed.coefficient }, (_, copy) => row.atoms.map((_a, a) => `i${i + 1}c${copy + 1}a${a + 1}`)).flat()
    return Array.from({ length: drawnCount(row, 1) }, (_, d) => `i${i + 1}x${d + 1}`)
  })
}

// targets(data, set) -> [{ key, bbox, neutral_it }]: "items" are the groups, "atoms" the discs, in reading order.
export function targets(data, set, opts = {}) {
  const ids = targetIds(data, set)
  if (ids.length === 0) return []
  const scene = layout(data, { width: 360, fontPx: 20, subject: "chemistry", ...opts, mode: "select", set })
  if (scene.error) return []
  const noun = set === "items" ? "Gruppo" : "Atomo"
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `${noun} ${i + 1} di ${ids.length}` }))
}

// Every string the figure prints (L4); Ruby's printed() returns the same set. The molecule has no states.
export function printed(data) {
  const show = data.show ?? ["symbols"]
  const out = new Set()
  for (const item of data.items) {
    out.add(item.formula)
    const row = rowOfFormula(item.formula)
    if (!row) continue
    out.add(item.label_it ?? row.name_it)
    if (row.kind === "molecular") {
      if (show.includes("symbols")) for (const a of row.atoms) out.add(a.symbol)
      if (show.includes("angle") && row.angle) out.add(angleText(row.angle))
      if (show.includes("partial") && row.partial_charges) {
        const signs = row.partial_charges.map((c) => Number(c.replace(",", ".")))
        if (signs.some((v) => v > 0)) out.add("δ+")
        if (signs.some((v) => v < 0)) out.add("δ−")
      }
    } else {
      out.add("unità")
      if (show.includes("symbols")) {
        if (row.kind === "metal") out.add(row.atoms[0].symbol)
        else for (const idx of ionGroups(row)) out.add(ionText(row, idx).plain)
      }
    }
  }
  return [...out]
}
