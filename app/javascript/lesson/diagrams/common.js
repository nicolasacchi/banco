// Shared by the diagram layouts (A7): the context of one layout, state merging, label placement, the
// estimator that stands in for the browser's measurement in node, and the final check of a Scene.
// Everything here is pure.

export const COMPACT = 6

export function fail(path, message, code = "E-LESSON-DIAGRAM") {
  return { error: { path, message, code } }
}

export const isError = (x) => x && x.error !== undefined

// Plain text of a label: "$...$" kept readable ("x" for "$x$"), markup removed. For descriptions.
export function plain(text) {
  return String(text ?? "").replace(/\\\$/g, "\u0000").replace(/\$/g, "").replace(/\u0000/g, "$")
    .replace(/\\role\{[a-z-]+\}\{([^{}]*)\}/g, "$1").replace(/\\cdot/g, "·").replace(/\\times/g, "×")
    .replace(/\\neq/g, "≠").replace(/\\le(?![a-z])/g, "≤").replace(/\\ge(?![a-z])/g, "≥")
    .replace(/\\frac\{([^{}]*)\}\{([^{}]*)\}/g, "$1/$2").replace(/\\to/g, "→").replace(/\\[a-zA-Z]+/g, "").replace(/[{}]/g, "")
}

// Atkinson-like metrics: good enough to lay out in node and to bound the browser's real measurement.
export function estimate(text, px, maxW) {
  const lineH = Math.ceil(px * 1.4)
  const clean = plain(text)
  const word = (w) => {
    let total = 0
    for (const ch of w) {
      if (/[ilI.,;:'!|]/.test(ch)) total += 0.3
      else if (/[mwMW]/.test(ch)) total += 0.85
      else if (/[A-Z0-9]/.test(ch)) total += 0.62
      else if (/\s/.test(ch)) total += 0.3
      else total += 0.54
    }
    return total * px
  }
  const space = 0.3 * px
  if (!maxW) return { w: Math.ceil(word(clean)), h: lineH }
  const words = clean.split(/\s+/).filter(Boolean)
  let lines = 1
  let line = 0
  let widest = 0
  for (const w of words) {
    const ww = word(w)
    if (line > 0 && line + space + ww > maxW) {
      widest = Math.max(widest, line)
      lines += 1
      line = ww
    } else line = line > 0 ? line + space + ww : ww
  }
  widest = Math.max(widest, line)
  return { w: Math.ceil(Math.min(widest, Math.max(maxW, widest))), h: lines * lineH }
}

// The state i of a diagram: the top level overlaid shallowly by states[i] (A7). Idempotent on a served,
// already merged state. Returns { ...top (without states), ...state }.
export function effectiveState(data, i) {
  const { states, ...top } = data
  if (!Array.isArray(states) || states.length === 0) return top
  return { ...top, ...states[Math.min(i, states.length - 1)] }
}

export const stateCount = (data) => (Array.isArray(data.states) && data.states.length > 0 ? data.states.length : 1)

export function makeContext(data, opts) {
  const fontPx = Math.max(18, opts.fontPx ?? 20)
  const measure = opts.measure ?? estimate
  const lineH = Math.ceil(fontPx * 1.4)
  return {
    width: Math.max(240, Math.floor(opts.width ?? 600)),
    fontPx,
    lineH,
    measure: (text, px = fontPx, maxW) => measure(text, px, maxW),
    state: Math.max(0, opts.state ?? 0),
    tryValue: opts.tryValue,
    pad: Math.round(fontPx * 0.4),
    shapes: [],
    labels: [],
    palette: opts.palette ?? null,
    validateTex: opts.validateTex ?? null,
    icons: opts.icons ?? null,
    subject: opts.subject ?? "math"
  }
}

// Puts a label. (ax, ay) is the anchor: anchor "start" (left edge), "middle" (centre) or "end" (right edge)
// horizontally; valign "top" | "middle" | "bottom" vertically. maxW wraps. Returns the label (with its box).
export function label(ctx, text, ax, ay, { anchor = "middle", valign = "top", maxW, cls = "", px, key, role, tag } = {}) {
  const size = Math.max(px ?? ctx.fontPx, ctx.fontPx)
  const m = ctx.measure(text, size, maxW)
  const w = Math.min(m.w, maxW ?? m.w)
  const h = m.h
  const x = anchor === "start" ? ax : anchor === "end" ? ax - w : ax - w / 2
  const y = valign === "top" ? ay : valign === "bottom" ? ay - h : ay - h / 2
  const item = { x: Math.round(x), y: Math.round(y), w: Math.ceil(w), h: Math.ceil(h), anchor, text_it: text, cls, px: size }
  if (maxW && m.h > ctx.lineH) item.wrap = true
  if (key) item.key = key
  if (role) item.role = role
  if (tag) item.tag = tag
  ctx.labels.push(item)
  return item
}

export function shape(ctx, kind, attrs) {
  const s = { kind, ...attrs }
  ctx.shapes.push(s)
  return s
}

// Shifts a label horizontally so that its box lies inside [0, width].
export function clampX(ctx, item) {
  item.x = Math.max(0, Math.min(item.x, ctx.width - item.w))
  return item
}

export const overlaps = (a, b) => a.x < b.x + b.w - 0.5 && b.x < a.x + a.w - 0.5 && a.y < b.y + b.h - 0.5 && b.y < a.y + a.h - 0.5

export function hasOverlap(ctx) {
  const labels = ctx.labels
  for (let i = 0; i < labels.length; i++) for (let j = i + 1; j < labels.length; j++) if (overlaps(labels[i], labels[j])) return true
  return labels.some((l) => l.x < -0.5 || l.x + l.w > ctx.width + 0.5)
}

// The last check of a layout: every label inside the width, none under the base size, none over another.
export function finish(ctx, height, extra = {}) {
  const labels = ctx.labels
  for (let i = 0; i < labels.length; i++) {
    const a = labels[i]
    if (a.px < ctx.fontPx - 0.01) return fail("", `a label is under the base size (${a.text_it})`, "E-DIAGRAM-SMALL-TEXT")
    if (a.x < -0.5 || a.x + a.w > ctx.width + 0.5) return fail("", `a label does not fit the width (${a.text_it})`, "E-DIAGRAM-LAYOUT")
    for (let j = i + 1; j < labels.length; j++) {
      if (overlaps(a, labels[j])) return fail("", `two labels overlap (${a.text_it} and ${labels[j].text_it})`, "E-DIAGRAM-LAYOUT")
    }
  }
  return { width: ctx.width, height: Math.ceil(height), shapes: ctx.shapes, labels, ...extra }
}

// The roles of a subject: the common ones and the subject's own.
export function roleNames(palette, subject) {
  return new Set([...Object.keys(palette.common), ...Object.keys(palette.subjects[subject] ?? {})])
}

export function roleInfo(palette, subject, name) {
  return palette.subjects[subject]?.[name] ?? palette.common[name] ?? null
}

// Every "role" string found anywhere in the data, with its JSON pointer.
export function* walkRoles(value, path = "") {
  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i++) yield* walkRoles(value[i], `${path}/${i}`)
  } else if (value && typeof value === "object") {
    for (const [k, v] of Object.entries(value)) {
      if (k === "role" && typeof v === "string") yield { path: `${path}/${k}`, role: v }
      else yield* walkRoles(v, `${path}/${k}`)
    }
  }
}

