// cell (WAVE2 2.8, biology.md 2.1; T7, D-312): one or two cells (a bacterium, an animal cell, a plant cell) drawn by our code with fixed shapes, places and
// colours, the same in every lesson, so the cell becomes a map the student learns once. The parts each kind may have, their Italian names, their jobs and
// their colours come from the vetted table bio/cell_parts (lesson/data/bio-cell_parts): a part the kind does not have is refused (a bacterium with a
// nucleus, an animal cell with a wall), and every cell has the four shared parts (membrane, cytoplasm, DNA, ribosomes).
//
// Labels: `all` names every part with a leader line (two side columns when they fit, else a number on each part and one key under the figure, the same
// number for the same part in both cells), `tap` names a part only when it is tapped, `none` names nothing. A tap on a part (`all` and `tap`: on any of
// its shapes or the invisible pads along its thin lines, which forward the tap to the part's button) says its name and its job, or the author's note.
// Highlight lights parts (a halo and a thicker outline, the others dimmed: never colour alone), paths are arrows between two parts of one cell, `fill`
// sets the water of the vacuole (low: the membrane pulls away from the wall). Two cells with different parts offer "Solo le differenze". Select mode
// (L3): the cells as a line drawing in one neutral style, one zone per part as large as its button, `c1.nucleoid` and so on, no names; the wall's band
// stands apart from the membrane and their two targets keep each to its own band; no ribosome's dot lies under another part's target.
// The Ruby twin is Lessons::Diagrams::Cell (the same semantic checks in the same order, the same targets and printed strings); both run
// test/fixtures/diagrams/types/cell.json.
import schema from "lesson/diagram_schemas/cell"
import TABLE from "lesson/data/bio-cell_parts"
import { crosses, effectiveState, finish, label, labelNear, listIt, shape, stateCount, words } from "lesson/diagrams/common"
import { run } from "lesson/diagrams/run"

export const type = "cell"
export { schema }

export const PARTS = TABLE.parts
export const KINDS = TABLE.kinds
// The canonical order of the parts (the table's): the order of the key, of the targets and of the descriptions.
export const ORDER = Object.keys(PARTS)
const SHARED = ["membrane", "cytoplasm", "ribosomes"]
const LABEL_WORDS = 6

// Texts the figure prints (Ruby's printed() has the same ones).
export const TEXT = {
  hint_all: "Tocca una parte per leggere che cosa fa.",
  hint_tap: "Tocca una parte per leggere il suo nome e che cosa fa.",
  compare: "Confronta le due cellule",
  diff: "Solo le differenze",
  hit_hint: "Tocca per leggere che cosa fa"
}
const KIND_IT = { bacterium: "un batterio", animal: "una cellula animale", plant: "una cellula vegetale", red_blood: "un globulo rosso" }
const KIND_IN = { bacterium: "nel batterio", animal: "nella cellula animale", plant: "nella cellula vegetale" }
const KIND_EN = { bacterium: "bacterium", animal: "animal cell", plant: "plant cell", red_blood: "red blood cell" }
// What a part looks like, for a figure that names nothing (labels: none): the description says the shapes, never the names.
const SHAPE_IT = {
  wall: "un bordo spesso", membrane: "un bordo sottile", cytoplasm: "l'interno", nucleoid: "un groviglio di filo", nucleus: "un cerchio grande con dei fili dentro",
  dna: "dei fili", ribosomes: "tanti puntini", mitochondria: "dei fagioli con delle pieghe dentro", chloroplasts: "dei fagioli con delle pile di dischi",
  vacuole: "una grande sacca", er: "delle pieghe intorno al cerchio grande", golgi: "una pila di sacchetti curvi", vesicles: "delle piccole bolle",
  flagellum: "una coda ondulata"
}
const FILL_IT = { low: "quasi vuoto: la membrana si stacca dalla parete", mid: "pieno a metà", high: "pieno d'acqua" }

const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1)
const nameOf = (part) => PARTS[part]?.name_it ?? part
const isEukaryote = (kind) => KINDS[kind]?.includes("nucleus")
// The part that holds the DNA in a cell: the nucleoid of a bacterium, the nucleus of a eukaryotic cell.
const dnaHome = (cell) => (cell.parts.includes("nucleoid") ? "nucleoid" : "nucleus")
// Does the cell have the part (dna: always, in its nucleoid or its nucleus)?
const has = (cell, part) => (part === "dna" ? cell.parts.includes("nucleoid") || cell.parts.includes("nucleus") : cell.parts.includes(part))
const inAny = (cells, part) => cells.some((c) => has(c, part))

// ---- semantics (the same checks, in the same order, as Lessons::Diagrams::Cell) ------------------------------------------------------------

const SPECIAL = {
  "bacterium:nucleus": "a bacterium has no nucleus: its DNA lies in the cytoplasm (nucleoid)",
  "animal:wall": "an animal cell has no wall: only the plant cell and the bacterium have one",
  "animal:chloroplasts": "an animal cell has no chloroplasts: they are only in the plant cell",
  "animal:vacuole": "an animal cell has no large central vacuole (its small sacs are the vesicles)",
  "animal:nucleoid": "a eukaryotic cell keeps its DNA in the nucleus: list nucleus, not nucleoid",
  "plant:nucleoid": "a eukaryotic cell keeps its DNA in the nucleus: list nucleus, not nucleoid",
  "animal:flagellum": "the figure draws a typical animal cell: it has no flagellum",
  "plant:flagellum": "the figure draws a typical plant cell: it has no flagellum"
}

export function partProblem(kind, part) {
  if (part === "dna") return "dna is not a part to list: a bacterium lists nucleoid, an animal or plant cell nucleus (highlight, paths and notes may name dna)"
  if (!PARTS[part]) return `${part} is not a part the figure draws (${ORDER.filter((p) => p !== "dna").join(", ")})`
  if (KINDS[kind].includes(part)) return null
  if (SPECIAL[`${kind}:${part}`]) return SPECIAL[`${kind}:${part}`]
  if (kind === "bacterium") return `a bacterium has no organelles closed by a membrane: it has no ${part}`
  return `a ${KIND_EN[kind]} has no ${part} (it may show ${KINDS[kind].join(", ")})`
}

function staticProblem(data) {
  const cells = data.cells
  for (let i = 0; i < cells.length; i++) {
    const cell = cells[i]
    const at = `/cells/${i}`
    if (cell.kind === "red_blood") return { path: `${at}/kind`, message: "the red blood cell is not drawn yet: it has no nucleus and no ribosomes, say it in a more block" }
    if (cell.omit_shared !== undefined) return { path: `${at}/omit_shared`, message: "omit_shared is for the red blood cell, which is not drawn yet" }
    for (let j = 0; j < cell.parts.length; j++) {
      const bad = partProblem(cell.kind, cell.parts[j])
      if (bad) return { path: `${at}/parts/${j}`, message: bad }
      if (cell.parts.indexOf(cell.parts[j]) !== j) return { path: `${at}/parts/${j}`, message: `${cell.parts[j]} is listed twice` }
    }
    const missing = [...SHARED.filter((p) => !cell.parts.includes(p)), ...(has(cell, "dna") ? [] : [cell.kind === "bacterium" ? "nucleoid" : "nucleus"])]
    if (missing.length) return { path: `${at}/parts`, message: `every cell has a membrane, cytoplasm, DNA and ribosomes: add ${missing.join(", ")}` }
    if (cell.label_it !== undefined && words(cell.label_it) > LABEL_WORDS) return { path: `${at}/label_it`, message: `a label has ${words(cell.label_it)} words (at most ${LABEL_WORDS})` }
  }
  if (data.true_scale === true) return { path: "/true_scale", message: "true_scale waits for the vetted sizes of bio/sizes: draw the cells side by side without it" }
  const notes = data.notes ?? []
  if (notes.length && (data.labels ?? "all") === "none") return { path: "/notes", message: "a note is read on a tap: with labels none nothing can be tapped" }
  for (let k = 0; k < notes.length; k++) {
    const part = notes[k].part
    if (!inAny(cells, part)) return { path: `/notes/${k}/part`, message: `${part} is not a part of the figure's cells` }
    if (notes.findIndex((n) => n.part === part) !== k) return { path: `/notes/${k}/part`, message: `${part} has two notes` }
  }
  return null
}

