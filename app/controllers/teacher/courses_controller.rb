module Teacher
  # The course map of a subject as the path of the subject (D-241): topics in order as numbered steps with one plain
  # state each, the new skills with the programme text, and the release to the official student (a decision posted
  # to Teacher::DecisionsController). `?only=ready` keeps the topics that wait for the teacher.
  class CoursesController < Teacher::BaseController
    def show
      subject! or return
      @unit = "#{@subject.key}:course"
      @review = Teacher::CourseReview.new(@subject)
      @only_ready = params[:only] == "ready"
    end
  end
end
