// program: draft (w2-2, track T9). The contract stub of WAVE2 1.2: replace layout and describe, keep the
// exports, and add the optional ones the type needs (speak, controls, targets, printed, recordAtRender, layout3d; see
// lesson/diagrams/contract.js). Until the registry says `available` a lesson cannot use it.
import schema from "lesson/diagram_schemas/program"
import { stub } from "lesson/diagrams/stub"

export const type = "program"
export { schema }
export const { layout, describe } = stub(type)

// recordAtRender(data) -> { records, findings }: runs the program in the server's Chrome at the render check (firm rule 3) and returns the
// records of every run (the default inputs and each try chip) and the findings (E-PROGRAM-BOUND, E-LESSON-VERIFY, E-CHECK-ANSWER-BY-SIMULATION). Never called in S's page.
export const recordAtRender = (_data) => ({ records: [], findings: [] })
