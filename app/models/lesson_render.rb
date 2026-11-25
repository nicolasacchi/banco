# One render check of a lesson/2 revision (D-249, A12.2): append-only. Rows are made by RenderLessonRevisionJob
# through Validation::LessonRenderRunner. A revision can have several (an `error` attempt, then a verdict);
# the latest row is what the gate and the pages read.
class LessonRender < ApplicationRecord
  belongs_to :lesson_revision

  def result = JSON.parse(result_json)
  def shots = JSON.parse(shots_json)
  # The segments the host found the lesson saying aloud ([{"lang", "text", "voice"}], D-359), or nil on a row made before they were collected.
  def segments = segments_json && JSON.parse(segments_json)
  def errors_list = Array(result["errors"])
  def passed? = status == "passed"

  # Failed only because time ran out (every error is E-LESSON-RENDER «timeout:»): the server's limit, not the author's data, so the verdict is not final
  # (RenderLessonRevisionJob draws it again, and the author may ask for it: `banco lesson render REV --retry`).
  def timeout_only?
    status == "failed" && errors_list.any? && errors_list.all? { |e| e["code"] == "E-LESSON-RENDER" && e["message"].to_s.start_with?("timeout:") }
  end

  # How many verdicts at the end of the revision's rows are timeout-only failures (the job stops asking again after RenderLessonRevisionJob::TIMEOUT_DRAWS).
  def self.timeout_streak(revision)
    where(lesson_revision_id: revision.id, status: %w[passed failed]).order(:id).to_a.reverse.take_while(&:timeout_only?).size
  end

  # The latest verdict row of a revision (error rows are attempts, not verdicts), or nil.
  def self.verdict_for(revision)
    where(lesson_revision_id: revision.id, status: %w[passed failed]).order(:id).last
  end

  def self.latest_for(revision) = where(lesson_revision_id: revision.id).order(:id).last
end
