// Words typed into an expression field (D-318). The MathLive field turns typed letters into
// \operatorname{..}, \text{..} or \mathrm{..} (known shortcuts) or into a run of single letters
// ("thereisnovalue"). The answer is an expression, so the page shows a short line under the field.
// Nothing is blocked and nothing is graded here: this only decides whether to show the line.

// Names a student may type on purpose (MathLive writes most of them as \sin and the like).
export const KNOWN_NAMES = new Set([
  "sin", "cos", "tan", "cot", "sec", "csc", "sen", "tg", "ctg", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
  "log", "ln", "lg", "exp", "lim", "max", "min", "mod", "gcd", "lcm", "mcm", "mcd", "det", "deg", "arg", "inf", "sup", "rad"
])

const WRAPPER = /\\(?:operatorname\*?|text|textrm|textit|textbf|mathrm|mathit|mathsf|mathtt|mbox)\s*\{([^{}]*)\}/g
const COMMAND = /\\[A-Za-z]+/g
const MIN_RUN = 3

// The letters the item itself writes in its formulas ($..$ in its texts): its own variables.
export function itemLetters(part) {
  const letters = new Set()
  const walk = (value) => {
    if (typeof value === "string") {
      for (const [, math] of value.matchAll(/\$([^$]*)\$/g)) {
        for (const [letter] of math.replace(COMMAND, " ").matchAll(/[A-Za-z]/g)) letters.add(letter.toLowerCase())
      }
    } else if (Array.isArray(value)) value.forEach(walk)
    else if (value && typeof value === "object") Object.values(value).forEach(walk)
  }
  walk(part)
  return letters
}

// latex: the field's value. own: a Set of lower-case letters (see itemLetters).
export function hasTypedWords(latex, own = new Set()) {
  if (typeof latex !== "string" || latex === "") return false
  let flat = latex
  // Innermost wrappers first: \operatorname{\mathrm{th}} -> \operatorname{th} -> th.
  for (let i = 0; i < 8; i += 1) {
    const next = flat.replace(WRAPPER, "$1")
    if (next === flat) break
    flat = next
  }
  flat = flat.replace(COMMAND, " ")
  for (const [run] of flat.matchAll(/[A-Za-z]+/g)) {
    const word = run.toLowerCase()
    if (word.length < MIN_RUN) continue
    if (KNOWN_NAMES.has(word)) continue
    if ([...word].every((c) => own.has(c))) continue
    return true
  }
  return false
}
