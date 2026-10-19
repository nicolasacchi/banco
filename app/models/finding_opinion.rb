# What the third reviewer thinks of one finding, derived from its assessments (D-222, D-316). Only the first
# opinion (model claude-opus-5-5) counts: the latest assessment that counts is the effective one. The state:
#
#   none      nobody has given a counting opinion yet
#   clear     the opinion says author_right or finding_right ("Chiaro")
#   unclear   the opinion says unclear
#
# D-316 dropped the second opinion (claude-haiku-4-5-20251001). Old second opinions stay in the ledger and show as
# history (#history); they never change a state. An assessment by a session whose true model equals the true model of
# the session that raised the finding does not count either (different_model_from_raiser, read time).
#
# Nothing here decides anything. A blocker or major finding with a clear opinion can be followed by the teacher with
# one click. A minor finding is closed (author_right) or marked to fix (finding_right) as a derived state, never as a
# row in decisions (D-239); a teacher's decision on the finding always wins (Teacher::TestReview).
class FindingOpinion
  attr_reader :first, :history

  def initialize(assessments)
    counting, history = assessments.partition(&:counts?)
    @history = history.sort_by(&:id)
    @first = counting.max_by(&:id)
  end

  def any? = !first.nil?

  def state
    return :none unless any?

    first.verdict == "unclear" ? :unclear : :clear
  end

  def clear? = state == :clear

  # author_right or finding_right when the opinion is clear, else nil.
  def verdict = clear? ? first.verdict : nil

  # The disposition that following a clear opinion records, or nil.
  def disposition = FindingAssessment::FOLLOW[verdict]

  # What a minor finding comes to without the teacher (D-239): :closed (the author is right), :to_fix (the finding is
  # right) or nil (unclear or no counting opinion: the teacher still has it).
  def minor_outcome
    { "author_right" => :closed, "finding_right" => :to_fix }[first&.verdict]
  end

  # The counting opinion, as a list.
  def given = [ first ].compact

  # Every assessment in the ledger, the ones that count and the history.
  def all = (given + history).sort_by(&:id)
end
