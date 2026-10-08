# The student's course pages (A9): the acting student (official or trial; the teacher and guests get 403),
# and what the catalog shows this student. A topic or a subject that is not visible is a 404 for this
# student, whatever exists: the official student sees nothing until the teacher releases the course.
module StudentCourse
  extend ActiveSupport::Concern

  included do
    include ActingStudent
    helper_method :course_view, :draft?
  end

  def course_view = @course_view ||= Course::StudentView.new(acting_student)

  # Not approved yet: only a trial student ever sees such a topic.
  def draft? = @topic && !@topic.approved

  private

  # Sets @subject_view and @topic from params[:topic]; 404 when this student cannot see it.
  def load_topic
    @subject_view, @topic = course_view.find_topic(params[:topic])
    head(:not_found) unless @topic
  end

  # The JSON endpoints refuse once the subject is no longer visible (a withdrawn release): the same answer.
  def subject_visible?(subject_key) = course_view.subject(subject_key).present?

  def json_not_found = render(json: { status: "not_found" }, status: :not_found)
end