function stateProblem(eff, path) {
  const cells = eff.cells
  const marks = eff.highlight ?? []
  for (let j = 0; j < marks.length; j++) {
    if (!inAny(cells, marks[j])) return { path: `${path}/highlight/${j}`, message: `${marks[j]} is not a part of the figure's cells` }
  }
  const paths = eff.paths ?? []
  for (let j = 0; j < paths.length; j++) {
    const p = paths[j]
    if (!inAny(cells, p.from)) return { path: `${path}/paths/${j}/from`, message: `${p.from} is not a part of the figure's cells` }
    if (!inAny(cells, p.to)) return { path: `${path}/paths/${j}/to`, message: `${p.to} is not a part of the figure's cells` }
    if (p.from === p.to) return { path: `${path}/paths/${j}/to`, message: "a path joins two different parts" }
    if (!cells.some((c) => has(c, p.from) && has(c, p.to))) return { path: `${path}/paths/${j}`, message: `no cell has both ${p.from} and ${p.to}` }
    if (p.label_it !== undefined && words(p.label_it) > LABEL_WORDS) return { path: `${path}/paths/${j}/label_it`, message: `a label has ${words(p.label_it)} words (at most ${LABEL_WORDS})` }
  }
  for (const key of Object.keys(eff.fill ?? {})) {
    if (key !== "vacuole") return { path: `${path}/fill/${key}`, message: "only the vacuole has a fill level (low, mid, high)" }
    if (!inAny(cells, "vacuole")) return { path: `${path}/fill/${key}`, message: "no cell of the figure has a vacuole" }
    if (!["low", "mid", "high"].includes(eff.fill[key])) return { path: `${path}/fill/${key}`, message: "a fill level is low, mid or high" }
  }
  return null
}

export function semantic(data) {
  const top = staticProblem(data)
  if (top) return top
  const count = stateCount(data)
  for (let i = 0; i < count; i++) {
    const found = stateProblem(effectiveState(data, i), data.states?.length ? `/states/${i}` : "")
    if (found) return found
  }
  return null
}

// ---- geometry: the fixed drawing of each kind -------------------------------------------------------------------------------------------
// A kind is drawn in a box of width w (its height is w times ASPECT) from fixed fractions of w, so the picture is the same at every size. Each part has
// shapes, a zone (the point where its tap target, its number and the end of its leader line sit: the zones of one cell are far apart by construction)
// and a side (where its label goes in the two-column layout). A port (an ellipse) is where an arrow starts or ends.

const ASPECT = { bacterium: 0.5, animal: 0.8, plant: 0.76 }
const r1 = (v) => Math.round(v * 10) / 10

function pathOf(points, close = true) {
  return points.map(([x, y], i) => `${i ? "L" : "M"}${r1(x)} ${r1(y)}`).join(" ") + (close ? " Z" : "")
}

// A closed curve around (cx, cy): an ellipse with a little wobble (an animal cell, a vacuole), sampled in 96 points.
function blob(cx, cy, rx, ry, wob = []) {
  const pts = []
  for (let k = 0; k < 96; k++) {
    const t = (k / 96) * Math.PI * 2
    const f = 1 + wob.reduce((s, [a, n, ph]) => s + a * Math.sin(n * t + ph), 0)
    pts.push([cx + rx * f * Math.cos(t), cy + ry * f * Math.sin(t)])
  }
  return pathOf(pts)
}

function capsule(x, y, w, h) {
  const r = h / 2
  return `M${r1(x + r)} ${r1(y)} H${r1(x + w - r)} A${r1(r)} ${r1(r)} 0 0 1 ${r1(x + w - r)} ${r1(y + h)} H${r1(x + r)} A${r1(r)} ${r1(r)} 0 0 1 ${r1(x + r)} ${r1(y)} Z`
}

function roundRect(x, y, w, h, r) {
  return `M${r1(x + r)} ${r1(y)} H${r1(x + w - r)} Q${r1(x + w)} ${r1(y)} ${r1(x + w)} ${r1(y + r)} V${r1(y + h - r)} Q${r1(x + w)} ${r1(y + h)} ${r1(x + w - r)} ${r1(y + h)} H${r1(x + r)} Q${r1(x)} ${r1(y + h)} ${r1(x)} ${r1(y + h - r)} V${r1(y + r)} Q${r1(x)} ${r1(y)} ${r1(x + r)} ${r1(y)} Z`
}

// An ellipse turned by `rot` degrees, as a path.
function ellipseRot(cx, cy, rx, ry, rot) {
  const a = (rot * Math.PI) / 180
  const pts = []
  for (let k = 0; k < 48; k++) {
    const t = (k / 48) * Math.PI * 2
    const x = rx * Math.cos(t)
    const y = ry * Math.sin(t)
    pts.push([cx + x * Math.cos(a) - y * Math.sin(a), cy + x * Math.sin(a) + y * Math.cos(a)])
  }
  return pathOf(pts)
}

// Points along the long axis of a turned ellipse: the folds of a mitochondrion (a zigzag) and the stacks of a chloroplast.
function along(cx, cy, rx, ry, rot, fn) {
  const a = (rot * Math.PI) / 180
  const map = ([x, y]) => [cx + x * Math.cos(a) - y * Math.sin(a), cy + x * Math.sin(a) + y * Math.cos(a)]
  return fn(rx, ry).map((line) => line.map(map))
}

const cristae = (rx, ry) => [Array.from({ length: 9 }, (_, k) => [-rx * 0.72 + (k * rx * 1.44) / 8, (k % 2 ? 1 : -1) * ry * 0.55])]
const grana = (rx, ry) => [-0.45, 0, 0.45].flatMap((f) => [-0.4, 0, 0.4].map((g) => [[rx * f - rx * 0.13, ry * g], [rx * f + rx * 0.13, ry * g]]))

// An annular sector (a flattened sac of the reticulum or the Golgi), angles in degrees.
function sector(cx, cy, ra, rb, a0, a1) {
  const pts = []
  const steps = 18
  for (let k = 0; k <= steps; k++) {
    const t = ((a0 + ((a1 - a0) * k) / steps) * Math.PI) / 180
    pts.push([cx + rb * Math.cos(t), cy + rb * Math.sin(t)])
  }
  for (let k = steps; k >= 0; k--) {
    const t = ((a0 + ((a1 - a0) * k) / steps) * Math.PI) / 180
    pts.push([cx + ra * Math.cos(t), cy + ra * Math.sin(t)])
  }
  return pathOf(pts)
}

// A tangled loop of DNA: a closed curve that winds around an ellipse (the nucleoid), or a short thread (chromatin in a nucleus).
function tangle(cx, cy, rx, ry, turns = 7) {
  const pts = []
  for (let k = 0; k <= 160; k++) {
    const t = (k / 160) * Math.PI * 2
    const f = 0.62 + 0.3 * Math.sin(turns * t) + 0.08 * Math.cos(3 * t + 1)
    pts.push([cx + rx * f * Math.cos(t), cy + ry * (0.7 * f + 0.3 * Math.cos(turns * t + 0.6)) * Math.sin(t + 0.4 * Math.sin(turns * t))])
  }
  return pathOf(pts, false)
}

