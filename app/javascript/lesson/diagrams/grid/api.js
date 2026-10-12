// The grid API (WAVE2 2.5; contract frozen in W2-0, built first by T9, consumed by T3 and T7): cells with fixed widths (every digit in its own
// cell), header rows and columns, outlines around cell groups (the "boot" of Spanish verbs), per-cell tap (hear, reveal, card), `hide` cells,
// stacking rules on a phone, declared scroll frames (only `sheet` uses one; a map pan is never needed).
// The functions live in grid/engine.js (with the helpers readingOrder, fitSize, cellAt, isHidden, GridError for the types that use the engine);
// this file keeps the frozen names and signatures.
import * as engine from "lesson/diagrams/grid/engine"

// grid({ rows, cols, widths, heights, headerRows, headerCols, cells }) -> Grid : widths and heights in px (a number, or one per column / row).
//   `hide` and `tap` are CELL ATTRIBUTES, not options of the grid: cells is a sparse list [{ row, col, hide?: true, tap?: "hear" | "reveal" | "card" }].
//   A hidden cell is drawn empty and its value is never in the Grid (L10): the grid holds geometry and attributes, never text. A tap cell
//   carries an `id` ("r2c3", 0-based): the id of the popover or reveal it opens. Bad arguments throw an engine.GridError.
export const grid = (spec) => engine.build(spec)

// cellBox(grid, row, col) -> { x, y, w, h }
export const cellBox = (g, row, col) => engine.cellBox(g, row, col)

// outline(grid, cells, { kind }) -> { d } : the path around a group of cells ([{ row, col }]); kind "boot" (inset, rounded corners) | "frame" (on the edges)
export const outline = (g, cells, options) => engine.outline(g, cells, options)

// stackForPhone(grid, width) -> [{ title_it, cells }] : below 600 px a grid wider than the room opens into sections (one per data row) in reading order
export const stackForPhone = (g, width) => engine.stackForPhone(g, width)

// scrollFrame(grid, { fixedFirstColumn }) -> { bbox, scroll: true, fixedFirstColumn } : a declared horizontal scroll frame (Scene frames[])
export const scrollFrame = (g, options) => engine.scrollFrame(g, options)

// cellTargets(grid, set) -> [{ key, bbox, neutral_it }] : the select targets of a set of cells ([{ row, col }], "cells" or "all"), in reading order
export const cellTargets = (g, set) => engine.cellTargets(g, set)

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
export const CELL_ATTRIBUTES = engine.CELL_ATTRIBUTES
export const TAP_KINDS = engine.TAP_KINDS
