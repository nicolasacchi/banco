// The pure part of the select check's keyboard (WAVE2 2.11): which target is next when an arrow is pressed. A box is { x, y, w, h } in the
// figure's coordinates; the list is in reading order (t1..tN). The arrows go to the geometrically nearest target in that direction; if there
// is none in that direction the focus stays where it is.

const centre = (b) => ({ x: b.x + b.w / 2, y: b.y + b.h / 2 })

// dir: "left" | "right" | "up" | "down". Returns the index to focus (from, when nothing lies that way).
export function nearest(boxes, from, dir) {
  const here = centre(boxes[from])
  let best = from
  let bestScore = Infinity
  boxes.forEach((box, i) => {
    if (i === from) return
    const c = centre(box)
    const dx = c.x - here.x
    const dy = c.y - here.y
    const along = dir === "right" ? dx : dir === "left" ? -dx : dir === "down" ? dy : -dy
    const across = dir === "left" || dir === "right" ? Math.abs(dy) : Math.abs(dx)
    if (along <= 0.5) return
    // a target straight ahead beats a nearer one far off to the side
    const score = along + across * 2
    if (score < bestScore - 1e-9 || (Math.abs(score - bestScore) < 1e-9 && i < best)) {
      best = i
      bestScore = score
    }
  })
  return best
}

// Reading-order neighbours for Home, End and Page keys.
export const first = () => 0
export const last = (boxes) => boxes.length - 1

// The sentence read for a screen reader: "zona 3 di 12" plus the neutral description of the type, never a name.
export function targetLabel(template, n, total, neutral) {
  const base = template.replace("%{n}", n).replace("%{total}", total)
  return neutral ? `${base}, ${neutral}` : base
}