function thread(cx, cy, r, seed) {
  const pts = []
  for (let k = 0; k <= 40; k++) {
    const t = k / 40
    pts.push([cx + r * (t - 0.5) * 1.6, cy + r * 0.32 * Math.sin(t * Math.PI * (3 + seed)) + r * 0.18 * Math.cos(t * 7 + seed)])
  }
  return pathOf(pts, false)
}

// The fixed places of each kind, as fractions of the box width (x and y alike). `zones` are where a part's tap target, number and leader end sit; any two
// zones of a kind are at least 0.115 of the width apart on one axis, so at the narrowest drawing (240 px) they never touch. `side` is the column of its
// name in the two-column layout. `dots` are the ribosomes (a small cluster under the zone and a few more).
const PLACES = {
  bacterium: {
    dots: [[0.62, 0.13], [0.66, 0.17], [0.7, 0.12], [0.73, 0.18], [0.69, 0.21], [0.18, 0.18], [0.24, 0.13], [0.3, 0.36], [0.36, 0.38], [0.58, 0.35], [0.65, 0.33], [0.53, 0.14], [0.13, 0.25]],
    zones: { wall: [0.22, 0.074], membrane: [0.62, 0.412], cytoplasm: [0.17, 0.32], nucleoid: [0.44, 0.25], ribosomes: [0.68, 0.16], flagellum: [0.925, 0.25] },
    side: { wall: "left", membrane: "right", cytoplasm: "left", nucleoid: "right", ribosomes: "right", flagellum: "right" }
  },
  animal: {
    nucleus: [0.43, 0.38, 0.125],
    mito: [[0.24, 0.2, -25], [0.66, 0.15, 12], [0.48, 0.64, 4]],
    er: [0.43, 0.38, 0.155, 0.235, 120, 205],
    golgi: [0.95, 0.42, [0.15, 0.18, 0.21, 0.24], 152, 208],
    ves: [[0.79, 0.6], [0.665, 0.5], [0.69, 0.29]],
    dots: [[0.62, 0.6], [0.67, 0.64], [0.63, 0.66], [0.69, 0.59], [0.66, 0.57], [0.14, 0.4], [0.12, 0.5], [0.84, 0.25], [0.8, 0.2], [0.36, 0.11], [0.22, 0.32], [0.86, 0.5], [0.3, 0.6]],
    zones: { membrane: [0.13, 0.16], cytoplasm: [0.33, 0.66], nucleus: [0.424, 0.302], dna: [0.424, 0.43], ribosomes: [0.65, 0.62], mitochondria: [0.66, 0.15], er: [0.247, 0.45], golgi: [0.74, 0.42], vesicles: [0.69, 0.29] },
    side: { membrane: "left", cytoplasm: "left", nucleus: "left", dna: "left", ribosomes: "right", er: "left", mitochondria: "right", golgi: "right", vesicles: "right" }
  },
  plant: {
    nucleus: [0.18, 0.22, 0.11],
    mito: [[0.11, 0.5, 80], [0.88, 0.63, 90]],
    er: [0.18, 0.22, 0.135, 0.185, 20, 110],
    golgi: [0.2, 0.85, [0.19, 0.215, 0.24], 247, 293],
    ves: [[0.33, 0.52], [0.36, 0.58]],
    chloro: [[0.42, 0.105, 0], [0.66, 0.105, 0], [0.905, 0.3, 90], [0.905, 0.47, 90], [0.5, 0.66, 0], [0.73, 0.66, 0]],
    dots: [[0.8, 0.09], [0.84, 0.125], [0.865, 0.085], [0.81, 0.14], [0.29, 0.085], [0.33, 0.135], [0.07, 0.41], [0.42, 0.62], [0.6, 0.62]],
    zones: { wall: [0.036, 0.38], membrane: [0.61, 0.708], cytoplasm: [0.54, 0.11], nucleus: [0.098, 0.248], dna: [0.228, 0.187], ribosomes: [0.83, 0.11], mitochondria: [0.11, 0.5], chloroplasts: [0.905, 0.3], vacuole: [0.57, 0.38], er: [0.235, 0.37], golgi: [0.2, 0.635], vesicles: [0.36, 0.58] },
    side: { wall: "left", membrane: "right", cytoplasm: "right", nucleus: "left", dna: "left", er: "left", mitochondria: "left", vesicles: "left", golgi: "left", vacuole: "right", chloroplasts: "right", ribosomes: "right" }
  }
}

export const ZONES = Object.fromEntries(Object.entries(PLACES).map(([k, v]) => [k, v.zones]))

// A select figure (L3) draws the wall's band a gap away from the membrane, so the line drawing shows two lines, and their targets keep each to its own
// band: the wall's on the top edge, above the gap (over the band and out of the cell: the figure keeps room above it), the membrane's on the bottom
// edge, above the gap (over the line, inside the cell). `along` is where on its edge each target sits, as a fraction of the width: on the straight part
// of the edge, away from the other targets (the bacterium's membrane target right of the nucleoid's even when the targets are 46 px wide).
export const selectGap = (w) => Math.min(6, Math.max(5, Math.floor(w * 0.02)))
const SELECT_EDGES = { bacterium: { wall: 0.3, membrane: 0.58 }, plant: { wall: 0.54, membrane: 0.61 } }
// Where a select figure puts a target other than its zone: a plant cell's cytoplasm is a thin layer between the vacuole and the membrane, so its target
// goes to the widest room of it, left of the vacuole, never against the membrane (where it would look like the membrane's).
const SELECT_ZONES = { plant: { cytoplasm: [0.235, 0.505] } }
// The tap pads of `all` and `tap` (A3): an invisible strip along a thin part, so a tap near the line counts (the membrane, the wall, the tail), and a
// ring around each ribosome; a tap on any shape of a part reads that part, not only a tap on its zone.
const padWidth = (w) => Math.max(8, Math.round(w * 0.03))

