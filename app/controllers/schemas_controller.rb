# «I miei schemi» (D-372): the schema of a topic, the summary card of the lesson revision the student is shown, drawn by the lesson/2
# renderer; and the list of the schemas he has opened, with a count of the ones still closed. A schema opens when its topic is done
# (Course::Schemas); before that the page and the list say so and carry none of its content. Read-only: nothing is recorded, and the
# lesson is not changed. The teacher's preview opens every schema (it has no progress to wait for).
class SchemasController < ApplicationController
  include StudentCourse

  before_action :load_topic, only: :show

  helper LessonPagesHelper

  def index
    @schemas = schemas
    @closed = course_view.subjects.empty?
  end

  def show
    @unlocked = schemas.unlocked?(@topic)
    return unless @unlocked

    @revision = @topic.lesson_revision
    body = @revision.body
    if body["schema"] == "banco.lesson/2"
      # The same projection as the lesson's page, reduced to its summary card: no answer is in it.
      @student_body = Lessons::StudentBody.schema(body, revision_id: @revision.id, seed: acting_student.key) or return page_not_found
      @safe = !Banco::Lesson2.enabled?
      @preferences = Diagnosis::Preferences.lesson(acting_student)
    else
      @summary_it = body.dig("sections", "summary_it").presence or return page_not_found
    end
  end

  private

  def schemas = @schemas ||= Course::Schemas.new(course_view, open_all: preview?)
end
