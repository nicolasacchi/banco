# The teacher's first page: the subjects, what waits, the minutes spent (C-04). The other
# pages are in app/controllers/teacher/.
class TeacherController < ApplicationController
  layout "teacher"
  include ViewedStudent
  before_action :require_reader!

  def show
    @unit = "home"
    @home = Teacher::Home.new(student: viewed_student)
  end
end
