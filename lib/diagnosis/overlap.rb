# frozen_string_literal: true

module Diagnosis
  # How alike two instances of one item look to the student (D-297). Pure: it reads
  # Plan::Instance#texts, which the loader fills from the instance display.
  #
  # texts is {strong: [...], weak: [...]}, each text already normalized the way the text
  # grader normalizes (Grading::Closed::Text.normalize). Strong texts are what the student
  # recognises an instance by: the stem (and a testlet's passage), the left rows of a
  # matching, the elements of an ordering, the options of a choice. Weak texts are the right
  # column of a matching, whose categories repeat by nature.
  #
  #   alike(a, b) = STRONG_WEIGHT * |strong(a) & strong(b)| + |weak(a) & weak(b)|
  module Overlap
    STRONG_WEIGHT = 2

    module_function

    def alike(a, b)
      ta = a.texts
      tb = b.texts
      return 0 unless ta && tb

      STRONG_WEIGHT * (ta[:strong] & tb[:strong]).size + (ta[:weak] & tb[:weak]).size
    end

    # Of +fitting+ (the engine's candidates in order), the instance to serve: the first one
    # of the first candidate's item with the lowest total overlap with the +served+
    # instances of that item. With none served, or equal overlaps, that is the first
    # candidate itself, so a run without repeats is unchanged.
    def least_alike(fitting, served)
      first = fitting.first
      before = served.select { |s| s.item == first.item && s.id != first.id }
      return first if before.empty?

      fitting.select { |i| i.item == first.item }.min_by.with_index { |i, n| [ before.sum { |s| alike(i, s) }, n ] }
    end
  end
end
