# «Scrivi tu» (D-407), the student's side: POST /topics/:topic/writings sends a text he wrote himself on a topic that pins a writing task (idempotent on
# client_writing_id, checked against what this student is shown, Writings::Intake). Students only, official and trial; the teacher's preview posts to the same
# route and writes only the preview student's row; a guest and nobody get 403 from ActingStudent. A text changes no grade, no attempt, no skill state and nothing
# of the practice; the teacher corrects it with a decision (Teacher::DecisionsController) and no model answers (firm rule 1).
class WritingsController < ApplicationController
  include StudentCourse

  # JSON for the box: "recorded" (also a repeat) with the text as stored, or "invalid" (422: the box says why and keeps the words).
  def create
    result = Writings::Intake.call(student: acting_student, course_view: course_view, topic: params[:topic], params: params)
    if result.status == :recorded
      submission = result.submission
      render json: { status: "recorded", submission: { id: submission.id, item_revision_id: submission.item_revision_id, text: submission.text, word_count: submission.word_count } }
    else
      render json: { status: "invalid", error: result.error.to_s }, status: :unprocessable_entity
    end
  end
end
