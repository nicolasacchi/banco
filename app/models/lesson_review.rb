# The one review of a lesson revision by an independent session (banco.lesson_review/1).
class LessonReview < ApplicationRecord
  belongs_to :lesson_revision
  belongs_to :agent_session

  def checklist = JSON.parse(checklist_json)
  def recomputed = JSON.parse(recomputed_json)
  def findings = JSON.parse(findings_json)
end
