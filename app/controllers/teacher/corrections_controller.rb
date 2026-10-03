module Teacher
  # The evening screen: short answers and uncertain verdicts that wait for the teacher.
  class CorrectionsController < Teacher::BaseController
    def show
      @unit = "evening"
      @corrections = Teacher::Corrections.call
    end
  end
end
