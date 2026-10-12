# frozen_string_literal: true

module Lessons
  # ProgramGrammar: The Ruby PARSER of the closed statement language of the program diagram (it never runs one); the JS twin lesson/lib/program.js also runs, only in browsers (firm rule 3).
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-2, track T9): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/program.js and both run test/fixtures/lesson2/program.json (like Lessons::Num and lesson/num.js).
  module ProgramGrammar
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "parse" => "parse(statements)"
    }.freeze

    module_function

    # Grammar, declared names, static caps (12 statements, depth 2, 6 variables, values within +-10^6): [] or findings.
    def parse(statements)
      raise NotBuilt, "Lessons::ProgramGrammar.parse is not built yet (T9, w2-2)"
    end
  end
end
