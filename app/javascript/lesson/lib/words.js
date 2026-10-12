// Words: The split notation shared by paradigm and word_parts (| stem and ending, [..] changed letters, + attached piece), Spanish syllables and stress.
// Built by T3 (WAVE2 1.10, batch w2-1). The Ruby twin is lib/lessons/words.rb and both run test/fixtures/lesson2/spanish_words.json (and the Ruby file's
// header says the rules). `present` is the W2-2 half and is not built yet.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "split": "split(notation)",
  "syllables_es": "syllablesEs(word)",
  "stress_es": "stressEs(word)",
  "tilde_ok": "tildeOk(word)",
  "present": "present(verb, pattern)"
}

const ACCENTED = "áéíóú"
const STRONG = ["a", "e", "o", "á", "é", "ó"]
const WEAK = ["i", "u", "ü", "í", "ú"]
const VOWELS = [...STRONG, ...WEAK]
const TILDE_WEAK = ["í", "ú"]
const INSEPARABLE = ["pl", "pr", "bl", "br", "fl", "fr", "gl", "gr", "cl", "cr", "kl", "kr", "tr", "dr"]
const DIACRITIC = ["tú", "él", "mí", "sí", "sé", "té", "dé", "más", "aún", "qué", "quién", "quiénes", "cuál", "cuáles", "cuán", "cuándo", "cuánto", "cuánta", "cuántos", "cuántas", "cómo", "dónde", "adónde"]

export class Refused extends Error {}

const hasTilde = (syl) => [...syl.toLowerCase()].some((c) => ACCENTED.includes(c))
const stripTilde = (text) => [...text].map((c) => { const i = ACCENTED.indexOf(c); return i < 0 ? c : "aeiou"[i] }).join("")

// A form in split notation as pieces with their marks; the marks removed give the word.
// Returns { pieces: [{ text, mark, group }], word }. The marks: "stem" (before the first |), "ending" (after a |), "attached" (after a +),
// "change" (inside [..]); a "group" is a piece between | and + (the pieces of a decode), counted from 0.
export function split(notation) {
  if (typeof notation !== "string") throw new Refused("the form must be a text")
  if (notation === "") throw new Refused("the form is empty")
  if (/\s/.test(notation)) throw new Refused("no spaces in a form")
  const pieces = []
  let group = 0
  let mark = "stem"
  let base = "stem"
  let buf = ""
  let inside = false
  const flush = (m) => {
    if (buf !== "") pieces.push({ text: buf, mark: m, group })
    buf = ""
  }
  for (const ch of notation) {
    if (ch === "[") {
      if (inside) throw new Refused("[ inside [ ]")
      flush(mark)
      inside = true
    } else if (ch === "]") {
      if (!inside) throw new Refused("] without [")
      if (buf === "") throw new Refused("[] is empty")
      flush("change")
      inside = false
      mark = base
    } else if (ch === "|" || ch === "+") {
      if (inside) throw new Refused(`${ch} inside [ ]`)
      if (pieces.length === 0 && buf === "") throw new Refused(`a piece before ${ch} is missing`)
      flush(mark)
      if (pieces[pieces.length - 1].group !== group) throw new Refused("two separators in a row")
      group += 1
      base = ch === "|" ? "ending" : "attached"
      mark = base
    } else buf += ch
  }
  if (inside) throw new Refused("[ is not closed")
  flush(mark)
  if (pieces.length === 0 || pieces[pieces.length - 1].group !== group) throw new Refused("a piece after the last separator is missing")
  return { pieces, word: pieces.map((p) => p.text).join("") }
}

// The word as units: { low, vowel, len, at }, a vowel or a consonant (a digraph is one unit); `at` is the index of its first letter.
function unitsOf(word) {
  if (typeof word !== "string" || !/^\p{L}+$/u.test(word)) throw new Refused(`${JSON.stringify(word)}: a word of letters only`)
  const low = [...word.toLowerCase()]
  const units = []
  let i = 0
  while (i < low.length) {
    const c = low[i]
    const n = low[i + 1]
    const d = low[i + 2]
    if (["ch", "ll", "rr"].includes(`${c}${n}`)) {
      units.push({ low: `${c}${n}`, vowel: false, len: 2, at: i })
      i += 2
    } else if ((c === "q" || c === "g") && n === "u" && ["e", "i", "é", "í"].includes(d ?? "")) {
      units.push({ low: `${c}u`, vowel: false, len: 2, at: i })
      i += 2
    } else if (VOWELS.includes(c) || (c === "y" && i === low.length - 1 && (i === 0 || VOWELS.includes(low[i - 1])))) {
      units.push({ low: c, vowel: true, len: 1, at: i })
      i += 1
    } else {
      units.push({ low: c, vowel: false, len: 1, at: i })
      i += 1
    }
  }
  return units
}

