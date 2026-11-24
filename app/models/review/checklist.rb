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

    # Only a practice item (kind practice_item) is reviewed on two more points (A2.6).
    PRACTICE_POINTS = [
      "hints that are missing, give the key, or do not run from the rule to the next step",
      "a typical-error message that gives the key, or a solution step that is wrong or ends elsewhere than at the key"
    ].freeze

    # A bilingual item (english or spanish, D-402) is reviewed on two more points, with ids of their own (14 and 15), so that a review of an item
    # that is not bilingual keeps its 11 or 13 points and the ids of a stored review still read from ALL_POINTS.
    TRANSLATION_POINTS = [
      "an Italian translation that is wrong, adds or drops something, or gives the key away",
      "target-language text above the level, unclear, or with Italian words in it"
    ].freeze
    ALL_POINTS = (POINTS + PRACTICE_POINTS + TRANSLATION_POINTS).freeze
    PRACTICE_IDS = (POINTS.size + 1..POINTS.size + PRACTICE_POINTS.size).to_a.freeze
    TRANSLATION_IDS = (POINTS.size + PRACTICE_POINTS.size + 1..ALL_POINTS.size).to_a.freeze

    # Evidence that says nothing: what a bare "all verified" looks like.
    STOCK = /\A\W*(tutto|all|everything|nulla|niente|nessun problema|no problem|nothing|ok|okay|va bene|verificat[oa]|verified|checked|controllat[oa]|fine|bene|pass|passa|n\/a|na)(\W+(a posto|verificato|verified|checked|ok|controllato|fine|bene|to report|da segnalare))?\W*\z/i
    MIN_WORDS = 4

    module_function

    # The ids of the points of a review: 1..11, then 12 and 13 for a practice item, then 14 and 15 for a bilingual one (an item that is
    # bilingual and not a practice item has 1..11, 14, 15).
    def ids(practice:, bilingual: false) = (1..POINTS.size).to_a + (practice ? PRACTICE_IDS : []) + (bilingual ? TRANSLATION_IDS : [])

    # 13 points for a practice item, 11 for any other; two more for a bilingual one.
    def expected_count(practice:, bilingual: false) = ids(practice: practice, bilingual: bilingual).size

    def all(practice: false, bilingual: false) = ids(practice: practice, bilingual: bilingual).map { |id| { id: id, point: ALL_POINTS[id - 1] } }

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
