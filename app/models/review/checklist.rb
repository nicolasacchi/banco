module Review
  # The 11 points of the expert review (A-05). The numbers are the ids of
  # banco.review/1; briefs/review.md has the same list in prose.
  module Checklist
    POINTS = [
      "a wrong or ambiguous key",
      "a second defensible answer",
      "a distractor that is not a real misconception",
      "a rule that is too general (an absolute word without a counterexample)",
      "content of the following year in a base item",
      "a scope that does not match the programme markers",
      "unclear Italian or a double negation",
      "exam-gaming wording or self-certification",
      "a fact without a source",
      "a stem that gives the answer away",
      "an item that measures reading load or the interface instead of the skill"
    ].freeze

    # Evidence that says nothing: what a bare "all verified" looks like.
    STOCK = /\A\W*(tutto|all|everything|nulla|niente|nessun problema|no problem|nothing|ok|okay|va bene|verificat[oa]|verified|checked|controllat[oa]|fine|bene|pass|passa|n\/a|na)(\W+(a posto|verificato|verified|checked|ok|controllato|fine|bene|to report|da segnalare))?\W*\z/i
    MIN_WORDS = 4

    module_function

    def all = POINTS.each_with_index.map { |text, i| { id: i + 1, point: text } }

    # The ids of checklist points whose evidence is empty talk, and whether the
    # eleven pieces of evidence are not all different.
    # Why one piece of evidence is refused: :too_short, :stock_phrase or nil.
    def weak_reason(evidence)
      return :stock_phrase if evidence.to_s.match?(STOCK)
      :too_short if evidence.to_s.split.size < MIN_WORDS
    end

    def empty_evidence(checklist)
      weak = checklist.select { |c| weak_reason(c["evidence"]) }.map { |c| c["id"] }
      texts = checklist.map { |c| c["evidence"].to_s.strip.downcase }
      repeated = texts.tally.select { |_, n| n > 1 }.keys
      [ weak, repeated ]
    end
  end
end
