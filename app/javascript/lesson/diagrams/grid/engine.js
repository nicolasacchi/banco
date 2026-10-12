// The grid engine (WAVE2 2.5; T9). Geometry only: a grid never holds a cell's text, so a hidden cell's value cannot be in it (L2, L10).
// The six functions of the frozen interface are exported through grid/api.js; the helpers below are for the types that use the engine.
//
// A Grid is plain data: { rows, cols, widths[], heights[], xs[], ys[], width, height, headerRows, headerCols, cells[] }.
//   xs[c] / ys[r] are the left / top edge of column c / row r (px, whole grid at 0,0); cells[] holds only the cells that carry an
//   attribute: { row, col, id, hide?, tap? }, in reading order. `id` ("r2c3", 0-based) is what a popover or reveal is keyed by.
// Bad arguments throw a GridError (a programmer error: the types validate their data before they build a grid).
export class GridError extends Error {}

// The attributes a cell may carry in grid({ cells }), and the kinds of tap.
export const CELL_ATTRIBUTES = ["row", "col", "hide", "tap"]
export const TAP_KINDS = ["hear", "reveal", "card"]

export const MAX_ROWS = 60
export const MAX_COLS = 30
export const PHONE_BELOW = 600

const key = (row, col) => `r${row}c${col}`
const round = (n) => Math.round(n * 100) / 100

function axis(name, count, given) {
  const list = Array.isArray(given) ? given : Array.from({ length: count }, () => given)
  if (list.length !== count) throw new GridError(`${name}: ${count} sizes expected, ${list.length} given`)
  for (const v of list) if (!(typeof v === "number" && Number.isFinite(v) && v > 0)) throw new GridError(`${name}: a size is not a positive number`)
  return list
}

function edges(sizes) {
  const out = [0]
  for (const s of sizes) out.push(out[out.length - 1] + s)
  return out
}

export function build({ rows, cols, widths, heights, headerRows = 0, headerCols = 0, cells = [] } = {}) {
  if (!Number.isInteger(rows) || rows < 1 || rows > MAX_ROWS) throw new GridError(`rows: 1 to ${MAX_ROWS}`)
  if (!Number.isInteger(cols) || cols < 1 || cols > MAX_COLS) throw new GridError(`cols: 1 to ${MAX_COLS}`)
  if (!Number.isInteger(headerRows) || headerRows < 0 || headerRows > rows) throw new GridError("headerRows is outside the grid")
  if (!Number.isInteger(headerCols) || headerCols < 0 || headerCols > cols) throw new GridError("headerCols is outside the grid")
  const w = axis("widths", cols, widths)
  const h = axis("heights", rows, heights)
  const seen = new Map()
  for (const cell of cells) {
    for (const k of Object.keys(cell)) if (!CELL_ATTRIBUTES.includes(k)) throw new GridError(`a cell has no attribute ${k}`)
    const { row, col } = cell
    if (!Number.isInteger(row) || !Number.isInteger(col) || row < 0 || col < 0 || row >= rows || col >= cols) throw new GridError(`a cell lies outside the grid (${row}, ${col})`)
    if (cell.hide !== undefined && typeof cell.hide !== "boolean") throw new GridError("hide is true or false")
    if (cell.tap !== undefined && !TAP_KINDS.includes(cell.tap)) throw new GridError(`tap is one of ${TAP_KINDS.join(", ")}`)
    if (seen.has(key(row, col))) throw new GridError(`the cell ${key(row, col)} is described twice`)
    const norm = { row, col, id: key(row, col) }
    if (cell.hide) norm.hide = true
    if (cell.tap) norm.tap = cell.tap
    seen.set(norm.id, norm)
  }
  const list = [...seen.values()].sort((a, b) => a.row - b.row || a.col - b.col)
  const xs = edges(w)
  const ys = edges(h)
  return Object.freeze({ rows, cols, widths: w, heights: h, xs, ys, width: round(xs[cols]), height: round(ys[rows]), headerRows, headerCols, cells: list })
}

