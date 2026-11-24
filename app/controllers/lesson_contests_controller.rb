# «Per me va bene così» on a check of a lesson/2 (D-396): POST /topics/:topic/lesson/contest with {card, block, step?, ex?, part?}, the place of the check as
# LessonChecksController has it. The student's latest wrong answer to that check goes to the teacher through a lesson event (Lessons::CheckContest),
# which she reads in «Contestazioni»; no comment is written (D-400). The answer is {status: "contested", explain_it?, model_it?, steps?...} | {status: "not_contestable"} (no try yet, or the last one was
# right) | {status: "not_found"}. Students only, official and trial; the teacher, a guest and the teacher's preview get 403 (the preview has no route: it never
# contests, D-309).
class LessonContestsController < ApplicationController
  include StudentCourse

  before_action :load_topic_for_json
  before_action { response.headers["Cache-Control"] = "no-store" }

  def create
    revision = @topic.lesson_revision
    return json_not_found unless revision.lesson2?

    locator = { card: whole(:card), block: whole(:block), step: whole(:step), ex: whole(:ex), part: whole(:part) }.compact
    return json_not_found unless locator[:card] && locator[:block]

    reply = Lessons::CheckContest.new(revision, student: acting_student, topic_revision: @topic.topic_revision).call(locator)
    render json: reply.body, status: reply.status
  end

  private

  def load_topic_for_json
    @subject_view, @topic = course_view.find_topic(params[:topic])
    json_not_found unless @topic
  end

  # A positive whole number as JSON sent it, or nil.
  def whole(name)
    value = request.request_parameters[name.to_s]
    value.is_a?(Integer) && value.positive? ? value : nil
  end
end
