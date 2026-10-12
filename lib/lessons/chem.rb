# frozen_string_literal: true

module Lessons
  # Chem: The formula grammar (case-exact symbols from chem/elements, one bracket level), atom counts and classes.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T7): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/chem.js and both run test/fixtures/lesson2/chem_formulas.json (like Lessons::Num and lesson/num.js).
  module Chem
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "parse" => "parse(formula)",
      "count" => "count(formula)",
      "classify" => "classify(formula)",
      "same_composition" => "same_composition(a, b)"
    }.freeze

    module_function

    # A formula as {coefficient, groups}; nil when it does not parse.
    def parse(formula)
      raise NotBuilt, "Lessons::Chem.parse is not built yet (T7, w2-1)"
    end

    # Atoms by symbol, coefficient included.
    def count(formula)
      raise NotBuilt, "Lessons::Chem.count is not built yet (T7, w2-1)"
    end

    # 'element' or 'compound'.
    def classify(formula)
      raise NotBuilt, "Lessons::Chem.classify is not built yet (T7, w2-1)"
    end

    # Whether two formulas have the same atom counts (a near miss of a typed answer).
    def same_composition(a, b)
      raise NotBuilt, "Lessons::Chem.same_composition is not built yet (T7, w2-1)"
    end
  end
end