// opts.select: the select figure (the band apart from the membrane, `edges` for the two targets, no pads); else `pads` for the taps.
function geometry(kind, x0, y0, w, cell, eff, opts = {}) {
  const select = !!opts.select
  const parts = new Set(cell.parts)
  const place = PLACES[kind]
  const shapes = [] // [{ part, s, pad? }] in drawing order
  const ports = {}
  const edges = {} // select: { wall: { mid, along }, membrane: ... }: a target spans [mid - Z, mid] upwards, Z wide along its edge, centred on along
  const add = (part, s) => shapes.push({ part, s })
  const pad = (part, s) => select || shapes.push({ part, s, pad: true })
  const pw = padWidth(w)
  const h = Math.round(w * ASPECT[kind])
  // a select figure has no states and no fill: the cell is drawn full of water whatever the stored figure says
  const level = select ? "high" : eff.fill?.vacuole ?? "high"
  // the frame (the wall of a plant cell) at full size; the rest of a plant cell whose vacuole is low shrinks towards the middle: the membrane pulls away
  // from the wall (plasmolysis), and every part inside moves with it
  const k = kind === "plant" && level === "low" ? 0.84 : 1
  const centre = [0.5, ASPECT[kind] / 2]
  const P = (fx, fy) => [x0 + (centre[0] + (fx - centre[0]) * k) * w, y0 + (centre[1] + (fy - centre[1]) * k) * w]
  const s = (f) => f * w * k
  const zones = {}
  for (const [part, [fx, fy]] of Object.entries({ ...place.zones, ...(select ? SELECT_ZONES[kind] : {}) })) zones[part] = P(fx, fy)
  const dot = (cx, cy) => {
    const r = Math.max(2.5, w * 0.009)
    pad("ribosomes", { kind: "circle", cx, cy, r: Math.max(7, r * 2.5), cls: "dg-cp-pad" })
    add("ribosomes", { kind: "circle", cx, cy, r, cls: "dg-cp-dot" })
  }
  const dots = () => {
    for (const [fx, fy] of place.dots) dot(...P(fx, fy))
    ports.ribosomes = { cx: zones.ribosomes[0], cy: zones.ribosomes[1], rx: s(0.045), ry: s(0.045) }
  }
  if (kind === "bacterium") {
    const flag = parts.has("flagellum")
    const sx = flag ? 0 : 0.08 // the body moves to the middle when there is no tail
    for (const part of Object.keys(zones)) zones[part] = [zones[part][0] + sx * w, zones[part][1]]
    const Q = (fx, fy) => [x0 + (fx + sx) * w, y0 + fy * w]
    const [bx, by] = Q(0.02, 0.06)
    const bw = w * 0.8
    const bh = w * 0.38
    const t = Math.max(5, Math.round(w * 0.028))
    const ring = (d) => capsule(bx - d, by - d, bw + 2 * d, bh + 2 * d) // the outline of the body grown by d (shrunk when d < 0)
    const m = parts.has("wall") ? t : 0
    if (parts.has("wall")) {
      // the band; a select figure moves it out by the gap (the room around the body allows it) so that it stands apart from the membrane
      const gp = select ? selectGap(w) : 0
      add("wall", { kind: "path", d: `${ring(gp)} ${ring(gp - t)}`, cls: "dg-cp-band", fillRule: "evenodd" })
      pad("wall", { kind: "path", d: `${ring(Math.min(pw, Math.floor(w * 0.02)))} ${ring(0)}`, cls: "dg-cp-pad", fillRule: "evenodd" }) // inside the cell's box
      if (select) {
        edges.wall = { mid: by + t - gp / 2, along: x0 + (SELECT_EDGES.bacterium.wall + sx) * w }
        edges.membrane = { mid: by + bh - t + gp / 2, along: x0 + (SELECT_EDGES.bacterium.membrane + sx) * w }
      }
    }
    add("cytoplasm", { kind: "path", d: ring(-m), cls: "" })
    add("membrane", { kind: "path", d: ring(-m), cls: "dg-cp-ink dg-cp-edge" })
    // the strip of the membrane: inside it when a wall is outside it, on both sides when the membrane is the edge
    pad("membrane", { kind: "path", d: `${ring(m ? -m : pw / 2)} ${ring(-m - (m ? pw : pw / 2))}`, cls: "dg-cp-pad", fillRule: "evenodd" })
    if (!parts.has("wall")) zones.membrane = [zones.membrane[0], zones.membrane[1] + t]
    if (flag) {
      const pts = []
      const [fx0, fy0] = [bx + bw - 2, by + bh / 2]
      const len = w * 0.16
      for (let j = 0; j <= 40; j++) pts.push([fx0 + (j / 40) * len, fy0 + Math.sin((j / 40) * Math.PI * 3) * w * 0.035])
      add("flagellum", { kind: "path", d: pathOf(pts, false), cls: "dg-cp-ink dg-cp-tail" })
      pad("flagellum", { kind: "path", d: pathOf(pts, false), cls: "dg-cp-pad dg-cp-pad-line" })
    }
    const [ncx, ncy] = zones.nucleoid
    add("nucleoid", { kind: "ellipse", cx: ncx, cy: ncy, rx: w * 0.13, ry: w * 0.085, cls: "dg-cp-zonefill" })
    add("nucleoid", { kind: "path", d: tangle(ncx, ncy, w * 0.12, w * 0.075, 7), cls: "dg-cp-ink dg-cp-thread" })
    ports.nucleoid = { cx: ncx, cy: ncy, rx: w * 0.13, ry: w * 0.085 }
    ports.dna = ports.nucleoid
    for (const [fx, fy] of place.dots) dot(...Q(fx, fy))
    ports.ribosomes = { cx: zones.ribosomes[0], cy: zones.ribosomes[1], rx: w * 0.045, ry: w * 0.045 }
    return { h, shapes, zones, ports, edges, side: place.side }
  }
  if (kind === "animal") {
    const [cx, cy] = P(0.5, 0.4)
    const WOB = [[0.025, 3, 0.4], [0.018, 5, 1.3], [0.01, 7, 2.1]]
    const outline = blob(cx, cy, s(0.46), s(0.36), WOB)
    add("cytoplasm", { kind: "path", d: outline, cls: "" })
    add("membrane", { kind: "path", d: outline, cls: "dg-cp-ink dg-cp-edge" })
    pad("membrane", { kind: "path", d: `${blob(cx, cy, s(0.46) + pw / 2, s(0.36) + pw / 2, WOB)} ${blob(cx, cy, s(0.46) - pw / 2, s(0.36) - pw / 2, WOB)}`, cls: "dg-cp-pad", fillRule: "evenodd" })
  } else {
    const t = Math.max(6, Math.round(w * 0.032))
    const [bx, by] = [x0 + w * 0.02, y0 + w * 0.02]
    const bw = w * 0.96
    const bh = h - w * 0.04
    const box = (d, r) => roundRect(bx - d, by - d, bw + 2 * d, bh + 2 * d, Math.max(1, r + d)) // the frame grown by d (shrunk when d < 0)
    if (parts.has("wall")) {
      // the band; a select figure moves its inner edge out by the gap and its outer edge by as much as the cell's box allows, so that it stands
      // apart from the membrane
      const gp = select ? selectGap(w) : 0
      const out = select ? Math.min(gp, Math.floor(w * 0.02)) : 0
      add("wall", { kind: "path", d: `${box(out, w * 0.05)} ${box(gp - t, w * 0.035 + t)}`, cls: "dg-cp-band", fillRule: "evenodd" })
      pad("wall", { kind: "path", d: `${box(Math.min(pw, Math.floor(w * 0.02)), w * 0.05)} ${box(0, w * 0.05)}`, cls: "dg-cp-pad", fillRule: "evenodd" }) // inside the cell's box
      if (select) {
        edges.wall = { mid: by + t - gp / 2, along: x0 + SELECT_EDGES.plant.wall * w }
        edges.membrane = { mid: by + bh - t + gp / 2, along: x0 + SELECT_EDGES.plant.membrane * w }
      }
    }
    const [ix, iy] = P(0.02 + t / w, 0.02 + t / w)
    const [iw, ih, ir] = [(bw - 2 * t) * k, (bh - 2 * t) * k, w * (k < 1 ? 0.09 : 0.035)]
    const inner = roundRect(ix, iy, iw, ih, ir)
    add("cytoplasm", { kind: "path", d: inner, cls: "" })
    add("membrane", { kind: "path", d: inner, cls: "dg-cp-ink dg-cp-edge" })
    pad("membrane", { kind: "path", d: `${inner} ${roundRect(ix + pw, iy + pw, iw - 2 * pw, ih - 2 * pw, Math.max(1, ir - pw))}`, cls: "dg-cp-pad", fillRule: "evenodd" })
    zones.wall = [x0 + w * place.zones.wall[0], y0 + w * place.zones.wall[1]] // the wall does not move
    zones.membrane = [zones.membrane[0], iy + (bh - 2 * t) * k]
    if (parts.has("vacuole")) {
      const size = { high: [0.27, 0.22], mid: [0.2, 0.16], low: [0.15, 0.12] }[level]
      const [vx, vy] = zones.vacuole
      add("vacuole", { kind: "path", d: blob(vx, vy, s(size[0]), s(size[1]), [[0.04, 3, 0.2], [0.02, 5, 1]]), cls: "" })
      ports.vacuole = { cx: vx, cy: vy, rx: s(size[0]), ry: s(size[1]) }
    }
    if (parts.has("chloroplasts")) {
      for (const [fx, fy, rot] of place.chloro) {
        const [cx, cy] = P(fx, fy)
        add("chloroplasts", { kind: "path", d: ellipseRot(cx, cy, s(0.062), s(0.03), rot), cls: "" })
        for (const line of along(cx, cy, s(0.062), s(0.03), rot, grana)) add("chloroplasts", { kind: "path", d: pathOf(line, false), cls: "dg-cp-ink" })
      }
    }
  }
  const [nfx, nfy, nfr] = place.nucleus
  const [nx, ny] = P(nfx, nfy)
  const nr = s(nfr)
  if (parts.has("er")) {
    const [ex, ey, ra, rb, a0, a1] = place.er
    const [cx, cy] = P(ex, ey)
    pad("er", { kind: "path", d: sector(cx, cy, s(ra) - 2, s(rb + 0.016) + 2, a0, a1), cls: "dg-cp-pad" }) // the folds and the room between them
    for (let j = 0; j < 3; j++) add("er", { kind: "path", d: sector(cx, cy, s(ra + ((rb - ra) * j) / 2), s(ra + ((rb - ra) * j) / 2 + 0.016), a0, a1), cls: "" })
  }
  if (parts.has("nucleus")) {
    add("nucleus", { kind: "circle", cx: nx, cy: ny, r: nr, cls: "" })
    add("nucleus", { kind: "circle", cx: nx, cy: ny, r: Math.max(1, nr - Math.max(3, w * 0.01)), cls: "dg-cp-ink dg-cp-thin" })
    for (const [dx, dy, seed] of [[-0.25, -0.18, 0], [0.18, 0.12, 1], [-0.12, 0.38, 2]]) add("dna", { kind: "path", d: thread(nx + dx * nr, ny + dy * nr, nr * 0.5, seed), cls: "dg-cp-ink dg-cp-thread" })
    add("nucleus", { kind: "circle", cx: nx + nr * 0.3, cy: ny - nr * 0.32, r: Math.max(3, nr * 0.18), cls: "dg-cp-nucleolus" })
    ports.nucleus = { cx: nx, cy: ny, rx: nr, ry: nr }
    ports.dna = { cx: nx, cy: ny + nr * 0.1, rx: nr * 0.55, ry: nr * 0.45 }
  }
  if (parts.has("mitochondria")) {
    for (const [fx, fy, rot] of place.mito) {
      const [cx, cy] = P(fx, fy)
      add("mitochondria", { kind: "path", d: ellipseRot(cx, cy, s(0.07), s(0.034), rot), cls: "" })
      for (const line of along(cx, cy, s(0.07), s(0.034), rot, cristae)) add("mitochondria", { kind: "path", d: pathOf(line, false), cls: "dg-cp-ink" })
    }
  }
  if (parts.has("golgi")) {
    const [gx, gy, radii, a0, a1] = place.golgi
    const [cx, cy] = P(gx, gy)
    pad("golgi", { kind: "path", d: sector(cx, cy, s(radii[0]) - 2, s(radii[radii.length - 1] + 0.016) + 2, a0, a1), cls: "dg-cp-pad" })
    for (const r of radii) add("golgi", { kind: "path", d: sector(cx, cy, s(r), s(r + 0.016), a0, a1), cls: "" })
  }
  if (parts.has("vesicles")) {
    for (const [fx, fy] of place.ves) {
      const [cx, cy] = P(fx, fy)
      const r = Math.max(3, s(0.018))
      pad("vesicles", { kind: "circle", cx, cy, r: Math.max(7, r + 2), cls: "dg-cp-pad" })
      add("vesicles", { kind: "circle", cx, cy, r, cls: "" })
    }
  }
  dots()
  return { h, shapes, zones, ports, edges, side: place.side }
}

