# "Non ho capito": one optional line that the teacher reads. No model answers (firm rule 1); nothing is
# graded or derived from it. Idempotent on client_question_id.
class QuestionsController < ApplicationController
  include StudentCourse

  before_action { response.headers["Cache-Control"] = "no-store" }

  MAX_LENGTH = 300
  ID_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/

  class Refused < StandardError
    attr_reader :http

    def initialize(http) = (@http = http; super())
  end

  rescue_from(Refused) { |e| render json: { status: e.http == 404 ? "not_found" : "invalid" }, status: e.http }

  def create
    client_id = params[:client_question_id].to_s
    raise Refused, 422 unless client_id.match?(ID_FORMAT)

    existing = StudentQuestion.find_by(client_question_id: client_id)
    if existing
      raise Refused, 404 unless existing.student_id == acting_student.id

      return done
    end
    _, @topic = course_view.find_topic(params[:topic])
    raise Refused, 404 unless @topic

    begin
      StudentQuestion.create!(row(client_id))
    rescue ActiveRecord::RecordNotUnique
      # the same question arrived twice at once
    end
    done
  end

  private

  def row(client_id)
    topic_revision = @topic.topic_revision
    section = params[:section].presence&.to_s
    exercise = params[:exercise].presence&.to_s
    text = params[:text_it].to_s.strip.gsub(/\s+/, " ")
    raise Refused, 422 if section && !StudentQuestion::SECTIONS.include?(section)
    raise Refused, 422 if exercise && !exercise.match?(/\A([1-9]|1[0-2])\z/)
    raise Refused, 422 if text.length > MAX_LENGTH

    { student: acting_student, client_question_id: client_id, topic_revision: topic_revision, lesson_revision: lesson_revision(topic_revision),
      practice_serve: serve, section: section, exercise: exercise&.to_i, text_it: text.presence, created_at: Time.current }
  end

  # The lesson revision of the page the student read: the topic's own, or none.
  def lesson_revision(topic_revision)
    given = params[:lesson_revision_id].presence
    return nil unless given
    raise Refused, 404 unless given.to_s == topic_revision.lesson_revision_id.to_s

    topic_revision.lesson_revision
  end

  # A serve of this student on one of the topic's skills, or none.
  def serve
    return nil if params[:serve_id].blank?

    found = PracticeServe.find_by(id: params[:serve_id].to_s.to_i, student_id: acting_student.id)
    raise Refused, 404 unless found && @topic.skills.include?(found.skill_key)

    found
  end

  def done = render(json: { ok: true, message_it: I18n.t("question.sent") })
end
