// The graph router (WAVE2 2.1; contract frozen in W2-0, built by T4b): one layout engine for node-and-arrow figures, shared by flow,
// chain and network. Fixed positions per layout (never force-directed: a figure is the same for every student and in print), stable node
// positions across states, edge changes as a 300 ms FLIP (a swap under reduced motion, A5), and below 600 px the nodes are stacked and the
// edges become a numbered list of moves under the figure.
import { notBuilt } from "lesson/lib/not_built"

// The layouts that have fixed positions: tree, line (a journey), ring (a cycle), pair, row, triangle, hub, fan, grid.
export const LAYOUTS = ["tree", "line", "ring", "pair", "row", "triangle", "hub", "fan", "grid"]

// place(layout, nodes, box, options) -> Map id -> { x, y, w, h }
//   nodes: [{ id, w, h }] sizes measured by the caller; box: { width, height?, narrow }; options: { centre?, into? }
export const place = notBuilt("graph/router.place", "T4b", "w2-1")

// route(boxes, edges, options) -> [{ id, from, to, points: [[x, y], ...], arrow: { x, y, angle }, label: { x, y } | null }]
//   boxes: the Map of place(); edges: [{ id, from, to, back?, label? }]; options: { orthogonal: true, gap }
export const route = notBuilt("graph/router.route", "T4b", "w2-1")

// flip(previous, next, ms) -> { keep: [id], enter: [id], leave: [id], ms } : what moves between two states; ms 300, 0 under reduced motion
export const flip = notBuilt("graph/router.flip", "T4b", "w2-1")

// moveList(nodes, edges) -> [{ n, text_it }] : the phone's numbered list of moves ("1. Anna consegna la bicicletta a Paolo")
export const moveList = notBuilt("graph/router.moveList", "T4b", "w2-1")

// The frozen signatures, one string per function (checked by lesson/test/contract.test.mjs against the exports).
export const SIGNATURES = {
  place: "place(layout, nodes, box, options)",
  route: "route(boxes, edges, options)",
  flip: "flip(previous, next, ms)",
  moveList: "moveList(nodes, edges)",
}
