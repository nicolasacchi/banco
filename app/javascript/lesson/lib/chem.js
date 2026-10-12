// Chem: The formula grammar (case-exact symbols from chem/elements, one bracket level), atom counts and classes.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T7): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/chem.rb and both run test/fixtures/lesson2/chem_formulas.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "parse": "parse(formula)",
  "count": "count(formula)",
  "classify": "classify(formula)",
  "same_composition": "sameComposition(a, b)"
}

// A formula as {coefficient, groups}; nil when it does not parse.
export const parse = notBuilt("chem.parse", "T7", "w2-1")
// Atoms by symbol, coefficient included.
export const count = notBuilt("chem.count", "T7", "w2-1")
// 'element' or 'compound'.
export const classify = notBuilt("chem.classify", "T7", "w2-1")
// Whether two formulas have the same atom counts (a near miss of a typed answer).
export const sameComposition = notBuilt("chem.sameComposition", "T7", "w2-1")
