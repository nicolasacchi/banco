# frozen_string_literal: true

module Lessons
  # Sheet: Calc formulas in Italian (functions, ';' separators, $ references): evaluation without loops or recursion, fill shift.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-3, track T9): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/sheet.js and both run test/fixtures/lesson2/sheet.json (like Lessons::Num and lesson/num.js).
  module Sheet
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "evaluate" => "evaluate(cells, ref)",
      "fill" => "fill(formula, rows, cols)"
    }.freeze

    module_function

    # The value of a cell.
    def evaluate(cells, ref)
      raise NotBuilt, "Lessons::Sheet.evaluate is not built yet (T9, w2-3)"
    end

    # A formula copied by an offset, with $ parts fixed.
    def fill(formula, rows, cols)
      raise NotBuilt, "Lessons::Sheet.fill is not built yet (T9, w2-3)"
    end
  end
end
