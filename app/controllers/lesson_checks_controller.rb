# The grading of an inline question of a lesson/2 (A9): POST /topics/:topic/lesson/checks/:card/:block[/:step]
# (the blank of a faded example) or .../checks/:card/:block/ex/:n[/:part] (a check of an exercise of "Prova tu"),
# with {response, try, client_event_id}. The answer is {verdict: right|wrong|invalid, message_it?, explain_it?, try,
# steps?, result_it?, states?}. The server grades with the shared graders (Lessons::Checks) and records a
# lesson_events row; it never writes to the practice ledger. response is student data: at most 200 characters,
# filtered from the logs, shown to the teacher only.
class LessonChecksController < ApplicationController
  include StudentCourse

  before_action :load_topic_for_json
  before_action { response.headers["Cache-Control"] = "no-store" }

  def create
    revision = @topic.lesson_revision
    return json_not_found unless revision.lesson2?

    locator = { card: params[:card].to_i, block: params[:block].to_i, step: params[:step]&.to_i, ex: params[:n]&.to_i, part: params[:part]&.to_i }
    answer = Lessons::CheckAnswer.new(revision, student_key: acting_student.key, student: acting_student, topic_revision: @topic.topic_revision)
    reply = answer.call(locator, response_value, client_event_id: params[:client_event_id].presence)
    render json: reply.body, status: reply.status
  end

  private

  def load_topic_for_json
    @subject_view, @topic = course_view.find_topic(params[:topic])
    json_not_found unless @topic
  end

  # What the browser sent, as plain JSON data (a string, a hash or an array of strings).
  def response_value = JSON.parse(request.request_parameters["response"].to_json)
end
