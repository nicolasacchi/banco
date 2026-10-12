// Sheet: Calc formulas in Italian (functions, ';' separators, $ references): evaluation without loops or recursion, fill shift.
// Contract stub of W2-0 (WAVE2 1.10, batch w2-3, track T9): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// lib/lessons/sheet.rb and both run test/fixtures/lesson2/sheet.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "evaluate": "evaluate(cells, ref)",
  "fill": "fill(formula, rows, cols)"
}

// The value of a cell.
export const evaluate = notBuilt("sheet.evaluate", "T9", "w2-3")
// A formula copied by an offset, with $ parts fixed.
export const fill = notBuilt("sheet.fill", "T9", "w2-3")