// The attributes of one cell, or null when it carries none.
export function cellAt(g, row, col) {
  return g.cells.find((c) => c.row === row && c.col === col) ?? null
}

export const isHeader = (g, row, col) => row < g.headerRows || col < g.headerCols
export const isHidden = (g, row, col) => cellAt(g, row, col)?.hide === true

export function cellBox(g, row, col) {
  if (!Number.isInteger(row) || !Number.isInteger(col) || row < 0 || col < 0 || row >= g.rows || col >= g.cols) throw new GridError(`a cell lies outside the grid (${row}, ${col})`)
  return { x: round(g.xs[col]), y: round(g.ys[row]), w: round(g.widths[col]), h: round(g.heights[row]) }
}

// Every cell of the grid in reading order (rows from the top, columns from the left).
export function readingOrder(g) {
  const out = []
  for (let r = 0; r < g.rows; r++) for (let c = 0; c < g.cols; c++) out.push({ row: r, col: c })
  return out
}

function normalizeSet(g, set) {
  let list
  if (set === "all") list = readingOrder(g)
  else if (set === "cells") list = readingOrder(g).filter(({ row, col }) => !isHeader(g, row, col))
  else if (Array.isArray(set)) list = set
  else throw new GridError("a set of cells is a list of { row, col }, or \"cells\" or \"all\"")
  const seen = new Set()
  const out = []
  for (const { row, col } of list) {
    if (!Number.isInteger(row) || !Number.isInteger(col) || row < 0 || col < 0 || row >= g.rows || col >= g.cols) throw new GridError(`a cell lies outside the grid (${row}, ${col})`)
    if (seen.has(key(row, col))) continue
    seen.add(key(row, col))
    out.push({ row, col })
  }
  return out.sort((a, b) => a.row - b.row || a.col - b.col)
}

// The path around a group of cells. The boundary of the union is traced as directed edges (clockwise on the screen), which keeps the
// region on the right of every edge, so one inward shift works for outer boundaries and for holes alike. kind "boot" insets the line
// by 3 px and rounds its corners (the outline around a change mark); "frame" is the plain rectilinear boundary on the cell edges.
export function outline(g, group, { kind = "frame" } = {}) {
  if (kind !== "boot" && kind !== "frame") throw new GridError("kind is boot or frame")
  const cells = normalizeSet(g, group)
  if (cells.length === 0) throw new GridError("an outline needs at least one cell")
  const inside = new Set(cells.map(({ row, col }) => key(row, col)))
  const out = new Map()
  const add = (a, b) => {
    const back = out.get(`${b[0]},${b[1]}`)
    const idx = back ? back.findIndex((e) => e.to[0] === a[0] && e.to[1] === a[1]) : -1
    if (idx >= 0) {
      back.splice(idx, 1)
      return
    }
    const list = out.get(`${a[0]},${a[1]}`) ?? []
    list.push({ from: a, to: b })
    out.set(`${a[0]},${a[1]}`, list)
  }
  for (const { row, col } of cells) {
    const x0 = g.xs[col]
    const x1 = g.xs[col + 1]
    const y0 = g.ys[row]
    const y1 = g.ys[row + 1]
    if (!inside.has(key(row - 1, col))) add([x0, y0], [x1, y0])
    if (!inside.has(key(row, col + 1))) add([x1, y0], [x1, y1])
    if (!inside.has(key(row + 1, col))) add([x1, y1], [x0, y1])
    if (!inside.has(key(row, col - 1))) add([x0, y1], [x0, y0])
  }
  const loops = []
  const take = () => {
    for (const list of out.values()) if (list.length) return list.shift()
    return null
  }
  for (let e = take(); e; e = take()) {
    const loop = [e.from]
    let at = e
    for (;;) {
      loop.push(at.to)
      if (at.to[0] === e.from[0] && at.to[1] === e.from[1]) break
      const next = out.get(`${at.to[0]},${at.to[1]}`)?.shift()
      if (!next) break
      at = next
    }
    loop.pop()
    loops.push(loop)
  }
  const inset = kind === "boot" ? 3 : 0
  const radius = kind === "boot" ? 8 : 0
  return { d: loops.map((loop) => loopPath(loop, inset, radius)).join(" ") }
}

