# The lesson of a topic. The page carries the sections of the approved lesson revision; the solutions of
# the exercises are fetched one by one, on a click, and never are in the page (A9.2, A9.3).
class LessonsController < ApplicationController
  include StudentCourse

  before_action :load_topic
  before_action :no_store, only: :solution

  SECTIONS = %w[why_it idea_it example_it mistakes_it].freeze
  OPENED_THROTTLE = 5.minutes
  AFTER_TRY = %w[book_it summary_it].freeze

  helper LessonPagesHelper

  def show
    revision = @topic.lesson_revision
    @body = revision.body
    @revision = revision
    record_opened(revision)
    return unless @body["schema"] == "banco.lesson/2"

    # A lesson of version 2 (R2): the page gets the student's projection, never the stored body (A2).
    @student_body = student_body(revision)
    @resume = resume_from(revision)
    @safe = !Banco::Lesson2.enabled?
    @preferences = Diagnosis::Preferences.lesson(acting_student)
    render :show2
  end

  # What the student's page may know of this revision: Lessons::StudentBody (a whitelist per block, the options
  # shuffled with the student's seed). It has no fallback on purpose: a stored body is never sent as it is.
  def student_body(revision)
    Lessons::StudentBody.for(revision, seed: preview? ? "preview" : acting_student.key)
  end
  private :student_body

  # { card: the last card seen of this revision or nil, seen: [n, ...] } from the lesson events (R3).
  def resume_from(revision)
    return { card: nil, seen: [] } unless defined?(::Lessons::Progress)

    ::Lessons::Progress.for(acting_student, revision)
  end
  private :resume_from

  def record_opened(revision)
    last = PracticeEvent.where(student: acting_student, kind: "lesson_opened", topic_revision: @topic.topic_revision).order(:id).last
    return if last && last.at > OPENED_THROTTLE.ago

    PracticeEvent.create!(student: acting_student, kind: "lesson_opened", topic_revision: @topic.topic_revision, lesson_revision: revision,
                          payload_json: "{}", at: Time.current, created_at: Time.current)
  end
  private :record_opened

  # POST /topics/:topic/lesson/exercises/:n/solution -> {n, solution_it}
  def solution
    revision = @topic.lesson_revision
    exercise = Array(revision.body["exercises"]).find { |e| e["n"] == params[:n].to_i }
    return render(json: { status: "not_found" }, status: :not_found) unless exercise

    now = Time.current
    PracticeEvent.create!(student: acting_student, kind: "lesson_solution_shown", topic_revision: @topic.topic_revision, lesson_revision: revision,
                          payload_json: { n: exercise["n"] }.to_json, at: now, created_at: now)
    render json: { n: exercise["n"], solution_it: exercise["solution_it"] }
  end
end
