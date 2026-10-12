// periodic_table: reserved (w2-1, track T7). The contract stub of WAVE2 1.2: replace layout and describe, keep the
// exports, and add the optional ones the type needs (speechSegments, controls, targets, printed, recordAtRender, layout3d; see
// lesson/diagrams/contract.js). Until the registry says `available` a lesson cannot use it.
import schema from "lesson/diagram_schemas/periodic_table"
import { stub } from "lesson/diagrams/stub"

export const type = "periodic_table"
export { schema }
export const { layout, describe } = stub(type)