// ---- layout -----------------------------------------------------------------------------------------------------------------------------

// A label measured in its own classes (a bold name is wider than the plain text label() measures): its box is the one the page draws.
function say(ctx, text, x, y, opts = {}) {
  const px = Math.max(opts.px ?? ctx.fontPx, ctx.fontPx)
  const m = ctx.measure(text, px, opts.maxW, opts.cls ?? "")
  const item = label(ctx, text, x, y, opts)
  const w = Math.ceil(Math.min(m.w, opts.maxW ?? m.w))
  const h = Math.ceil(m.h)
  if (w > item.w) {
    if (item.anchor === "middle") item.x = Math.round(x - w / 2)
    else if (item.anchor === "end") item.x = Math.round(x - w)
    item.w = w
  }
  if (h > item.h) {
    if ((opts.valign ?? "top") === "middle") item.y = Math.round(y - h / 2)
    else if (opts.valign === "bottom") item.y = Math.round(y - h)
    item.h = h
  }
  if (opts.maxW && h > ctx.lineH) item.wrap = true
  return item
}

const labelsOf = (eff) => eff.labels ?? "all"

// The parts lit in a state: the highlight, or with "Solo le differenze" the parts that one cell has and the other has not.
function litParts(eff, ctx, select) {
  if (select) return new Set()
  if (comparing(eff, ctx)) return new Set(differences(eff.cells))
  return new Set(eff.highlight ?? [])
}

const comparing = (eff, ctx) => eff.cells.length === 2 && labelsOf(eff) !== "none" && (ctx.controls?.compare ?? []).includes("diff") && differences(eff.cells).length > 0

export function differences(cells) {
  if (cells.length !== 2) return []
  const [a, b] = cells
  return ORDER.filter((p) => p !== "dna" && (a.parts.includes(p) !== b.parts.includes(p)))
}

// Does the figure name the DNA of a eukaryotic cell (in a highlight, a path or a note of any state)? Then the threads inside its nucleus get a label, a
// zone and a number of their own, in every state (so the numbers never change from one state to the next).
function namesDna(data) {
  const scopes = [data, ...(data.states ?? [])]
  return scopes.some((x) => (x.highlight ?? []).includes("dna") || (x.paths ?? []).some((p) => p.from === "dna" || p.to === "dna")) || (data.notes ?? []).some((n) => n.part === "dna")
}

// The parts of a cell that carry a label, a zone and a target, in the canonical order.
function labelledParts(cell, data) {
  const list = ORDER.filter((p) => cell.parts.includes(p))
  if (isEukaryote(cell.kind) && namesDna(data)) list.splice(list.indexOf("nucleus") + 1, 0, "dna")
  return list
}

function noteOf(eff, cell, part) {
  const notes = eff.notes ?? []
  const own = notes.find((n) => n.part === part)
  if (own) return own.text_it
  if (part === dnaHome(cell) && cell.kind === "bacterium") return notes.find((n) => n.part === "dna")?.text_it ?? null
  return null
}

// The size of a zone as the text asks, or a little larger on a large drawing.
const nominalZone = (F, cw) => Math.max(Math.round(F * 1.45), Math.round(cw * 0.085))
// A select check's targets are buttons of at least 28 px on the page (draw.js selectTargets): the scene draws them that large, so that what the tests
// measure is what the student taps.
const SELECT_MIN = 28

// The target of the wall or of the membrane of a select figure: Z wide along its edge, from the gap between the two bands upwards (the wall's on the
// top edge: outwards; the membrane's on the bottom edge: inwards), so it never reaches the other band.
const edgeBox = (e, Z) => ({ x: Math.round(e.along - Z / 2), y: Math.floor(e.mid - Z), w: Z, h: Z })

// The size of the zones of a cell: as large as the text size asks, but never so large that two zones of the cell touch; at least 24 px (A3).
function zoneSize(zones, F, W, cw) {
  const nominal = nominalZone(F, cw)
  // a zone on the very edge of the scene is pushed inside it: the room between zones is measured where they will be
  const pts = Object.values(zones).map(([x, y]) => [Math.max(nominal / 2, Math.min(W - nominal / 2, x)), Math.max(nominal / 2, y)])
  let room = Infinity
  for (let a = 0; a < pts.length; a++) for (let b = a + 1; b < pts.length; b++) room = Math.min(room, Math.max(Math.abs(pts[a][0] - pts[b][0]), Math.abs(pts[a][1] - pts[b][1])) - 3)
  return Math.max(24, Math.min(nominal, Math.floor(room)))
}

