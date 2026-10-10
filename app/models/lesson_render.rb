# One render check of a lesson/2 revision (D-249, A12.2): append-only. Rows are made by RenderLessonRevisionJob
# through Validation::LessonRenderRunner. A revision can have several (an `error` attempt, then a verdict);
# the latest row is what the gate and the pages read.
class LessonRender < ApplicationRecord
  belongs_to :lesson_revision

  def result = JSON.parse(result_json)
  def shots = JSON.parse(shots_json)
  def errors_list = Array(result["errors"])
  def passed? = status == "passed"

  # The latest verdict row of a revision (error rows are attempts, not verdicts), or nil.
  def self.verdict_for(revision)
    where(lesson_revision_id: revision.id, status: %w[passed failed]).order(:id).last
  end

  def self.latest_for(revision) = where(lesson_revision_id: revision.id).order(:id).last
end