// Whether two neighbouring vowels (units a and b of one run) are one syllable.
function joined(units, a, b, last) {
  const x = units[a].low
  const y = units[b].low
  const sx = STRONG.includes(x)
  const sy = STRONG.includes(y)
  const wx = WEAK.includes(x) || x === "y"
  const wy = WEAK.includes(y) || y === "y"
  if (sx && sy) return false
  if (wx && wy) {
    const base = (v) => v.replace(/[íúü]/g, (c) => ({ í: "i", ú: "u", ü: "u" })[c]).replace("y", "i")
    return base(x) !== base(y)
  }
  if (TILDE_WEAK.includes(x) || TILDE_WEAK.includes(y)) return false
  // a weak vowel between two strong ones goes with the second (a-ia, not ai-a)
  if (sx && wy && b < last && STRONG.includes(units[b + 1].low)) return false
  return true
}

// The nuclei of the syllables: runs of vowel units cut at hiatus, as [from, to] indexes of units.
function nucleiOf(units) {
  const nuclei = []
  let i = 0
  while (i < units.length) {
    if (!units[i].vowel) {
      i += 1
      continue
    }
    let j = i
    while (j + 1 < units.length && units[j + 1].vowel) j += 1
    let start = i
    for (let a = i; a < j; a++) {
      if (joined(units, a, a + 1, j)) continue
      nuclei.push([start, a])
      start = a + 1
    }
    nuclei.push([start, j])
    i = j + 1
  }
  return nuclei
}

// The syllables of a Spanish word.
export function syllablesEs(word) {
  const units = unitsOf(word)
  const nuclei = nucleiOf(units)
  if (nuclei.length <= 1) return [word]
  const cuts = []
  for (let k = 0; k + 1 < nuclei.length; k++) {
    const from = nuclei[k][1] + 1
    const to = nuclei[k + 1][0]
    const cons = to - from
    if (cons === 0) cuts.push(to)
    else if (cons === 1) cuts.push(from)
    else if (INSEPARABLE.includes(units[to - 2].low + units[to - 1].low) && units[to - 2].len === 1 && units[to - 1].len === 1) cuts.push(to - 2)
    else cuts.push(to - 1)
  }
  // `at` counts letters of the lower-cased word, as Ruby's characters do; the original keeps its case and its tildes
  const chars = [...word]
  const spans = []
  let from = 0
  for (const unit of cuts) {
    const at = units[unit].at
    spans.push(chars.slice(from, at).join(""))
    from = at
  }
  spans.push(chars.slice(from).join(""))
  return spans
}

function defaultStress(syls, low) {
  if (syls.length === 1) return 1
  const chars = [...low]
  const last = chars[chars.length - 1]
  const open = VOWELS.includes(last) || last === "n" || (last === "s" && VOWELS.includes(chars[chars.length - 2] ?? ""))
  return open ? syls.length - 1 : syls.length
}

// The 1-based index of the stressed syllable.
export function stressEs(word) {
  const syls = syllablesEs(word)
  const marked = syls.map((s, i) => (hasTilde(s) ? i : -1)).filter((i) => i >= 0)
  if (marked.length > 1) throw new Refused(`${word}: two written tildes`)
  if (marked.length) return marked[0] + 1
  return defaultStress(syls, word.toLowerCase())
}

// A tilde on í or ú next to a strong vowel keeps the hiatus (día, país, baúl).
function hiatusTilde(syls, index) {
  const syl = [...syls[index].toLowerCase()]
  const at = syl.findIndex((c) => TILDE_WEAK.includes(c))
  if (at < 0) return false
  if (at > 0 && STRONG.includes(syl[at - 1])) return true
  if (STRONG.includes(syl[at + 1] ?? "")) return true
  const prev = index > 0 ? [...syls[index - 1].toLowerCase()].pop() : ""
  const next = index < syls.length - 1 ? [...syls[index + 1].toLowerCase()][0] : ""
  return (at === 0 && STRONG.includes(prev ?? "")) || (at === syl.length - 1 && STRONG.includes(next ?? ""))
}

// Whether the written tilde (or its absence) follows the stress rule: false for a tilde that is not needed (cámara is right, camára is not; a
// tilde on a monosyllable such as fué, or on the stressed syllable of a word that is stressed there anyway); a word with no tilde cannot be
// told wrong, because the engine does not know how it is said.
export function tildeOk(word) {
  const low = word.toLowerCase()
  if (DIACRITIC.includes(low)) return true
  const syls = syllablesEs(word)
  const marked = syls.map((s, i) => (hasTilde(s) ? i : -1)).filter((i) => i >= 0)
  if (marked.length === 0) return true
  if (marked.length > 1 || syls.length === 1) return false
  if (hiatusTilde(syls, marked[0])) return true
  return marked[0] + 1 !== defaultStress(syls, stripTilde(low))
}

// W2-2: the six present forms by pattern; spanish/verbs is the truth and the engine only cross-checks regular and stem-changing rows.
export const present = notBuilt("words.present", "T3", "w2-2")
