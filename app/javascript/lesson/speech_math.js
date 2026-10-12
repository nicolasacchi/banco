// The speech form of the markup grammar (WAVE2 4.3, SPEC A10): what a formula, a chemical formula, a code span and a string of bits sound like
// when the device reads them. Pure functions of strings; the walker of lesson/speech.js calls them for the KaTeX output (it reads the TeX source
// out of the annotation) and for the nodes that say what they are. Italian, digits left as digits (the device reads them well).

const SIMPLE = {
  "+": "più", "-": "meno", "−": "meno", "=": "uguale", "<": "minore di", ">": "maggiore di", "*": "per", "/": "diviso", ":": "diviso",
  "\\cdot": "per", "\\times": "per", "\\div": "diviso", "\\pm": "più o meno", "\\neq": "diverso da", "\\ne": "diverso da", "\\le": "minore o uguale a",
  "\\leq": "minore o uguale a", "\\ge": "maggiore o uguale a", "\\geq": "maggiore o uguale a", "\\approx": "circa uguale a", "\\to": "diventa",
  "\\rightarrow": "diventa", "\\Rightarrow": "quindi", "\\leftarrow": "prende", "\\Leftrightarrow": "se e solo se", "\\%": "per cento", "%": "per cento",
  "\\cdots": "e così via", "\\ldots": "e così via", "\\dots": "e così via", "\\infty": "infinito", "\\in": "appartiene a", "\\cup": "unito a",
  "\\cap": "intersecato con", "\\subset": "contenuto in", "\\circ": "gradi", "\\degree": "gradi", "°": "gradi",
  "\\pi": "pi greco", "\\alpha": "alfa", "\\beta": "beta", "\\gamma": "gamma", "\\delta": "delta", "\\Delta": "delta", "\\theta": "teta", "\\lambda": "lambda",
  "\\mu": "mi", "\\sigma": "sigma", "\\omega": "omega", "\\varepsilon": "epsilon", "\\epsilon": "epsilon"
}
const IGNORED = new Set(["\\left", "\\right", "\\,", "\;", "\\:", "\\!", "\\ ", "\\quad", "\\qquad", "\\displaystyle", "\\textstyle", "\\limits", "\\bigl", "\\bigr", "\\big", "\\Big", "\\\\", "&"])
const WORD_AFTER_POWER = { 2: "al quadrato", 3: "al cubo" }

// ---- TeX: a tiny reader of the subset lessons use -----------------------------------------------------------------------------------------

function readGroup(s, i) {
  // s[i] is "{": the text inside and the index after the closing brace
  let depth = 0
  for (let j = i; j < s.length; j++) {
    if (s[j] === "\\") j += 1
    else if (s[j] === "{") depth += 1
    else if (s[j] === "}" && --depth === 0) return [s.slice(i + 1, j), j + 1]
  }
  return [s.slice(i + 1), s.length]
}

// One argument: a group or a single token (a letter, a digit or a command).
function readArg(s, i) {
  while (s[i] === " ") i += 1
  if (s[i] === "{") return readGroup(s, i)
  if (s[i] === "\\") {
    const m = s.slice(i).match(/^\\[A-Za-z]+|^\\./)
    return [m[0], i + m[0].length]
  }
  return [s.slice(i, i + 1), i + 1]
}