export function words(text) {
  return String(text ?? "").trim().split(/\s+/).filter(Boolean).length
}

// A dot-free join of Italian items: "a, b e c".
export function listIt(items) {
  if (items.length <= 1) return items.join("")
  return `${items.slice(0, -1).join(", ")} e ${items[items.length - 1]}`
}

// Places labels in stacked rows so that none overlaps another. Each spec is { text, cx, cls, role, maxW,
// connectFrom }: the label is centred on cx (shifted to stay inside the width), in the first row where
// it fits next to the labels already there; a label in a row after the first gets a thin connector line
// from `connectFrom` (a y) to its top. dir 1 stacks downward from y0, -1 upward. Returns the height used.
export function stackLabels(ctx, specs, y0, dir = 1) {
  const rows = []
  let used = 0
  const gapX = 8
  for (const spec of specs) {
    const probe = ctx.measure(spec.text, ctx.fontPx, spec.maxW)
    const w = Math.min(Math.ceil(probe.w), ctx.width - 8)
    const h = Math.ceil(probe.h)
    const x = Math.max(4, Math.min(Math.round(spec.cx - w / 2), ctx.width - w - 4))
    let r = 0
    for (; r < rows.length; r++) {
      if (rows[r].every((b) => x >= b.x + b.w + gapX || x + w + gapX <= b.x)) break
    }
    if (r === rows.length) rows.push([])
    rows[r].push({ x, w })
    const rowH = ctx.lineH * (spec.lines ?? 1) + 4
    const y = dir > 0 ? y0 + r * rowH : y0 - r * rowH - h
    const item = label(ctx, spec.text, x, y, { anchor: "start", maxW: spec.maxW ? w : undefined, cls: spec.cls ?? "", role: spec.role, key: spec.key })
    item.w = Math.max(item.w, w)
    item.anchor = "middle"
    if (r > 0 && spec.connectFrom !== undefined) {
      const top = dir > 0 ? item.y : item.y + item.h
      shape(ctx, "line", { x1: spec.cx, y1: spec.connectFrom, x2: spec.cx, y2: top, cls: "dg-connector" })
    }
    used = Math.max(used, (r + 1) * rowH)
  }
  return used
}

// Tries the 8 places around a point, nearest first; returns the first label that does not overlap one
// already placed and stays inside the box [bx0, bx1] x [by0, by1]; null when none does.
export function labelNear(ctx, text, px, py, gap, box, opts = {}) {
  const m = ctx.measure(text, ctx.fontPx, opts.maxW)
  const w = Math.ceil(m.w)
  const h = Math.ceil(m.h)
  const spots = [
    [px + gap, py - h - gap / 2], [px + gap, py + gap / 2], [px - w - gap, py - h - gap / 2], [px - w - gap, py + gap / 2],
    [px - w / 2, py - h - gap], [px - w / 2, py + gap], [px + gap, py - h / 2], [px - w - gap, py - h / 2]
  ]
  for (const [x0, y0] of spots) {
    const x = Math.round(x0)
    const y = Math.round(y0)
    if (x < box.x0 || x + w > box.x1 || y < box.y0 || y + h > box.y1) continue
    const probe = { x, y, w, h }
    if (ctx.labels.some((l) => overlaps(l, probe))) continue
    return label(ctx, text, x, y, { anchor: "start", cls: opts.cls ?? "", maxW: opts.maxW, role: opts.role })
  }
  return null
}
