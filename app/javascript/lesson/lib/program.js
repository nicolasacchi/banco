// ProgramGrammar: The Ruby PARSER of the closed statement language of the program diagram (it never runs one); the JS twin lesson/lib/program.js also runs, only in browsers (firm rule 3).
// Contract stub of W2-0 (WAVE2 1.10, batch w2-2, track T9): the signatures below are frozen; the bodies are the track's. The Ruby twin is
// The Ruby side only PARSES (lib/lessons/program_grammar.rb); this module also runs, and only in browsers: the server's Chrome at the render check, firm rule 3. Vectors: test/fixtures/lesson2/program.json.
import { notBuilt } from "lesson/lib/not_built"

// name => signature
export const SIGNATURES = {
  "parse": "parse(statements)",
  "run": "run(statements, inputs)",
  "listing": "listing(statements, dialect)"
}

// Grammar, declared names, static caps (12 statements, depth 2, 6 variables, values within +-10^6): [] or findings.
export const parse = notBuilt("program.parse", "T9", "w2-2")
// JS only: a bounded run (200 executed blocks, 12 trace rows): {trace, outputs, memory, turns, findings}.
export const run = notBuilt("program.run", "T9", "w2-2")
// JS only: the generated Visual Basic listing from the structure.
export const listing = notBuilt("program.listing", "T9", "w2-2")
