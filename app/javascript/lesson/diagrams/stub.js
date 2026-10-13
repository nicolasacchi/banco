// The stub of a diagram type that is reserved or a draft (D-265). The registry holds a type back until its track has built
// it; until then layout() answers the contract's error and describe() says nothing. Never mounted on a stored lesson:
// Lessons::Types refuses the name at submit.
import { fail } from "lesson/diagrams/common"

export function stub(type) {
  return {
    layout: () => fail("/type", `${type} is not available yet`, "E-LESSON-DIAGRAM"),
    describe: () => ""
  }
}
