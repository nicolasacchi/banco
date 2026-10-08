# The author's answer to a finding (D-220), append-only. It never disposes of the finding:
# the teacher decides (dispose_finding). The latest response of a finding counts.
class FindingResponse < ApplicationRecord
  STANCES = %w[item_right fixed].freeze
  MAX_NOTE = 700

  belongs_to :review_finding
  belongs_to :agent_session
  belongs_to :item_revision, optional: true

  # {finding id => its latest response}.
  def self.latest_for(finding_ids)
    where(review_finding_id: finding_ids).order(:id).includes(:item_revision, :agent_session).index_by(&:review_finding_id)
  end

  def to_h
    { id: id, finding_id: review_finding_id, stance: stance, revision_id: item_revision_id, seq: item_revision&.seq, note_it: note_it }.compact
  end
end