// TeX -> the words said. Fragments are joined by single spaces.
export function texToSpeech(tex) {
  const out = []
  const push = (w) => { if (w) out.push(w) }
  const s = String(tex ?? "")
  let i = 0
  while (i < s.length) {
    const ch = s[i]
    if (ch === " " || ch === "~" || ch === "\n") { i += 1; continue }
    if (ch === "\\") {
      const m = s.slice(i).match(/^\\[A-Za-z]+|^\\./)
      const cmd = m[0]
      i += cmd.length
      if (IGNORED.has(cmd)) continue
      if (cmd === "\\frac" || cmd === "\\dfrac" || cmd === "\\tfrac") {
        const [a, j] = readArg(s, i)
        const [b, k] = readArg(s, j)
        i = k
        const top = texToSpeech(a)
        const bottom = texToSpeech(b)
        // a one-word numerator and denominator are "3 fratto 4"; longer ones are named so that the ear can tell where each ends
        push(!/\s/.test(top) && !/\s/.test(bottom) ? `${top} fratto ${bottom}` : `frazione con numeratore ${top} e denominatore ${bottom}`)
      } else if (cmd === "\\sqrt") {
        let index = null
        if (s[i] === "[") {
          const close = s.indexOf("]", i)
          index = s.slice(i + 1, close)
          i = close + 1
        }
        const [a, j] = readArg(s, i)
        i = j
        push(`${index === "3" ? "radice cubica di" : index ? `radice ${texToSpeech(index)}-esima di` : "radice quadrata di"} ${texToSpeech(a)}`)
      } else if (cmd === "\\role") {
        const [, j] = readArg(s, i) // the role name
        const [a, k] = readArg(s, j)
        i = k
        push(texToSpeech(a))
      } else if (cmd === "\\text" || cmd === "\\mathrm" || cmd === "\\mathbf" || cmd === "\\textbf" || cmd === "\\mathit") {
        const [a, j] = readArg(s, i)
        i = j
        push(cmd === "\\mathrm" && /[A-Z]/.test(a) ? a : a.replace(/\\[A-Za-z]+/g, " "))
      } else if (cmd === "\\overline" || cmd === "\\bar") {
        const [a, j] = readArg(s, i)
        i = j
        push(`${texToSpeech(a)} con la barra`)
      } else if (cmd === "\\ce") {
        const [a, j] = readArg(s, i)
        i = j
        push(chemToSpeech(a))
      } else if (cmd === "\\pu") {
        const [a, j] = readArg(s, i)
        i = j
        push(a.replace(/\//g, " su ").replace(/\s+/g, " ").trim())
      } else if (SIMPLE[cmd]) push(SIMPLE[cmd])
      else if (/^\\[A-Za-z]+$/.test(cmd)) push(cmd.slice(1))
      continue
    }
    if (ch === "^" || ch === "_") {
      const [a, j] = readArg(s, i + 1)
      i = j
      const inner = texToSpeech(a)
      if (ch === "^") push(WORD_AFTER_POWER[a.trim()] ?? (/^-/.test(a.trim()) ? `alla meno ${texToSpeech(a.trim().slice(1))}` : `alla ${inner}`))
      else push(`indice ${inner}`)
      continue
    }
    if (ch === "{" || ch === "}") { i += 1; continue }
    if (ch === "(") { push("apri parentesi"); i += 1; continue }
    if (ch === ")") { push("chiudi parentesi"); i += 1; continue }
    if (ch === "[") { push("apri parentesi quadra"); i += 1; continue }
    if (ch === "]") { push("chiudi parentesi quadra"); i += 1; continue }
    if (ch === "|") { push("valore assoluto"); i += 1; continue }
    if (ch === ",") { push(/\d/.test(s[i - 1] ?? "") && /\d/.test(s[i + 1] ?? "") ? "virgola" : ""); i += 1; continue }
    if (/\d/.test(ch)) {
      const m = s.slice(i).match(/^\d+(?:[.,]\d+)?/)
      push(m[0])
      i += m[0].length
      continue
    }
    if (SIMPLE[ch]) { push(SIMPLE[ch]); i += 1; continue }
    if (/\p{L}/u.test(ch)) { push(ch); i += 1; continue }
    i += 1
  }
  return out.join(" ").replace(/\s+/g, " ").trim()
}

// ---- chemistry: "3 H2O" is "tre molecole: 6 atomi di idrogeno e 3 di ossigeno" -------------------------------------------------------------

// The Italian names of the elements of the programme; another symbol is read letter by letter. (The table chem/elements of T7 replaces this.)
export const ELEMENT_NAMES = {
  H: "idrogeno", He: "elio", Li: "litio", Be: "berillio", B: "boro", C: "carbonio", N: "azoto", O: "ossigeno", F: "fluoro", Ne: "neon", Na: "sodio",
  Mg: "magnesio", Al: "alluminio", Si: "silicio", P: "fosforo", S: "zolfo", Cl: "cloro", Ar: "argon", K: "potassio", Ca: "calcio", Sc: "scandio",
  Ti: "titanio", V: "vanadio", Cr: "cromo", Mn: "manganese", Fe: "ferro", Co: "cobalto", Ni: "nichel", Cu: "rame", Zn: "zinco", Ga: "gallio",
  Ge: "germanio", As: "arsenico", Se: "selenio", Br: "bromo", Kr: "kripton", Rb: "rubidio", Sr: "stronzio", Ag: "argento", Sn: "stagno",
  I: "iodio", Xe: "xeno", Ba: "bario", Au: "oro", Hg: "mercurio", Pb: "piombo", U: "uranio"
}
const NUMBER_WORDS = ["zero", "uno", "due", "tre", "quattro", "cinque", "sei", "sette", "otto", "nove", "dieci", "undici", "dodici"]
const say = (n) => (n >= 0 && n <= 12 ? NUMBER_WORDS[n] : String(n))

// The atoms of one formula (no coefficient): { symbol: count }, one bracket level.
function atomsOf(formula) {
  const counts = {}
  const walk = (text, times) => {
    const re = /([A-Z][a-z]?)(\d*)|\(([^()]*)\)(\d*)/g
    let m
    while ((m = re.exec(text))) {
      if (m[1]) counts[m[1]] = (counts[m[1]] ?? 0) + (m[2] ? Number(m[2]) : 1) * times
      else walk(m[3], times * (m[4] ? Number(m[4]) : 1))
    }
  }
  walk(formula.replace(/\^\{[^}]*\}|\^\S|\([aqsgl]+\)|[+-]$/g, ""), 1)
  return counts
}

function speakFormula(term) {
  const m = term.match(/^(\d+)?\s*(.+)$/)
  const coefficient = m[1] ? Number(m[1]) : 1
  const atoms = Object.entries(atomsOf(m[2])).map(([s, n]) => [s, n * coefficient])
  if (atoms.length === 0) return term
  const list = atoms.map(([s, n], i) => {
    const name = ELEMENT_NAMES[s] ?? s.split("").join(" ")
    return i === 0 ? `${n} ${n === 1 ? "atomo" : "atomi"} di ${name}` : `${n} di ${name}`
  })
  const sentence = list.length === 1 ? list[0] : `${list.slice(0, -1).join(", ")} e ${list[list.length - 1]}`
  const lead = coefficient > 1 ? `${say(coefficient)} molecole: ` : ""
  return `${lead}${sentence}`
}

// \ce{...} -> words: terms separated by + and arrows; each term by its atoms.
export function chemToSpeech(ce) {
  const parts = String(ce).split(/(\s*(?:<=>|<->|->|<-|=)\s*|\s\+\s)/)
  const words = []
  for (const part of parts) {
    const p = part.trim()
    if (!p) continue
    if (p === "+") words.push("più")
    else if (p === "->") words.push("dà")
    else if (p === "<=>" || p === "<->") words.push("è in equilibrio con")
    else if (p === "<-") words.push("proviene da")
    else if (p === "=") words.push("uguale")
    else words.push(speakFormula(p.replace(/\\[A-Za-z]+/g, "")))
  }
  return words.join(", ")
}

// ---- code and bits ---------------------------------------------------------------------------------------------------------------------------

const SYMBOL_NAMES = [
  ["<=", "minore o uguale a"], [">=", "maggiore o uguale a"], ["<>", "diverso da"], ["==", "uguale uguale"], ["!=", "diverso da"], ["&&", "e"], ["||", "o"],
  ["+=", "più uguale"], ["-=", "meno uguale"], ["<-", "prende"], ["←", "prende"], ["=", "uguale"], ["<", "minore di"], [">", "maggiore di"], ["+", "più"],
  ["-", "meno"], ["*", "per"], ["/", "diviso"], ["%", "resto"], ["(", "apri parentesi"], [")", "chiudi parentesi"], ["[", "apri quadra"], ["]", "chiudi quadra"],
  ["{", "apri graffa"], ["}", "chiudi graffa"], [";", "punto e virgola"], [",", "virgola"], ['"', "virgolette"], ["'", "apice"], ["$", "dollaro"],
  [".", "punto"], [":", "due punti"], ["&", "e commerciale"], ["_", "trattino basso"]
]

// A code span read with the names of its symbols ("k < 40" is "k minore di 40").
export function codeToSpeech(code) {
  let rest = String(code)
  const words = []
  while (rest.length > 0) {
    if (/^\s/.test(rest)) { rest = rest.trimStart(); continue }
    const symbol = SYMBOL_NAMES.find(([sym]) => rest.startsWith(sym))
    if (symbol && !(symbol[0] === "." && /^\.\d/.test(rest) && /\d$/.test(words[words.length - 1] ?? ""))) {
      words.push(symbol[1])
      rest = rest.slice(symbol[0].length)
      continue
    }
    const run = rest.match(/^[\p{L}\p{N}]+/u)
    if (run) { words.push(run[0]); rest = rest.slice(run[0].length) } else rest = rest.slice(1)
  }
  return words.join(" ")
}

// Bits digit by digit, a comma between groups of four (they make the device pause): "01101011" is "zero uno uno zero, uno zero uno uno".
export function bitsToSpeech(bits) {
  const digits = String(bits).replace(/[^01]/g, "")
  const names = { 0: "zero", 1: "uno" }
  const groups = []
  for (let i = 0; i < digits.length; i += 4) groups.push(digits.slice(i, i + 4).split("").map((d) => names[d]).join(" "))
  return groups.join(", ")
}

// Plain text as the device should say it: arrows and signs that a voice would skip or spell badly.
export function plainToSpeech(text) {
  return String(text)
    .replace(/←/g, " prende ").replace(/→/g, " diventa ").replace(/≠/g, " diverso da ").replace(/≤/g, " minore o uguale a ").replace(/≥/g, " maggiore o uguale a ")
    .replace(/×/g, " per ").replace(/÷/g, " diviso ").replace(/−/g, " meno ").replace(/(\d)\s*%/g, "$1 per cento")
    .replace(/\s+/g, " ")
}
