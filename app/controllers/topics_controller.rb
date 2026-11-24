# One topic: where it comes from in the programme, the lesson, and the skills to practise (A9.2).
class TopicsController < ApplicationController
  include StudentCourse

  before_action :load_topic

  def show
    @lesson_body = @topic.lesson_revision.body
    @programme = programme_refs(@lesson_body)
    body = @topic.topic_revision.body
    # D-402: the intro in the language the subject teaches when the revision has the pair, with its Italian to offer; else the Italian one.
    target = @topic.lang && body["intro_#{@topic.lang}"].presence
    @intro = target || body["intro_it"].presence
    @intro_tr = body["intro_it"].presence if target
    @read = course_view.lesson_read?(@topic)
  end

  private

  # The programme lines the lesson cites (what the teacher's programme says), in the order of the lesson: the seconda source, or the
  # official programme for a subject the seconda source does not cover (D-344).
  def programme_refs(body)
    source = Validation::Rules.programme_source(@subject_view.subject.key)
    Array(body["refs"]).select { |r| r["source"] == source }.uniq { |r| [ r["line"], r["fragment"] ] }
  end
end
