module Review
  # The eight points of the lesson review (A2.5); the numbers are the ids of banco.lesson_review/1 and
  # briefs/lesson-review.md has the same list in prose.
  module LessonChecklist
    POINTS = [
      "numbers: every number of examples, exercises and solutions recomputed in exact arithmetic",
      "solutions: each correct and complete, and its final equals finals_it",
      "rules stated precisely, with their common exceptions; no absolute word without a counterexample check",
      "Errori da evitare are real misconceptions and match the typical errors of the skills",
      "worked examples: every step has its reason; no step S cannot follow",
      "scope: the content matches the cited lines, nothing of a later year, the kind fits the skills' scope",
      "readability and tone: short sentences, one idea per paragraph, no double negation, tu, kind and neutral; no exam-gaming wording, no self-certification, no page or chapter numbers",
      "Prova tu: easy to hard, at least one exercise aimed at a typical error, none gives its answer away"
    ].freeze

    module_function

    def all = POINTS.each_with_index.map { |text, i| { id: i + 1, text: text } }
  end
end
