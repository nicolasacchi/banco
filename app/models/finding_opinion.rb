# What the third reviewer thinks of one finding, derived from its assessments (D-222). The first
# opinion (model claude-opus-5-5) and the second opinion (model claude-haiku-4-5-20251001) are
# the latest assessment of each model. The state:
#
#   none      nobody has assessed it yet
#   waiting   one of the two opinions is missing ("In attesa del secondo parere")
#   clear     both are there and say the same: author_right or finding_right ("Concordi")
#   unclear   both are there and both say unclear
#   split     both are there and differ ("Pareri discordanti")
#
# Nothing here decides anything. A blocker or major finding with a clear opinion can be followed
# by the teacher with one click. A minor finding with a clear opinion is closed (author_right) or
# marked to fix (finding_right) as a derived state, never as a row in decisions; a teacher's
# decision on the finding always wins (Teacher::TestReview).
class FindingOpinion
  attr_reader :first, :second

  def initialize(assessments)
    @first = assessments.select { |a| a.slot == :first }.max_by(&:id)
    @second = assessments.select { |a| a.slot == :second }.max_by(&:id)
  end

  def any? = !(first.nil? && second.nil?)

  def state
    return :none unless any?
    return :waiting if first.nil? || second.nil?
    return :split if first.verdict != second.verdict
    return :unclear if first.verdict == "unclear"

    :clear
  end

  def clear? = state == :clear

  # author_right or finding_right when the opinion is clear, else nil.
  def verdict = clear? ? first.verdict : nil

  # The disposition that following a clear opinion records, or nil.
  def disposition = FindingAssessment::FOLLOW[verdict]

  # What a minor finding comes to without the teacher: :closed (the author is right), :to_fix (the
  # finding is right) or nil (the teacher still has it).
  def minor_outcome
    { "author_right" => :closed, "finding_right" => :to_fix }[verdict]
  end

  # The opinions in reading order, each with its slot.
  def given = [ first, second ].compact
end
