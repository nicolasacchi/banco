# «Ti è piaciuto?» (D-365), the student's side: POST /ratings writes one rating of an exercise that is over or of the lesson he is reading
# (idempotent on client_rating_id, checked against what this student was shown). Students only, official and trial: the teacher, a guest and
# nobody get 403 from ActingStudent, and the teacher's preview has no route (it never writes, and its pages draw no box). A rating changes no
# grade, no attempt, no engine path and nothing of the practice ledger; the teacher only reads it. No model answers (firm rule 1).
class RatingsController < ApplicationController
  include StudentCourse

  # JSON for the box: "recorded" (also a repeat) with the rating as stored, or "invalid" (422, final: the box says so and keeps the words).
  def create
    result = Ratings::Intake.call(student: acting_student, course_view: course_view, params: params, language: I18n.locale)
    if result.status == :recorded
      rating = result.rating
      render json: { status: "recorded", rating: { stars: rating.stars, text_it: rating.text_it } }
    else
      render json: { status: "invalid", error: result.error.to_s }, status: :unprocessable_entity
    end
  end
end
