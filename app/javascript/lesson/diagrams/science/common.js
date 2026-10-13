// What the science family shares (T7): the library rows of chem/molecules, the pieces of a formula in reading order, the rows of its count table and
// the Italian words that describe them. Pure. The Ruby twin is Lessons::Diagrams::ScienceSupport (the pieces and the count rows run the same vectors).
import ELEMENTS from "lesson/data/chem-elements"
import MOLECULES from "lesson/data/chem-molecules"
import * as Chem from "lesson/lib/chem"

export const molecules = MOLECULES.molecules

export const MAIN_GROUPS = [1, 2, 13, 14, 15, 16, 17, 18]

// The elements a periodic table of `range` draws, in reading order (period by period, group by group): the rows of chem/elements.
export function rangeElements(range) {
  const rows = ELEMENTS.elements.filter((e) => (range === "periods_1_4" ? e.period <= 4 : range === "main_groups" ? e.group !== null && MAIN_GROUPS.includes(e.group) : false))
  return rows.sort((a, b) => a.period - b.period || a.group - b.group)
}

// The groups (columns) of a range, left to right.
export const rangeGroups = (range) => (range === "periods_1_4" ? Array.from({ length: 18 }, (_, i) => i + 1) : MAIN_GROUPS)

// The row of chem/molecules for a formula key (coefficient and state already removed), or null.
export const moleculeRow = (key) => (key ? molecules[key] ?? null : null)

// The row of the library for a formula as an author writes it ("3 H2O", "Ca(NO3)2(aq)"), or null.
export const rowOfFormula = (formula) => moleculeRow(Chem.base(formula))

export const PATCH_ROWS = 2
export const PATCH_UNITS = 2
export const METAL_DISCS = 7

// The groups of atom indices joined by bonds, in order of their first atom: the ions of a salt, or the one piece of a molecule.
export function ionGroups(row) {
  const parent = row.atoms.map((_, i) => i)
  const find = (i) => (parent[i] === i ? i : (parent[i] = find(parent[i])))
  for (const [a, b] of row.bonds ?? []) parent[find(a)] = find(b)
  const groups = new Map()
  row.atoms.forEach((_, i) => groups.set(find(i), [...(groups.get(find(i)) ?? []), i]))
  return [...groups.values()]
}

// How many discs a figure draws for a library row at a coefficient: the atoms of every molecule, or the discs of a patch (an ionic or metal row is
// a small patch with the first units framed: the coefficient is the number of framed units, at most PATCH_UNITS).
export function drawnCount(row, coefficient) {
  if (row.kind === "metal") return METAL_DISCS
  if (row.kind === "ionic") return PATCH_ROWS * PATCH_UNITS * ionGroups(row).length
  return row.atoms.length * coefficient
}

// Whether a patch can frame this many units.
export const unitsFit = (row, coefficient) => row.kind === "molecular" || coefficient <= PATCH_UNITS

// How many discs a figure draws for a formula as an author writes it; null outside the library.
export function atomsDrawn(formula) {
  const row = rowOfFormula(formula)
  return row ? drawnCount(row, Chem.parse(formula).coefficient) : null
}

// The leaf pieces of a parsed formula in reading order: [{ kind: "coefficient" | "symbol" | "subscript", text, group, ofGroup? }].
// A subscript is a piece only when it is written (a 1 is not); a bracket group's subscript is the group's.
export function pieces(parsed) {
  const out = []
  if (parsed.coefficient > 1) out.push({ kind: "coefficient", text: String(parsed.coefficient), group: false })
  for (const g of parsed.groups) {
    if (g.group) {
      for (const a of g.group) {
        out.push({ kind: "symbol", text: a.symbol, group: true })
        if (a.count > 1) out.push({ kind: "subscript", text: String(a.count), group: true })
      }
      out.push({ kind: "subscript", text: String(g.count), group: true, ofGroup: true })
    } else {
      out.push({ kind: "symbol", text: g.symbol, group: false })
      if (g.count > 1) out.push({ kind: "subscript", text: String(g.count), group: false })
    }
  }
  return out
}

// The rows of the count table, one per symbol in order of first appearance:
// { symbol, terms: [[unit, groupCount | null], ...], coefficient, total }.
export function countRows(parsed) {
  const rows = new Map()
  for (const g of parsed.groups) {
    if (g.group) for (const a of g.group) rows.set(a.symbol, [...(rows.get(a.symbol) ?? []), [a.count, g.count]])
    else rows.set(g.symbol, [...(rows.get(g.symbol) ?? []), [g.count, null]])
  }
  const k = parsed.coefficient
  return [...rows].map(([symbol, terms]) => ({ symbol, terms, coefficient: k, total: terms.reduce((s, [u, grp]) => s + u * (grp ?? 1), 0) * k }))
}

