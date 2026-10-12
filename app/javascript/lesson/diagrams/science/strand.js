// strand: reserved (w2-1, track T7). The contract stub of WAVE2 1.2: replace layout and describe, keep the
// exports, and add the optional ones the type needs (speak, controls, targets, printed, recordAtRender, layout3d; see
// lesson/diagrams/contract.js). Home palette: biology. Until the registry says `available` a lesson cannot use it.
import schema from "lesson/diagram_schemas/strand"
import { stub } from "lesson/diagrams/stub"

export const type = "strand"
export { schema }
export const { layout, describe } = stub(type)