// Which shapes of a lit part get the halo: the outline of an organelle, the edge, the wall, the threads of DNA, the dots, the tail; not the inner
// details (folds, stacks), not the faint zone of the nucleoid, not the cytoplasm (lit by its tint while the rest dims).
function haloed(part, cls) {
  if (part === "cytoplasm") return false
  if (cls === "" || cls === "dg-cp-dot" || cls === "dg-cp-band") return true
  return /dg-cp-(edge|thread|tail)/.test(cls)
}

function arrowhead(ctx, x, y, angle, cls) {
  const s = Math.round(ctx.fontPx * 0.6)
  const pt = (dx, dy) => [x + dx * Math.cos(angle) - dy * Math.sin(angle), y + dx * Math.sin(angle) + dy * Math.cos(angle)]
  shape(ctx, "polygon", { points: [pt(0, 0), pt(-s, -s * 0.55), pt(-s, s * 0.55)], cls })
}

// A point on the edge of a port, towards (tx, ty).
function edge(port, tx, ty) {
  const a = Math.atan2(ty - port.cy, tx - port.cx)
  return [port.cx + port.rx * Math.cos(a), port.cy + port.ry * Math.sin(a)]
}

function build(data, ctx) {
  const eff = effectiveState(data, ctx.state)
  const select = ctx.mode === "select"
  const labels = select ? "none" : labelsOf(eff)
  const cells = data.cells
  const n = cells.length
  const F = ctx.fontPx
  const W = ctx.width
  const gap = Math.round(F * 1.4)
  const lit = litParts(eff, ctx, select)
  const beside = n === 2 && W >= 600
  const colW = beside ? Math.floor((W - gap) / 2) : W
  const maxCell = Math.round(F * ({ s: 15, m: 19, l: 23 }[data.size] ?? 21))
  const minCell = Math.max(220, Math.round(F * 11))
  const leader = Math.round(F * 0.8)
  const labW = Math.round(F * 8)
  const lists = cells.map((c) => labelledParts(c, data))
  // sides when every cell can have its names in two columns beside it, else numbers on the parts and one key
  // the names are measured only when they are drawn: the page's measuring probe keeps the last text it measured, and a figure that names
  // nothing (a select check's own) must not carry a part's name anywhere in its DOM
  const sideWidths = cells.map((c, i) => {
    if (labels !== "all") return { left: 0, right: 0 }
    const sides = geometry(c.kind, 0, 0, 100, c, eff).side
    const width = (s) => Math.max(0, ...lists[i].filter((p) => (sides[p] ?? "right") === s).map((p) => Math.min(labW, Math.ceil(ctx.measure(nameOf(p), F, labW, "dg-clabel").w))))
    return { left: width("left"), right: width("right") }
  })
  const fits = (sw) => colW - sw.left - sw.right - 2 * leader - 8 >= minCell
  const style = labels !== "all" ? "plain" : sideWidths.every(fits) ? "sides" : "numbers"
  const numbers = style === "numbers" ? ORDER.filter((p) => lists.some((l) => l.includes(p))) : []
  const numberOf = (p) => numbers.indexOf(p) + 1
  const targets = []
  const hits = []
  const pending = [] // path labels that found no room inside their cell
  const leaders = [] // the leader lines drawn so far: a path's label keeps off them
  let failed = null
  let bottom = 0
  let y = 0
  // a zone's square, kept inside the scene (the wall's zone of a plant cell sits on its left edge)
  const zoneBox = (zx, zy, z) => ({ x: Math.max(0, Math.min(W - z, Math.round(zx - z / 2))), y: Math.max(0, Math.round(zy - z / 2)), w: z, h: z })
  cells.forEach((cell, i) => {
    const sw = sideWidths[i]
    const colX = beside ? i * (colW + gap) : 0
    const top = beside ? 0 : y
    const avail = style === "sides" ? colW - sw.left - sw.right - 2 * leader - 8 : colW
    const cw = Math.max(Math.min(avail, maxCell), Math.min(avail, minCell))
    const geo = (x0, y0) => geometry(cell.kind, x0, y0, cw, cell, eff, { select })
    const left = style === "sides" ? colX + sw.left + leader + 4 + Math.max(0, Math.floor((avail - cw) / 2)) : colX + Math.floor((colW - cw) / 2)
    let cy = top
    if (cell.label_it) {
      const t = say(ctx, cell.label_it, colX + colW / 2, cy, { anchor: "middle", cls: "dg-ctitle", maxW: colW - 8, key: select ? undefined : `cell:${i}:title` })
      cy += t.h + Math.round(F * 0.35)
    }
    // a select figure keeps room above a wall for the wall's target, which reaches out of the cell's top edge (its targets are at most this large)
    const wallEdge = geo(0, 0).edges.wall
    if (wallEdge) cy += Math.max(0, Math.ceil(Math.max(SELECT_MIN, nominalZone(F, cw)) - wallEdge.mid))
    const g = geo(left, cy)
    const drawnLit = (part) => lit.has(part) || (part === dnaHome(cell) && cell.kind === "bacterium" && lit.has("dna"))
    const anyLit = lit.size > 0 // a lit part anywhere dims the rest of the figure, a cell without it included
    const parts = lists[i]
    const tappable = labels === "all" || labels === "tap"
    // all and tap: every shape of a part, and the invisible pads along its thin lines, read that part when tapped (draw.js forwards the tap to the
    // part's button); the threads of a nucleus whose DNA has no label of its own read the nucleus
    const hitOf = (part) => (tappable ? `cell:${i}:${parts.includes(part) ? part : "nucleus"}` : undefined)
    const z = zoneSize(Object.fromEntries(parts.map((p) => [p, g.zones[p]])), F, W, cw)
    // select: one neutral zone per part (no name anywhere), in the canonical order, each as large as its button on the page; the wall's and the
    // membrane's of a walled cell keep to their own band (edgeBox)
    const Z = Math.max(z, SELECT_MIN)
    const boxes = select ? ORDER.filter((p) => cell.parts.includes(p)).map((part) => [part, g.edges[part] ? edgeBox(g.edges[part], Z) : zoneBox(...g.zones[part], Z)]) : []
    // a ribosome's dot under another part's target is left out of a select figure: with a dot in it, that target would look like the ribosomes'
    const underOther = (s) => boxes.some(([part, b]) => part !== "ribosomes" && s.cx + s.r + 2 > b.x && s.cx - s.r - 2 < b.x + b.w && s.cy + s.r + 2 > b.y && s.cy - s.r - 2 < b.y + b.h)
    // the shapes, part by part, with the halo of a lit part behind it
    for (const { part, s, pad } of g.shapes) {
      if (pad) {
        if (tappable) shape(ctx, s.kind, { ...s, hitFor: hitOf(part) })
        continue
      }
      if (select && s.cls === "dg-cp-dot" && underOther(s)) continue
      const own = part === "dna" ? (drawnLit("dna") ? "is-lit" : anyLit ? "is-dim" : "") : drawnLit(part) ? "is-lit" : anyLit ? "is-dim" : ""
      const cls = select ? `dg-cp dg-cp-neutral ${s.cls}`.trim() : `dg-cp dg-cp-${part} ${s.cls} ${own}`.replace(/\s+/g, " ").trim()
      if (!select && own === "is-lit" && haloed(part, s.cls)) shape(ctx, s.kind, { ...s, cls: `dg-cp-halo${s.cls === "dg-cp-dot" ? " dg-cp-halo-dot" : ""}`, hitFor: hitOf(part) })
      shape(ctx, s.kind, { ...s, cls, hitFor: hitOf(part) })
    }
    for (const [, b] of boxes) {
      const t = `t${targets.length + 1}`
      shape(ctx, "rect", { ...b, r: 6, cls: "dg-czone", target: t })
      targets.push({ target: t, bbox: b })
    }
    // the names
    let colBottom = cy + g.h
    if (style === "sides") {
      for (const sideName of ["left", "right"]) {
        const list = parts.filter((p) => (g.side[p] ?? "right") === sideName).sort((a, b) => g.zones[a][1] - g.zones[b][1])
        let next = cy
        for (const part of list) {
          const [zx, zy] = g.zones[part]
          const m = ctx.measure(nameOf(part), F, labW, "dg-clabel")
          const w = Math.min(labW, Math.ceil(m.w))
          const ly = Math.max(next, Math.round(zy - m.h / 2))
          const lx = sideName === "left" ? left - leader - 4 - w : left + cw + leader + 4
          const cls = `dg-clabel${drawnLit(part) ? " dg-clabel-lit" : anyLit ? " dg-clabel-dim" : ""}`
          const item = say(ctx, nameOf(part), lx, ly, { anchor: "start", maxW: w, cls, key: `cell:${i}:${part}:label` })
          const ex = sideName === "left" ? item.x + item.w + 3 : item.x - 3
          const seg = { x1: ex, y1: item.y + Math.min(item.h, ctx.lineH) / 2, x2: zx, y2: zy }
          leaders.push(seg)
          shape(ctx, "line", { ...seg, cls: `dg-cleader${drawnLit(part) ? " is-lit" : ""}` })
          shape(ctx, "circle", { cx: zx, cy: zy, r: 3.5, cls: "dg-cleader-dot" })
          next = item.y + item.h + 4
          colBottom = Math.max(colBottom, next)
        }
      }
    }
    if (style === "numbers") {
      const box = { x0: left, x1: left + cw, y0: cy, y1: cy + g.h }
      for (const part of parts) {
        const text = String(numberOf(part))
        const m = ctx.measure(text, F)
        const rr = Math.max(Math.round(F * 0.62), Math.ceil(m.w / 2) + 4)
        // a number stays whole inside the scene (the wall's zone of a plant cell is on its very edge)
        const zx = Math.max(rr + 1, Math.min(W - rr - 1, g.zones[part][0]))
        const zy = g.zones[part][1]
        const probe = { x: Math.round(zx - m.w / 2), y: Math.round(zy - m.h / 2), w: Math.ceil(m.w), h: Math.ceil(m.h) }
        const free = !ctx.labels.some((l) => l.x < probe.x + probe.w && probe.x < l.x + l.w && l.y < probe.y + probe.h && probe.y < l.y + l.h)
        const r = rr
        const cls = `dg-cbadge${drawnLit(part) ? " is-lit" : anyLit ? " is-dim" : ""}`
        if (free) {
          shape(ctx, "circle", { cx: zx, cy: zy, r, cls })
          say(ctx, text, zx, zy, { anchor: "middle", valign: "middle", cls: "dg-cnum", key: `cell:${i}:${part}:num` })
        } else {
          // two zones too close for two numbers at this text size: the number moves aside, with a short leader to its part
          const item = labelNear(ctx, text, zx, zy, r + 2, box, { cls: "dg-cnum" })
          if (!item) {
            failed = `no room for the number of ${part}`
            continue
          }
          const bx = item.x + item.w / 2
          const by = item.y + item.h / 2
          shape(ctx, "line", { x1: zx, y1: zy, x2: bx, y2: by, cls: "dg-cleader" })
          shape(ctx, "circle", { cx: bx, cy: by, r, cls })
        }
      }
    }
    // the arrows of the state, in this cell when it has both parts
    ;(eff.paths ?? []).forEach((p, k) => {
      if (!has(cell, p.from) || !has(cell, p.to)) return
      const pa = g.ports[p.from] ?? { cx: g.zones[p.from][0], cy: g.zones[p.from][1], rx: 0, ry: 0 }
      const pb = g.ports[p.to] ?? { cx: g.zones[p.to][0], cy: g.zones[p.to][1], rx: 0, ry: 0 }
      const [ax, ay] = edge(pa, pb.cx, pb.cy)
      const [bx, by] = edge(pb, pa.cx, pa.cy)
      const len = Math.hypot(bx - ax, by - ay) || 1
      const mx = (ax + bx) / 2 - ((by - ay) / len) * len * 0.18
      const my = (ay + by) / 2 + ((bx - ax) / len) * len * 0.18
      shape(ctx, "path", { d: `M${r1(ax)} ${r1(ay)} Q${r1(mx)} ${r1(my)} ${r1(bx)} ${r1(by)}`, cls: "dg-cpath", key: select ? undefined : `cell:${i}:path:${k}:${p.from}:${p.to}` })
      arrowhead(ctx, bx, by, Math.atan2(by - my, bx - mx), "dg-cpathhead")
      if (p.label_it) {
        const box = { x0: left, x1: left + cw, y0: cy, y1: cy + g.h }
        // beside the bulge of the arrow, on its outer side, so the label does not sit on the line
        const apexX = (ax + 2 * mx + bx) / 4
        const apexY = (ay + 2 * my + by) / 4
        const out = Math.hypot(mx - (ax + bx) / 2, my - (ay + by) / 2) || 1
        const px = apexX + ((mx - (ax + bx) / 2) / out) * F * 0.9
        const py = apexY + ((my - (ay + by) / 2) / out) * F * 0.9
        // it keeps off the arrow, the leader lines and the parts' zones; with no such place inside the cell it goes under the figure
        const keepOff = [{ x1: ax, y1: ay, x2: apexX, y2: apexY }, { x1: apexX, y1: apexY, x2: bx, y2: by }, ...leaders]
        for (const part of parts) {
          const [zx, zy] = g.zones[part]
          keepOff.push({ x1: zx - z / 2, y1: zy - z / 2, x2: zx + z / 2, y2: zy + z / 2 }, { x1: zx + z / 2, y1: zy - z / 2, x2: zx - z / 2, y2: zy + z / 2 })
        }
        const item = labelNear(ctx, p.label_it, px, py, 4, box, { cls: "dg-cpathtext", maxW: Math.round(cw * 0.6), avoid: keepOff })
        if (item && keepOff.some((seg) => crosses(seg, item, 1))) ctx.labels.splice(ctx.labels.indexOf(item), 1)
        if (!item || !ctx.labels.includes(item)) pending.push(p.label_it)
      }
    })
    // the tap targets (all and tap)
    if (labels === "all" || labels === "tap") {
      for (const part of parts) {
        const [zx, zy] = g.zones[part]
        hits.push({ key: `cell:${i}:${part}`, id: `c${i + 1}.${part}`, ...zoneBox(zx, zy, z), name: cap(nameOf(part)), text: cell.label_it ?? KIND_IN[cell.kind], hint_it: TEXT.hit_hint, note_it: noteOf(eff, cell, part) ?? PARTS[part].job_it })
      }
    }
    bottom = Math.max(bottom, colBottom)
    y = colBottom + gap
  })
  if (failed) return { error: { path: "", message: failed, code: "E-DIAGRAM-LAYOUT" } }
  let yy = bottom + Math.round(F * 0.5)
  // the path labels that did not fit inside their cell, under the figure
  for (const text of pending) {
    const item = say(ctx, `→ ${text}`, 4, yy, { anchor: "start", cls: "dg-cpathtext", maxW: W - 8 })
    yy += item.h + 4
  }
  // the key of the numbers: one row per part, in columns when they fit
  if (style === "numbers") {
    const r = Math.round(F * 0.62)
    const rowW = Math.min(W - 8, Math.max(...numbers.map((p) => Math.ceil(ctx.measure(nameOf(p), F, W - 2 * r - 20).w))) + 2 * r + 14)
    const cols = Math.max(1, Math.min(3, Math.floor((W + 12) / (rowW + 12))))
    const rows = Math.ceil(numbers.length / cols)
    const cursor = Array.from({ length: cols }, () => yy)
    numbers.forEach((part, k) => {
      const c = Math.floor(k / rows)
      const x = c * (rowW + 12)
      const m = ctx.measure(nameOf(part), F, rowW - 2 * r - 14)
      const rowH = Math.max(m.h, 2 * r, ctx.lineH)
      const ry = cursor[c]
      const isLit = [...lit].some((l) => l === part || (part === "nucleoid" && l === "dna"))
      shape(ctx, "circle", { cx: x + r + 2, cy: ry + Math.min(rowH, ctx.lineH) / 2, r, cls: `dg-cbadge${isLit ? " is-lit" : ""}` })
      say(ctx, String(k + 1), x + r + 2, ry + Math.min(rowH, ctx.lineH) / 2, { anchor: "middle", valign: "middle", cls: "dg-cnum", key: `key:${part}:n` })
      say(ctx, nameOf(part), x + 2 * r + 12, ry + Math.max(0, (Math.min(rowH, ctx.lineH) - ctx.lineH) / 2), { anchor: "start", maxW: rowW - 2 * r - 14, cls: `dg-ckey${isLit ? " dg-clabel-lit" : ""}`, key: `key:${part}` })
      cursor[c] = ry + rowH + 6
    })
    const maxY = Math.max(...cursor)
    yy = maxY + 4
  }
  if (labels === "all" || labels === "tap") {
    const item = say(ctx, labels === "tap" ? TEXT.hint_tap : TEXT.hint_all, 4, yy, { anchor: "start", cls: "dg-hint", maxW: W - 8 })
    yy += item.h + 4
  }
  const out = finish(ctx, yy + 4, { states: stateCount(data), state: ctx.state })
  if (out.error) return out
  out.style = style
  if (select) {
    out.targets = targets
    return out
  }
  out.hits = hits
  if (comparing(eff, ctx)) out.live = liveLine(eff)
  return out
}

