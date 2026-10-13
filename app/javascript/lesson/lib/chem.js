// Chem: the formula grammar (case-exact symbols from chem/elements, one bracket level), atom counts and classes (WAVE2 1.10, 2.8; T7).
// The Ruby twin is lib/lessons/chem.rb and both run test/fixtures/lesson2/chem_formulas.json.
//
//   formula     := coefficient? unit state?
//   coefficient := 2..20, then an optional single space        ("3 H2O", "2Ca(NO3)2")
//   unit        := ( Symbol subscript? | "(" ( Symbol subscript? )+ ")" subscript )+
//   subscript   := 2..99 (a 1 is never written)
//   state       := "(s)" | "(l)" | "(g)" | "(aq)"
//
// Symbols are the 118 of chem/elements and are case-exact: "Co" is cobalt, "CO" is carbon and oxygen, "CL" is nothing. One level of brackets
// in this release; charges and hydrates come later. Nothing here draws or says anything: that is the figure's job.
import ELEMENTS from "lesson/data/chem-elements"

// name => signature
export const SIGNATURES = {
  "parse": "parse(formula)",
  "count": "count(formula)",
  "classify": "classify(formula)",
  "same_composition": "sameComposition(a, b)"
}

export const COEFFICIENT = [2, 20]
export const SUBSCRIPT = [2, 99]

const ROWS = new Map(ELEMENTS.elements.map((e) => [e.symbol, e]))
export const SYMBOLS = new Set(ROWS.keys())

export const isSymbol = (text) => SYMBOLS.has(String(text))
// The row of an element by symbol, or null.
export const element = (symbol) => ROWS.get(String(symbol)) ?? null

const within = (n, [lo, hi]) => n >= lo && n <= hi

function symbolAt(text, i) {
  if (!/[A-Z]/.test(text[i] ?? "")) return null
  for (const len of [3, 2, 1]) {
    const candidate = text.slice(i, i + len)
    if (candidate.length === len && /^[A-Z][a-z]*$/.test(candidate) && SYMBOLS.has(candidate)) return candidate
  }
  return null
}

// { count: Integer or null, next } for the digits at text[i..]; null when they are not a legal subscript (a leading 0, a 1, over 99).
function subscript(text, i) {
  const m = /^\d+/.exec(text.slice(i))
  if (!m) return { count: null, next: i }
  if (!/^[1-9]\d*$/.test(m[0])) return null
  const n = Number(m[0])
  if (!within(n, SUBSCRIPT)) return null
  return { count: n, next: i + m[0].length }
}

function atom(text, i) {
  const symbol = symbolAt(text, i)
  if (!symbol) return null
  const sub = subscript(text, i + symbol.length)
  if (!sub) return null
  return { symbol, count: sub.count ?? 1, next: sub.next }
}

function atoms(text) {
  const out = []
  let i = 0
  while (i < text.length) {
    const one = atom(text, i)
    if (!one) return null
    out.push({ symbol: one.symbol, count: one.count })
    i = one.next
  }
  return out
}

// A formula as { coefficient, groups, state }; null when it does not parse. A group is { symbol, count } or, for a bracket group,
// { group: [{ symbol, count }...], count }. The coefficient is 1 when none is written; the state is null or "s", "l", "g", "aq".
export function parse(formula) {
  let text = String(formula ?? "")
  if (text === "" || text.trim() !== text) return null
  let coefficient = 1
  const lead = /^(\d+) ?/.exec(text)
  if (lead) {
    coefficient = Number(lead[1])
    if (lead[1] !== String(coefficient) || !within(coefficient, COEFFICIENT)) return null
    text = text.slice(lead[0].length)
  }
  let state = null
  const tail = /\((s|l|g|aq)\)$/.exec(text)
  if (tail) {
    state = tail[1]
    text = text.slice(0, text.length - tail[0].length)
  }
  const groups = []
  let i = 0
  while (i < text.length) {
    if (text[i] === "(") {
      const close = text.indexOf(")", i)
      if (close < 0) return null
      const inner = atoms(text.slice(i + 1, close))
      if (!inner || inner.length === 0) return null
      const n = subscript(text, close + 1)
      if (!n || n.count === null) return null
      groups.push({ group: inner, count: n.count })
      i = n.next
    } else {
      const one = atom(text, i)
      if (!one) return null
      groups.push({ symbol: one.symbol, count: one.count })
      i = one.next
    }
  }
  if (groups.length === 0) return null
  return { coefficient, groups, state }
}

// Atoms by symbol, coefficient included; null when the formula does not parse.
export function count(formula) {
  const parsed = parse(formula)
  if (!parsed) return null
  const totals = {}
  for (const g of parsed.groups) {
    if (g.group) for (const a of g.group) totals[a.symbol] = (totals[a.symbol] ?? 0) + a.count * g.count * parsed.coefficient
    else totals[g.symbol] = (totals[g.symbol] ?? 0) + g.count * parsed.coefficient
  }
  return totals
}

// "element" when one kind of atom makes the formula, "compound" otherwise; null when it does not parse.
export function classify(formula) {
  const totals = count(formula)
  if (!totals) return null
  return Object.keys(totals).length === 1 ? "element" : "compound"
}

// Whether two formulas have the same atom counts (a near miss of a typed answer); false when either does not parse.
export function sameComposition(a, b) {
  const ca = count(a)
  const cb = count(b)
  if (!ca || !cb) return false
  const ka = Object.keys(ca)
  return ka.length === Object.keys(cb).length && ka.every((k) => ca[k] === cb[k])
}

// The formula without its coefficient and state ("2 Ca(NO3)2(aq)" -> "Ca(NO3)2"), the key of chem/molecules; null when it does not parse.
export function base(formula) {
  if (!parse(formula)) return null
  return String(formula).replace(/^\d+ ?/, "").replace(/\((s|l|g|aq)\)$/, "")
}

// The first symbol-shaped word of the text (a capital and its lowercase letters) that is not an element: "Xx2" gives "Xx"; null when every
// such word is an element (the formula may still be badly shaped).
export function unknownSymbol(formula) {
  return (String(formula ?? "").match(/[A-Z][a-z]*/g) ?? []).find((word) => !SYMBOLS.has(word)) ?? null
}
