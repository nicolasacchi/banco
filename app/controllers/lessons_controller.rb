# The lesson of a topic. The page carries the sections of the approved lesson revision; the solutions of
# the exercises are fetched one by one, on a click, and never are in the page (A9.2, A9.3).
class LessonsController < ApplicationController
  include StudentCourse

  before_action :load_topic
  before_action :no_store, only: :solution

  SECTIONS = %w[why_it idea_it example_it mistakes_it].freeze
  AFTER_TRY = %w[book_it summary_it].freeze

  def show
    revision = @topic.lesson_revision
    @body = revision.body
    @revision = revision
    PracticeEvent.create!(student: acting_student, kind: "lesson_opened", topic_revision: @topic.topic_revision, lesson_revision: revision,
                          payload_json: "{}", at: Time.current, created_at: Time.current)
  end

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
