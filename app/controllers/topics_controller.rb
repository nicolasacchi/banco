# One topic: where it comes from in the programme, the lesson, and the skills to practise (A9.2).
class TopicsController < ApplicationController
  include StudentCourse

  before_action :load_topic

  def show
    @lesson_body = @topic.lesson_revision.body
    @programme = programme_refs(@lesson_body)
    @intro = @topic.topic_revision.body["intro_it"].presence
    @read = course_view.lesson_read?(@topic)
  end

  private

  # The seconda lines the lesson cites (what the teacher's programme says), in the order of the lesson.
  def programme_refs(body)
    seconda = Validation::Rules.get(:course, :seconda_source)
    Array(body["refs"]).select { |r| r["source"] == seconda }.uniq { |r| [ r["line"], r["fragment"] ] }
  end
end