function simplify(points) {
  const out = []
  const n = points.length
  for (let i = 0; i < n; i++) {
    const a = points[(i + n - 1) % n]
    const b = points[i]
    const c = points[(i + 1) % n]
    const straight = (a[0] === b[0] && b[0] === c[0]) || (a[1] === b[1] && b[1] === c[1])
    if (!straight) out.push(b)
  }
  return out
}

function loopPath(raw, inset, radius) {
  const pts = simplify(raw)
  const n = pts.length
  const unit = (a, b) => {
    const len = Math.hypot(b[0] - a[0], b[1] - a[1])
    return [(b[0] - a[0]) / len, (b[1] - a[1]) / len, len]
  }
  const moved = pts.map((p, i) => {
    const d1 = unit(pts[(i + n - 1) % n], p)
    const d2 = unit(p, pts[(i + 1) % n])
    // the inward side of a direction (dx, dy) is (-dy, dx): the region lies on the right of every edge
    return [p[0] + inset * (-d1[1] - d2[1]), p[1] + inset * (d1[0] + d2[0])]
  })
  const f = (p) => `${round(p[0])} ${round(p[1])}`
  if (!radius) return `M${moved.map(f).join(" L")} Z`
  const parts = []
  moved.forEach((p, i) => {
    const prev = moved[(i + n - 1) % n]
    const next = moved[(i + 1) % n]
    const a = unit(prev, p)
    const b = unit(p, next)
    const r = Math.min(radius, a[2] / 2, b[2] / 2)
    const start = [p[0] - a[0] * r, p[1] - a[1] * r]
    const end = [p[0] + b[0] * r, p[1] + b[1] * r]
    parts.push(`${i === 0 ? "M" : "L"}${f(start)} Q${f(p)} ${f(end)}`)
  })
  return `${parts.join(" ")} Z`
}

// Below 600 px a grid that is wider than the room opens into sections in reading order: one per row of data, the row's header cells
// first. The title is a plain "Riga N" that the type replaces with its own words (the grid holds no text). A grid that fits, or any
// width from 600 px on, is one section.
export function stackForPhone(g, width) {
  if (!(width < PHONE_BELOW && g.width > width) || g.rows - g.headerRows < 2) return [{ title_it: "", cells: readingOrder(g) }]
  const sections = []
  for (let r = g.headerRows; r < g.rows; r++) {
    const cells = []
    for (let c = 0; c < g.cols; c++) cells.push({ row: r, col: c })
    sections.push({ title_it: `Riga ${r - g.headerRows + 1}`, cells, row: r })
  }
  return sections
}

export function scrollFrame(g, { fixedFirstColumn = false } = {}) {
  return { bbox: { x: 0, y: 0, w: round(g.width), h: round(g.height) }, scroll: true, fixedFirstColumn: Boolean(fixedFirstColumn) }
}

// The select targets of a set of cells, in reading order, all in the same neutral words (L3): the place only, never the content.
export function cellTargets(g, set) {
  return normalizeSet(g, set).map(({ row, col }) => ({ key: key(row, col), bbox: cellBox(g, row, col), neutral_it: `Riga ${row + 1}, colonna ${col + 1}` }))
}

// Equal widths for `count` cells that must fit `avail` px: as wide as `max`, never under `min` (the target size of A2 is 24 px).
export function fitSize(count, avail, { min = 24, max = 56 } = {}) {
  return Math.max(min, Math.min(max, Math.floor(avail / count)))
}
