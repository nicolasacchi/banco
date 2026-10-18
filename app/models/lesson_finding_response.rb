# The author's answer to a finding of a lesson review (D-313), append-only: the lesson twin of FindingResponse
# (D-220). The finding is the finding_n-th (from 1) of the review's findings_json. It never disposes of the
# finding: the teacher decides, when she approves the topic or sends the lesson back. The latest response counts.
class LessonFindingResponse < ApplicationRecord
  STANCES = %w[lesson_right fixed].freeze
  MAX_NOTE = FindingResponse::MAX_NOTE

  belongs_to :lesson_review
  belongs_to :agent_session
  belongs_to :lesson_revision, optional: true

  def finding_id = LessonFindings.id_for(lesson_review_id, finding_n)

  # {finding id ("L12-3") => its latest response} for the given lesson review ids.
  def self.latest_for(review_ids)
    where(lesson_review_id: review_ids).order(:id).includes(:lesson_revision).index_by(&:finding_id)
  end

  def to_h
    { id: id, finding_id: finding_id, stance: stance, revision_id: lesson_revision_id, seq: lesson_revision&.seq, note_it: note_it }.compact
  end
end
