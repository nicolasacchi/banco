// The browser side of the component contract v2 (WAVE2-COMPONENTS 1.2; extends A7 and D-253). A diagram type is a module
// app/javascript/lesson/diagrams/FAMILY/TYPE.js (the flat modules of release 1 follow the same shape):
//
//   export function layout(data, ctx)     pure. ctx: { width, fontPx, measure, subject, state, revealed, controls, mode }
//                                         mode: "student" | "teacher" | "print" | "render" | "select"
//                                         revealed: the ids the student has opened so far (taps, Avanti, flips)
//                                         returns a Scene, or { error: { path, message, code } }; never throws
//   export function describe(data, ctx)   Italian text of what is VISIBLE in ctx.state with ctx.revealed (the "Descrizione", screen
//                                         readers, print); never a hidden or not-yet-revealed value
//   export function speechSegments(data, ctx) optional: speech segments [{ lang, text }] of the same visible state (default: describe
//                                         as one "it" segment, see defaultSegments)
//   export function controls(data)        optional: [{ id, kind, range?, values?, label_it }]; draw.js builds native controls.
//                                         kind: stepper | slider | toggle | chips | runner | tap. A slider ALWAYS comes with its
//                                         - and + buttons (A2): controls() cannot declare a slider alone (checkControls)
//   export function targets(data, set)    optional: select targets of a set in reading order: [{ key, bbox, neutral_it }]
//   export function printed(data, state)  optional: every string the state prints, INCLUDING describe() of that state, hidden
//                                         ids' labels and served reveals (L4)
//   export function recordAtRender(data)  optional, `program` only in wave 2: runs in the server's Chrome at the render check and
//                                         returns { records, findings }; never called in S's page (firm rule 3)
//   export function layout3d(data)        optional, W2-3: a Scene3D (WAVE2 2.12)
//   export const schema                   the type's compiled schema (lesson/diagram_schemas/TYPE); core types use diagram_schema
//
// Scene additions (draw.js): shapes[].target (the served target id tN, a focusable hit area only in mode "select"),
// shapes[].pattern (hatch | dots | cross | grid, a fixed <defs> set), labels[].lang (en | es | la), labels[].tap (a popover id),
// frames[] ({ bbox, scroll: true }: a declared horizontal scroll frame with a fixed first column; only `sheet` uses it).

export const MODES = ["student", "teacher", "print", "render", "select"]
export const CONTROL_KINDS = ["stepper", "slider", "toggle", "chips", "runner", "tap"]
export const PATTERNS = ["hatch", "dots", "cross", "grid"]
export const LANGS = ["en", "es", "la"]
export const OPTIONAL_EXPORTS = ["speechSegments", "controls", "targets", "printed", "recordAtRender", "layout3d"]

// The default speech of a figure: its description as one Italian segment.
export function defaultSegments(describe, data, ctx) {
  const text = describe(data, ctx)
  return text ? [{ lang: "it", text }] : []
}

// A list of controls as controls() returns it: problems as strings (empty when the list is a legal one).
export function checkControls(list) {
  const problems = []
  const seen = new Set()
  for (const control of list ?? []) {
    if (!CONTROL_KINDS.includes(control.kind)) problems.push(`${control.id}: unknown kind ${control.kind}`)
    if (seen.has(control.id)) problems.push(`${control.id}: declared twice`)
    seen.add(control.id)
    if (!control.label_it) problems.push(`${control.id}: no label_it`)
    if (control.kind === "slider" && !(control.range && control.step)) problems.push(`${control.id}: a slider declares its range and step (it is drawn with - and + buttons)`)
  }
  return problems
}

// A module against the contract: problems as strings (empty when the module has the required exports and the optional ones are functions).
export function checkModule(mod) {
  const problems = []
  if (typeof mod?.layout !== "function") problems.push("layout is not a function")
  if (typeof mod?.describe !== "function") problems.push("describe is not a function")
  for (const name of OPTIONAL_EXPORTS) if (mod && name in mod && typeof mod[name] !== "function") problems.push(`${name} is exported but not a function`)
  return problems
}