function liveLine(eff) {
  const diff = differences(eff.cells)
  if (labelsOf(eff) === "none") return "Accese le parti che ha solo una delle due cellule."
  return `Accese le parti che ha solo una delle due cellule: ${listIt(diff.map(nameOf))}.`
}

export const layout = (data, opts) => run(data, opts, { schema, semantic, build })

// ---- controls, description, targets, printed -----------------------------------------------------------------------------------------------

// "Solo le differenze": two cells whose parts differ, when the figure names its parts (a figure with labels none, the select check's own included, has none).
export function controls(data) {
  if (data.cells?.length !== 2 || (data.labels ?? "all") === "none" || differences(data.cells).length === 0) return []
  return [{ id: "compare", kind: "chips", multi: true, label_it: TEXT.compare, values: [{ value: "diff", label_it: TEXT.diff }] }]
}

// A cell in words: the author's label when it has one, else its kind. A figure that asks which kind a cell is (an example's blank, "E la
// seconda?") labels it "Seconda cellula": its description and its tap buttons must not answer for the student.
const cellWords = (cell) => cell.label_it ?? KIND_IT[cell.kind]

function describeState(data, i, ctx) {
  const eff = effectiveState(data, i)
  const select = ctx?.mode === "select"
  const labels = select ? "none" : labelsOf(eff)
  const named = labels !== "none"
  const cells = data.cells
  const out = []
  if (select) {
    const count = cells.reduce((s, c) => s + c.parts.length, 0)
    out.push(`${cells.length === 2 ? "Due cellule" : "Una cellula"} senza scritte: ci sono ${count} parti da toccare.`)
    return out.join(" ")
  }
  const partsOf = (cell) => labelledParts(cell, data).map((p) => (named ? nameOf(p) : SHAPE_IT[p]))
  if (cells.length === 1) out.push(`Una cellula: ${cellWords(cells[0])}. ${named ? "Le sue parti" : "Le parti non hanno il nome; si vedono"}: ${listIt(partsOf(cells[0]))}.`)
  else {
    out.push(`Due cellule una accanto all'altra. La prima, ${cellWords(cells[0])}: ${listIt(partsOf(cells[0]))}. La seconda, ${cellWords(cells[1])}: ${listIt(partsOf(cells[1]))}.`)
  }
  const lit = comparing(eff, ctx ?? {}) ? differences(cells) : eff.highlight ?? []
  if (lit.length) out.push(named ? `${comparing(eff, ctx ?? {}) ? "Accese solo le differenze" : "Evidenziate"}: ${listIt(lit.map(nameOf))}.` : `Sono evidenziate ${lit.length === 1 ? "una parte" : `${lit.length} parti`}.`)
  for (const p of eff.paths ?? []) {
    out.push(named ? `Una freccia va da ${nameOf(p.from)} a ${nameOf(p.to)}${p.label_it ? `: ${p.label_it}` : ""}.` : `Una freccia va da una parte a un'altra${p.label_it ? `: ${p.label_it}` : ""}.`)
  }
  if (eff.fill?.vacuole) out.push(`${named ? "Il vacuolo" : "La grande sacca"} è ${FILL_IT[eff.fill.vacuole]}.`)
  return out.join(" ")
}

