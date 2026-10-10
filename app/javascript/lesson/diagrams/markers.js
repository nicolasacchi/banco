// The marker shapes of the palette (A6) as small standalone SVGs (legend, mistakes), and the same drawn
// inside a diagram's SVG by draw.js.
import { svg } from "lesson/dom"

export function markerSvg(shape, cls = "") {
  const s = svg("svg", { class: `ic marker ${cls}`, viewBox: "0 0 24 24", "aria-hidden": "true", focusable: "false" })
  const add = (tag, attrs) => s.appendChild(svg(tag, { ...attrs, class: cls }))
  switch (shape) {
    case "box": add("rect", { x: 3, y: 3, width: 18, height: 18, rx: 4 }); break
    case "weight": add("path", { d: "M5 22 L8 9 H16 L19 22 Z" }); add("circle", { cx: 12, cy: 6, r: 3.5 }); break
    case "circle": add("circle", { cx: 12, cy: 12, r: 9 }); break
    case "square": add("rect", { x: 4, y: 4, width: 16, height: 16 }); break
    case "triangle": add("polygon", { points: "12,3 22,21 2,21" }); break
    case "diamond": add("polygon", { points: "12,2 22,12 12,22 2,12" }); break
    case "ring": s.appendChild(svg("circle", { cx: 12, cy: 12, r: 8, fill: "none", "stroke-width": 4, class: cls })); break
    case "star": add("polygon", { points: "12,2 15,9 22,9.5 16.5,14 18.5,21 12,17 5.5,21 7.5,14 2,9.5 9,9" }); break
    default: add("circle", { cx: 12, cy: 12, r: 8 })
  }
  return s
}
