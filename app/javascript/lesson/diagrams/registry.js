// The diagram types of release 1 (A7, A8): type name -> module { layout, describe, states }.
import * as balance from "lesson/diagrams/balance"
import * as number_line from "lesson/diagrams/number_line"
import * as area_model from "lesson/diagrams/area_model"
import * as table from "lesson/diagrams/table"
import * as cartesian from "lesson/diagrams/cartesian"
import * as sentence from "lesson/diagrams/sentence"
import * as concept_map from "lesson/diagrams/concept_map"
import * as flow from "lesson/diagrams/flow"
import * as equation_parts from "lesson/diagrams/equation_parts"
import { run } from "lesson/diagrams/run"

export const TYPES = { balance, equation_parts, number_line, area_model, table, cartesian, sentence, concept_map, flow }

export function moduleFor(type) {
  return TYPES[type] ?? null
}

// layout(data, { width, fontPx, measure, subject, state, tryValue }) -> Scene | { error: { path, message, code } }
export function layout(data, opts) {
  const mod = moduleFor(data?.type)
  if (mod) return mod.layout(data, opts)
  return run(data, opts, { build: () => ({ error: { path: "/type", message: "unknown diagram type", code: "E-LESSON-DIAGRAM" } }) })
}

export function describe(data) {
  const mod = moduleFor(data?.type)
  try {
    return mod ? mod.describe(data) : ""
  } catch (_error) {
    return ""
  }
}

export function stateCount(data) {
  return Array.isArray(data?.states) && data.states.length > 0 ? data.states.length : 1
}
