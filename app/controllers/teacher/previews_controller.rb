module Teacher
  # "Prova come S": the teacher plays a test as the student sees it. The answers
  # are attempts in the context teacher_preview of a preview student, kept apart
  # from the student's own log. The test itself runs in SittingsController.
  class PreviewsController < ApplicationController
    include ActingStudent

    def index
      @subjects = Subject.order(:position).select { |s| Diagnosis::Conductor.latest_blueprint(s) }
    end
  end
end