// ---- Italian ----------------------------------------------------------------------------------------------------------------------------

const WORDS = ["zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove", "dieci", "undici", "dodici", "tredici", "quattordici", "quindici", "sedici", "diciassette", "diciotto", "diciannove", "venti"]
// "tre" for 3 (1 to 20 as words; larger numbers stay digits)
export const numberWord = (n) => (n >= 0 && n <= 19 ? WORDS[n] : n === 20 ? "venti" : String(n))

// "d'acqua" before a vowel, "di cloro" before a consonant
export const dePhrase = (name) => (/^[aeiouàèéìòù]/i.test(name) ? `d'${name}` : `di ${name}`)

export const elementName = (symbol) => Chem.element(symbol)?.name_it ?? symbol

// "6 atomi di idrogeno e 3 di ossigeno": counts by symbol in order, the first with the word atomi (atomo for 1), the others bare.
export function atomsPhrase(counts) {
  const parts = Object.entries(counts).map(([symbol, n], i) => `${n}${i === 0 ? (n === 1 ? " atomo" : " atomi") : ""} di ${elementName(symbol)}`)
  if (parts.length <= 1) return parts.join("")
  return `${parts.slice(0, -1).join(", ")} e ${parts[parts.length - 1]}`
}

// What a coefficient of a library formula counts: "tre molecole d'acqua", "un'unità di cloruro di sodio", "due atomi di ferro".
export function quantityPhrase(row, coefficient) {
  const n = coefficient
  const name = row.name_it
  if (row.kind === "ionic") return `${n === 1 ? "un'unità" : `${numberWord(n)} unità`} ${dePhrase(name)}`
  if (row.kind === "metal") return `${n === 1 ? "un atomo" : `${numberWord(n)} atomi`} ${dePhrase(name)}`
  return `${n === 1 ? "una molecola" : `${numberWord(n)} molecole`} ${dePhrase(name)}`
}

// Plain text of a label that may carry [[role:text]] spans or $...$ math: for descriptions and the printed set.
export const strip = (text) => String(text ?? "").replace(/\[\[[a-z_]+:([^\]]*)\]\]/g, "$1").replace(/\$([^$]*)\$/g, "$1")

// ---- placing a block drawn in its own coordinates -------------------------------------------------------------------------------------------

// The path with its absolute coordinates moved by (dx, dy): M, L, C, Q as pairs, A with its end point only (radii, rotation and flags stay).
export function shiftPath(d, dx, dy) {
  return d.replace(/([MLCQA])([^MLCQAZ]*)/g, (_all, cmd, body) => {
    const nums = body.trim().split(/[\s,]+/).filter(Boolean).map(Number)
    const out = nums.map((v, i) => {
      if (cmd === "A") return i % 7 === 5 ? v + dx : i % 7 === 6 ? v + dy : v
      return i % 2 === 0 ? v + dx : v + dy
    })
    if (cmd === "A") return `A${out.slice(0, 2).join(",")} ${out[2]} ${out[3]} ${out[4]} ${out[5].toFixed(1)},${out[6].toFixed(1)}`
    return `${cmd}${out.map((v, i) => (i % 2 === 0 ? `${v.toFixed(1)}` : `,${v.toFixed(1)} `)).join("").trim()}`
  })
}

// A shape moved by (dx, dy), in place.
export function shiftShape(s, dx, dy) {
  if (s.kind === "line") {
    s.x1 += dx
    s.x2 += dx
    s.y1 += dy
    s.y2 += dy
  } else if (s.kind === "rect" || s.kind === "marker") {
    s.x += dx
    s.y += dy
  } else if (s.kind === "circle" || s.kind === "ellipse") {
    s.cx += dx
    s.cy += dy
  } else if (s.kind === "polygon") {
    s.points = s.points.map(([px, py]) => [px + dx, py + dy])
  } else if (s.kind === "path") {
    s.d = shiftPath(s.d, dx, dy)
  } else if (s.kind === "icon") {
    s.x += dx
    s.y += dy
  }
  return s
}

// Moves what a sub context drew by (dx, dy) and adds it to the real context.
export function mergeSub(ctx, sub, dx, dy) {
  for (const l of sub.labels) {
    l.x += dx
    l.y += dy
    ctx.labels.push(l)
  }
  for (const s of sub.shapes) ctx.shapes.push(shiftShape(s, dx, dy))
}
