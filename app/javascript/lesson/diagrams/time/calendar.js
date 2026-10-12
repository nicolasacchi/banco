// calendar: reserved (w2-3, track T4a). The contract stub of WAVE2 1.2: replace layout and describe, keep the
// exports, and add the optional ones the type needs (speak, controls, targets, printed, recordAtRender, layout3d; see
// lesson/diagrams/contract.js). Until the registry says `available` a lesson cannot use it.
import { stub } from "lesson/diagrams/stub"

export const type = "calendar"
export const { layout, describe } = stub(type)
