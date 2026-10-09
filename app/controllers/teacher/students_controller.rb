module Teacher
  # The students (the official one and the trial ones, D-217) with their report and practice links per subject.
  class StudentsController < Teacher::BaseController
    def show
      @students = Student.real
      @subjects = Subject.order(:position).to_a
    end
  end
end
