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

    # banco.lesson/2 (A13): eleven points; the first eight are the lesson/1 points reread for cards, then the cards.
    POINTS2 = [
      "numbers: every check answer, step blank and try final recomputed in exact arithmetic; diagrams the machine checks (balance levels, points on lines, number line landings) are looked at in the screenshot",
      "solutions, check answers, the messages of the typical errors and step blanks are correct; each final equals its final_it",
      "rules stated precisely, with their common exceptions; no absolute word without a counterexample check",
      "mistakes are real misconceptions and their codes match the typical errors of the skills",
      "worked examples: every step has its reason; the reveal order makes sense; a faded step is solvable from the steps before it",
      "scope: the content matches the cited lines, nothing of a later year, the kind fits the skills' scope",
      "readability and tone, card by card: short sentences, one idea per paragraph, no double negation, tu, kind and neutral; no exam-gaming wording, no self-certification, no page or chapter numbers",
      "Prova tu: easy to hard, at least one exercise aimed at a typical error, none gives its answer away",
      "visuals: every diagram and schema says the same as the text; none draws something false to satisfy the visual rule; a colour role means the same on every card; alt_it describes the content; no decorative visual; no visual prints the answer of a check",
      "cards: one idea per card; the order builds up; no card needs a later one; the titles say the idea; the core path is complete without more blocks and extra cards",
      "free pages pinned by the lesson: na in this release (there are none)"
    ].freeze

    # A bilingual lesson (english or spanish, D-402) is reviewed on two more points (12 and 13): the same two as a bilingual item. A lesson that
    # is not bilingual keeps its 11, so the reviews already filed keep their count.
    TRANSLATION_POINTS = Checklist::TRANSLATION_POINTS

    module_function

    def all = POINTS.each_with_index.map { |text, i| { id: i + 1, text: text } }

    def lesson2?(revision) = revision.body["schema"] == "banco.lesson/2"

    def bilingual?(revision) = lesson2?(revision) && revision.body["bilingual"] == true

    # The points of a revision: 8 for banco.lesson/1, 11 for banco.lesson/2, 13 for a bilingual banco.lesson/2.
    def for(revision)
      points = lesson2?(revision) ? POINTS2 : POINTS
      points += TRANSLATION_POINTS if bilingual?(revision)
      points.each_with_index.map { |text, i| { id: i + 1, text: text } }
    end
  end
end