export function describe(data, ctx) {
  if (ctx?.mode === "select") return describeState(data, 0, ctx) // a select check's figure has no states: one neutral sentence
  const single = ctx?.state
  const count = stateCount(data)
  const one = (i) => `${count > 1 ? `Passo ${i + 1}. ${data.states[i]?.op_it ? `${data.states[i].op_it}. ` : ""}` : ""}${describeState(data, i, ctx)}`
  if (single !== undefined || count === 1) return one(Math.min(single ?? 0, count - 1))
  return Array.from({ length: count }, (_, i) => one(i)).join(" ")
}

// The stored ids of set `parts` in reading order: the parts of the first cell in the table's order (c1.wall, c1.membrane...), then the second's.
export function targetIds(data, set) {
  if (set !== "parts") return []
  return data.cells.flatMap((cell, i) => ORDER.filter((p) => cell.parts.includes(p)).map((p) => `c${i + 1}.${p}`))
}

// targets(data, set) -> [{ key, bbox, neutral_it }]
export function targets(data, set, opts = {}) {
  const ids = targetIds(data, set)
  if (ids.length === 0) return []
  const scene = layout(data, { width: 360, fontPx: 20, subject: "biology", ...opts, mode: "select", set, state: 0 })
  if (scene.error) return []
  return scene.targets.map((t, i) => ({ key: ids[i], bbox: t.bbox, neutral_it: `Parte ${i + 1} di ${ids.length}` }))
}

// Every string the state prints (L4); Ruby's printed() returns the same set. A tap reveals a part's name and its job or note (L8): with labels all or tap
// they count as printed.
export function printed(data, state = 0) {
  const eff = effectiveState(data, state)
  const labels = labelsOf(eff)
  const out = new Set()
  for (const cell of data.cells) if (cell.label_it) out.add(cell.label_it)
  if (labels !== "none") {
    for (const cell of data.cells) {
      for (const part of labelledParts(cell, data)) {
        out.add(nameOf(part))
        out.add(noteOf(eff, cell, part) ?? PARTS[part].job_it)
      }
    }
    out.add(labels === "tap" ? TEXT.hint_tap : TEXT.hint_all)
  }
  for (const p of eff.paths ?? []) if (p.label_it) out.add(p.label_it)
  const op = data.states?.[state]?.op_it
  if (op) out.add(op)
  return [...out]
}
