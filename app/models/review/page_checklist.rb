module Review
  # The eleven points of the page review (D-290, SPEC B8); the numbers are the ids of banco.page_review/1 and
  # briefs/page-review.md has the same list in prose. The reviewer never receives the course sources.
  module PageChecklist
    POINTS = [
      "content correct: the numbers and the science are right, the states are checked by hand",
      "agrees with the card that embeds it: notation, words and colour roles are the same",
      "why_free_it holds: a component of the lesson could not do this",
      "the first action is obvious, the instructions are short, everything works with the keyboard alone",
      "accessibility: a text alternative, visible focus, contrast, no colour alone",
      "reduced motion and the fallback are meaningful (look at the screenshots)",
      "performance is plausible and nothing renders in a loop when idle",
      "the code uses only the allowed APIs and libraries: no hidden network or navigation, randomness only from banco.random, time only from banco.now",
      "no practice answer and no try final is in the page",
      "readability and tone of its texts; no personal data",
      "no conditional behaviour without a visible reason: every branch on the seed, on a count of interactions or on elapsed time is explained by what the page teaches (the diff shows the new ones)"
    ].freeze

    module_function

    def all = POINTS.each_with_index.map { |text, i| { id: i + 1, text: text } }
  end
end
