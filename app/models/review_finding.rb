# A finding of an expert review or of a blind solve. Append-only. Its disposition is
# a decision of the teacher (kind dispose_finding, payload {finding_id, disposition,
# reason_it}); the latest one counts.
class ReviewFinding < ApplicationRecord
  include Searchable

  SEVERITIES = %w[blocker major minor].freeze
  DISPOSITIONS = %w[fix_requested dismissed].freeze

  belongs_to :item_revision
  belongs_to :item_review, optional: true
  belongs_to :blind_solve, optional: true
  has_many :responses, class_name: "FindingResponse"
  has_many :assessments, class_name: "FindingAssessment"

  scope :must_be_disposed, -> { where(severity: %w[blocker major]) }

  def self.dispositions
    Decision.where(kind: "dispose_finding").order(:id).each_with_object({}) do |d, map|
      payload = JSON.parse(d.payload_json)
      map[payload["finding_id"].to_i] = payload["disposition"] if DISPOSITIONS.include?(payload["disposition"])
    end
  end

  def disposition = self.class.dispositions[id]

  def disposed? = !disposition.nil?

  def latest_response = responses.max_by(&:id)

  def opinion = FindingOpinion.new(assessments.includes(agent_session: :corrections).to_a)

  # True when the opinion is still empty and the arbiter's model is the one that raised this finding: the arbiter
  # on that model is refused (E-PROVIDER-NOT-ALLOWED), so the opinion stays empty (D-222). Read with the true
  # models (D-316).
  def opinion_slot_blocked?(op = opinion)
    return false unless op.first.nil?

    raiser = AgentSession.find_by(id: raised_by_session_id)
    !raiser.nil? && Providers.model_key(raiser.model) == Providers.first_opinion_model
  end

  # The agent session that raised the finding: the reviewer or the blind solver.
  def raised_by_session_id = item_review&.agent_session_id || blind_solve&.agent_session_id

  def to_h
    { id: id, source: source, severity: severity, code: code, instance: instance, field: field, quote: quote,
      problem_it: problem_it, fix_it: fix_it, disposition: disposition }.compact
  end
end
