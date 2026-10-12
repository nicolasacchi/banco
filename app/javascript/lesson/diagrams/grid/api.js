// The grid API (WAVE2 2.5; contract frozen in W2-0, built first by T9, consumed by T3 and T7): cells with fixed widths (every digit in its own
// cell), header rows and columns, outlines around cell groups (the "boot" of Spanish verbs), per-cell tap (hear, reveal, card), `hide` cells,
// stacking rules on a phone, declared scroll frames (only `sheet` uses one; a map pan is never needed).
import { notBuilt } from "lesson/lib/not_built"

// grid({ rows, cols, widths, heights, headerRows, headerCols, cells }) -> Grid : widths and heights in px.
//   `hide` and `tap` are CELL ATTRIBUTES, not options of the grid: cells is a sparse list [{ row, col, hide?: true, tap?: "hear" | "reveal" | "card" }].
//   A hidden cell is drawn empty and its value is never in the Grid (L10); a tap cell carries the id of the popover or reveal it opens.
export const grid = notBuilt("grid/api.grid", "T9", "w2-1")

// cellBox(grid, row, col) -> { x, y, w, h }
export const cellBox = notBuilt("grid/api.cellBox", "T9", "w2-1")

// outline(grid, cells, { kind }) -> { d } : the path around a group of cells; kind "boot" | "frame"
export const outline = notBuilt("grid/api.outline", "T9", "w2-1")

// stackForPhone(grid, width) -> [{ title_it, cells }] : below 600 px a grid opens into sections in reading order
export const stackForPhone = notBuilt("grid/api.stackForPhone", "T9", "w2-1")

// scrollFrame(grid, { fixedFirstColumn }) -> { bbox, scroll: true } : a declared horizontal scroll frame (Scene frames[])
export const scrollFrame = notBuilt("grid/api.scrollFrame", "T9", "w2-1")

// cellTargets(grid, set) -> [{ key, bbox, neutral_it }] : the select targets of a set of cells, in reading order
export const cellTargets = notBuilt("grid/api.cellTargets", "T9", "w2-1")

// The frozen signatures, one string per function (checked by lesson/test/contract.test.mjs against the exports).
export const SIGNATURES = {
  grid: "grid({ rows, cols, widths, heights, headerRows, headerCols, cells })",
  cellBox: "cellBox(grid, row, col)",
  outline: "outline(grid, cells, { kind })",
  stackForPhone: "stackForPhone(grid, width)",
  scrollFrame: "scrollFrame(grid, { fixedFirstColumn })",
  cellTargets: "cellTargets(grid, set)",
}
// The attributes a cell may carry in grid({ cells }).
export const CELL_ATTRIBUTES = ["row", "col", "hide", "tap"]
export const TAP_KINDS = ["hear", "reveal", "card"]
