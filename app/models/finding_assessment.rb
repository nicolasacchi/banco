# The third reviewer's opinion on a finding (D-222), append-only. The arbiter says who is right:
# the author (the item is right), the finding (the item needs a change) or neither clearly. Only the
# first opinion (claude-opus-5-5, config/banco/providers.yml) counts since D-316 dropped the second one:
# the latest counting assessment is the effective one, and an old second opinion is history. For a
# blocker or major finding an opinion never disposes of anything: the teacher decides
# (dispose_finding), possibly by following a clear opinion. A minor finding is closed or
# marked to fix by the opinion alone (D-239, FindingOpinion), still without a decision row.
class FindingAssessment < ApplicationRecord
  VERDICTS = %w[author_right finding_right unclear].freeze
  MAX_NOTE = 500
  # verdict => the disposition the teacher's click records when a clear opinion is followed.
  FOLLOW = { "author_right" => "dismissed", "finding_right" => "fix_requested" }.freeze

  belongs_to :review_finding
  belongs_to :agent_session

  validates :verdict, inclusion: { in: VERDICTS }

  # :first for the arbiter's model, nil for any other (an old second opinion, D-316).
  def slot = Providers.opinion_slot(agent_session.model)

  # The session that raised the finding (the reviewer or the blind solver).
  def raiser_session
    id = review_finding.raised_by_session_id
    id && AgentSession.find_by(id: id)
  end

  # True when the assessment counts (D-316): the arbiter's model, and a model other than the one that raised the
  # finding, both read with the true models (different_model_from_raiser, derived at read time).
  def counts? = ignored_reason.nil?

  # Why it does not count, or nil: :second_opinion (an old second opinion, no longer asked) or
  # :same_model_as_raiser.
  def ignored_reason
    return :second_opinion if slot.nil?
    return :same_model_as_raiser unless Providers.different_from_raiser?(agent_session, raiser_session)

    nil
  end

  # {finding id => FindingOpinion}, one query for the assessments.
  def self.opinions_for(finding_ids)
    rows = where(review_finding_id: finding_ids).order(:id).includes(agent_session: :corrections).group_by(&:review_finding_id)
    finding_ids.to_h { |id| [ id, FindingOpinion.new(rows[id] || []) ] }
  end

  def to_h
    { id: id, finding_id: review_finding_id, opinion: slot, verdict: verdict, model: agent_session.model, note_it: note_it, counts: counts? }
  end
end
