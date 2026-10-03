# An agent's proposed grade for a short answer (B-06). Append-only and never
# binding: it counts only after a decision of the teacher (kind confirm_grade,
# payload {grade_proposal_id}) confirms it in the browser.
class GradeProposal < ApplicationRecord
  belongs_to :attempt
  belongs_to :agent_session

  def points = JSON.parse(points_json)

  def confirmed?
    Decision.where(kind: "confirm_grade").any? { |d| JSON.parse(d.payload_json)["grade_proposal_id"].to_i == id }
  end
end
