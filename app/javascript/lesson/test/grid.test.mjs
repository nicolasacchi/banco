// The grid engine (WAVE2 2.5; T9): geometry, cell attributes, outlines, phone stacking, scroll frames and select targets.
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"

const api = await import("lesson/diagrams/grid/api")
const engine = await import("lesson/diagrams/grid/engine")

const g = api.grid({ rows: 3, cols: 4, widths: [40, 30, 30, 30], heights: 20, headerRows: 1, headerCols: 1, cells: [{ row: 1, col: 2, hide: true }, { row: 2, col: 1, tap: "reveal" }] })

test("a grid is geometry: edges, size and only the attributes it was given, never a value", () => {
  assert.deepEqual(g.xs, [0, 40, 70, 100, 130])
  assert.deepEqual(g.ys, [0, 20, 40, 60])
  assert.equal(g.width, 130)
  assert.equal(g.height, 60)
  assert.deepEqual(g.cells, [{ row: 1, col: 2, id: "r1c2", hide: true }, { row: 2, col: 1, id: "r2c1", tap: "reveal" }])
  assert.deepEqual(Object.keys(g).sort(), ["cells", "cols", "headerCols", "headerRows", "height", "heights", "rows", "width", "widths", "xs", "ys"])
  assert.ok(Object.isFrozen(g))
})

test("cellBox gives the box of a cell and refuses a cell outside", () => {
  assert.deepEqual(api.cellBox(g, 1, 2), { x: 70, y: 20, w: 30, h: 20 })
  assert.deepEqual(api.cellBox(g, 0, 0), { x: 0, y: 0, w: 40, h: 20 })
  assert.throws(() => api.cellBox(g, 3, 0), engine.GridError)
  assert.throws(() => api.cellBox(g, 0, -1), engine.GridError)
})

test("bad arguments throw a GridError", () => {
  const ok = { rows: 2, cols: 2, widths: 10, heights: 10 }
  assert.throws(() => api.grid({ ...ok, rows: 0 }), engine.GridError)
  assert.throws(() => api.grid({ ...ok, widths: [10] }), engine.GridError)
  assert.throws(() => api.grid({ ...ok, widths: -3 }), engine.GridError)
  assert.throws(() => api.grid({ ...ok, headerRows: 3 }), engine.GridError)
  assert.throws(() => api.grid({ ...ok, cells: [{ row: 0, col: 5 }] }), engine.GridError)
  assert.throws(() => api.grid({ ...ok, cells: [{ row: 0, col: 0, tap: "drag" }] }), engine.GridError)
  assert.throws(() => api.grid({ ...ok, cells: [{ row: 0, col: 0, text: "x" }] }), engine.GridError, "a cell carries no text")
  assert.throws(() => api.grid({ ...ok, cells: [{ row: 0, col: 0 }, { row: 0, col: 0, hide: true }] }), engine.GridError)
})

test("outline: a frame of one cell, an L shape and a ring with a hole", () => {
  const one = api.grid({ rows: 2, cols: 2, widths: 10, heights: 10 })
  assert.equal(api.outline(one, [{ row: 0, col: 0 }]).d, "M0 0 L10 0 L10 10 L0 10 Z")
  const l = api.outline(one, [{ row: 0, col: 0 }, { row: 1, col: 0 }, { row: 1, col: 1 }]).d
  assert.equal(l, "M0 0 L10 0 L10 10 L20 10 L20 20 L0 20 Z")
  const big = api.grid({ rows: 3, cols: 3, widths: 10, heights: 10 })
  const ring = [0, 1, 2].flatMap((r) => [0, 1, 2].map((c) => ({ row: r, col: c }))).filter((c) => !(c.row === 1 && c.col === 1))
  const d = api.outline(big, ring).d
  assert.equal((d.match(/M/g) ?? []).length, 2, "an outer loop and an inner one")
  assert.match(d, /M20 10 L10 10 L10 20 L20 20 Z$/, "the hole runs the other way round")
})

test("outline: the boot is inset and rounded, and stays inside the cells", () => {
  const d = api.outline(g, [{ row: 1, col: 1 }, { row: 1, col: 2 }], { kind: "boot" }).d
  assert.match(d, /Q/)
  const nums = [...d.matchAll(/-?\d+(?:\.\d+)?/g)].map((m) => Number(m[0]))
  assert.ok(nums.every((n) => n >= 0 && n <= 130))
  // the leftmost x of the group is 40, the inset 3: nothing is drawn left of 43 - rounding, nothing right of 97
  const xs = nums.filter((_, i) => i % 2 === 0)
  assert.equal(Math.min(...xs), 43)
  assert.equal(Math.max(...xs), 97)
  assert.throws(() => api.outline(g, [], { kind: "boot" }), engine.GridError)
  assert.throws(() => api.outline(g, [{ row: 0, col: 0 }], { kind: "wavy" }), engine.GridError)
})

test("outline: two cells apart make two loops", () => {
  const d = api.outline(g, [{ row: 0, col: 0 }, { row: 2, col: 3 }]).d
  assert.equal((d.match(/M/g) ?? []).length, 2)
})

test("stackForPhone: one section from 600 px or when it fits, a section per data row below", () => {
  assert.equal(api.stackForPhone(g, 800).length, 1)
  assert.equal(api.stackForPhone(g, 800)[0].cells.length, 12)
  assert.equal(api.stackForPhone(g, 390).length, 1, "130 px fit 390 px")
  const wide = api.grid({ rows: 4, cols: 6, widths: 80, heights: 30, headerRows: 1, headerCols: 1 })
  const parts = api.stackForPhone(wide, 390)
  assert.equal(parts.length, 3)
  assert.deepEqual(parts.map((p) => p.title_it), ["Riga 1", "Riga 2", "Riga 3"])
  assert.deepEqual(parts[0].cells.slice(0, 2), [{ row: 1, col: 0 }, { row: 1, col: 1 }])
  assert.equal(parts[0].cells.length, 6)
  assert.equal(api.stackForPhone(wide, 640).length, 1)
})

test("scrollFrame covers the grid and says whether the first column stays", () => {
  assert.deepEqual(api.scrollFrame(g, { fixedFirstColumn: true }), { bbox: { x: 0, y: 0, w: 130, h: 60 }, scroll: true, fixedFirstColumn: true })
  assert.equal(api.scrollFrame(g).fixedFirstColumn, false)
})

test("cellTargets: reading order, no content, hidden cells included, the header left out for 'cells'", () => {
  const all = api.cellTargets(g, "cells")
  assert.equal(all.length, 6)
  assert.deepEqual(all.map((t) => t.key), ["r1c1", "r1c2", "r1c3", "r2c1", "r2c2", "r2c3"])
  assert.equal(all[1].neutral_it, "Riga 2, colonna 3")
  assert.deepEqual(all[0].bbox, { x: 40, y: 20, w: 30, h: 20 })
  const some = api.cellTargets(g, [{ row: 2, col: 3 }, { row: 0, col: 0 }, { row: 2, col: 3 }])
  assert.deepEqual(some.map((t) => t.key), ["r0c0", "r2c3"])
  assert.equal(api.cellTargets(g, "all").length, 12)
  assert.throws(() => api.cellTargets(g, "digits"), engine.GridError)
})

test("fitSize: as wide as the room allows between the target minimum and the cap", () => {
  assert.equal(engine.fitSize(8, 300), 37)
  assert.equal(engine.fitSize(8, 2000), 56)
  assert.equal(engine.fitSize(16, 200), 24)
})
