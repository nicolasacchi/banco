// The point where y = a x + b meets y = c x + d (null when parallel).
export function meet(a, b, c, d) {
  if (a === c) return null
  const x = (d - b) / (a - c)
  return { x, y: a * x + b }
}
