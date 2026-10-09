# The third reviewer's opinion on a finding (D-222), append-only. The arbiter says who is right:
# the author (the item is right), the finding (the item needs a change) or neither clearly. Two
# opinions count, the first (claude-opus-5-5) and the second (claude-haiku-4-5-20251001), see
# config/banco/providers.yml; the latest assessment of each model is its effective one. For a
# blocker or major finding an opinion never disposes of anything: the teacher decides
# (dispose_finding), possibly by following a clear opinion. A minor finding is closed or
# marked to fix by the first opinion alone (D-239, FindingOpinion), still without a decision row.
class FindingAssessment < ApplicationRecord
  VERDICTS = %w[author_right finding_right unclear].freeze
  MAX_NOTE = 500
  # verdict => the disposition the teacher's click records when a clear opinion is followed.
  FOLLOW = { "author_right" => "dismissed", "finding_right" => "fix_requested" }.freeze

  belongs_to :review_finding
  belongs_to :agent_session

  validates :verdict, inclusion: { in: VERDICTS }

  # :first, :second, or nil for a model that gives no opinion.
  def slot = Providers.opinion_slot(agent_session.model)

  # {finding id => FindingOpinion}, one query for the assessments.
  def self.opinions_for(finding_ids)
    rows = where(review_finding_id: finding_ids).order(:id).includes(:agent_session).group_by(&:review_finding_id)
    finding_ids.to_h { |id| [ id, FindingOpinion.new(rows[id] || []) ] }
  end

  def to_h
    { id: id, finding_id: review_finding_id, opinion: slot, verdict: verdict, model: agent_session.model, note_it: note_it }
  end
end
