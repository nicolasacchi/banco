module Teacher
  # The course map of a subject: topics in order with their stage, the new skills with the programme text,
  # and the release to the official student (a decision posted to Teacher::DecisionsController).
  class CoursesController < Teacher::BaseController
    def show
      subject! or return
      @unit = "#{@subject.key}:course"
      @review = Teacher::CourseReview.new(@subject)
    end
  end
end
