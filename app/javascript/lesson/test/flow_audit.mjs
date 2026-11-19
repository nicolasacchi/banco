// The geometry of a flow Scene, judged from outside (D-383): the problems found, as a list of strings (empty when the drawing is sound).
//   - no two nodes overlap;
//   - every node text lies inside its node (a rhombus: all four corners of the text box inside the diamond);
//   - no edge label or loop label touches a node;
//   - a loop's arrow crosses no node, no label and no other loop.
// A node is a shape whose class has dg-node: a rect, or a polygon (a decision's rhombus). A loop is a path "M x,y H x V y H x".

const box = (s) => {
  if (s.kind === "rect") return { kind: "rect", x: s.x, y: s.y, w: s.w, h: s.h }
  const xs = s.points.map((p) => p[0])
  const ys = s.points.map((p) => p[1])
  return { kind: "rhombus", x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) }
}

// How deep a point lies in a node: 0 at the border, 1 at the centre, negative outside (a rhombus is |dx| / a + |dy| / b = 1).
const depth = (n, px, py, slack = 0) => {
  if (n.kind === "rect") return Math.min(px - n.x, n.x + n.w - px, py - n.y, n.y + n.h - py) + slack
  return 1 - (Math.abs(px - (n.x + n.w / 2)) / (n.w / 2) + Math.abs(py - (n.y + n.h / 2)) / (n.h / 2)) + slack / n.w
}

const overlap = (a, b) => a.x < b.x + b.w - 0.5 && b.x < a.x + a.w - 0.5 && a.y < b.y + b.h - 0.5 && b.y < a.y + a.h - 0.5

const corners = (l) => [[l.x, l.y], [l.x + l.w, l.y], [l.x, l.y + l.h], [l.x + l.w, l.y + l.h]]

// the three segments of a loop path
function segments(d) {
  const m = d.match(/^M(-?[\d.]+),(-?[\d.]+) H(-?[\d.]+) V(-?[\d.]+) H(-?[\d.]+)$/)
  if (!m) return null
  const [x0, y0, X, Y, x1] = m.slice(1).map(Number)
  return [{ x1: x0, y1: y0, x2: X, y2: y0 }, { x1: X, y1: y0, x2: X, y2: Y }, { x1: X, y1: Y, x2: x1, y2: Y }]
}

const along = (s, step = 0.02) => {
  const pts = []
  for (let t = 0; t <= 1.0001; t += step) pts.push([s.x1 + (s.x2 - s.x1) * t, s.y1 + (s.y2 - s.y1) * t])
  return pts
}

export function audit(scene) {
  if (scene.error) return [`layout error ${scene.error.code}: ${scene.error.message}`]
  const bad = []
  const nodes = scene.shapes.filter((s) => /\bdg-node\b/.test(s.cls ?? "")).map(box)
  for (let i = 0; i < nodes.length; i++) for (let j = i + 1; j < nodes.length; j++) if (overlap(nodes[i], nodes[j])) bad.push(`nodes ${i} and ${j} overlap`)
  for (const l of scene.labels) {
    if (/dg-nodetext/.test(l.cls)) {
      if (!nodes.some((n) => corners(l).every(([px, py]) => depth(n, px, py) >= 0))) bad.push(`the text "${l.text_it}" is not inside one node`)
    } else {
      for (const n of nodes) if (overlap(n, l) && (n.kind === "rect" || corners(l).some(([px, py]) => depth(n, px, py) > 0))) bad.push(`the label "${l.text_it}" touches a node`)
    }
  }
  const loops = []
  for (const s of scene.shapes.filter((q) => q.kind === "path" && /dg-loop/.test(q.cls))) {
    const segs = segments(s.d)
    if (!segs) {
      bad.push(`a path that is not a loop: ${s.d}`)
      continue
    }
    for (const sg of segs) {
      for (const n of nodes) if (along(sg).some(([px, py]) => depth(n, px, py) > 0.02 && (n.kind === "rect" ? depth(n, px, py, -2) > 0 : true))) bad.push("a loop crosses a node")
      for (const l of scene.labels) {
        if (along(sg).some(([px, py]) => px > l.x && px < l.x + l.w && py > l.y && py < l.y + l.h)) bad.push(`a loop crosses the label "${l.text_it}"`)
      }
    }
    loops.push(segs)
  }
  for (let a = 0; a < loops.length; a++) {
    for (let b = a + 1; b < loops.length; b++) {
      for (const p of loops[a]) {
        for (const q of loops[b]) {
          if ((p.y1 === p.y2) === (q.y1 === q.y2)) continue
          const h = p.y1 === p.y2 ? p : q
          const v = h === p ? q : p
          if (v.x1 > Math.min(h.x1, h.x2) && v.x1 < Math.max(h.x1, h.x2) && h.y1 > Math.min(v.y1, v.y2) && h.y1 < Math.max(v.y1, v.y2)) bad.push("two loops cross")
        }
      }
    }
  }
  return bad
}

// Which layout drew a tree flow: the indented one draws its steps' links as "dg-arrow" lines and its branches as "dg-branch" paths, the centred tree neither.
export const indented = (scene) => scene.shapes.some((s) => /\bdg-(arrow|branch)\b/.test(s.cls ?? ""))
