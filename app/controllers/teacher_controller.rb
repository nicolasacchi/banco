# The teacher's first page: the subjects, what waits, the minutes spent (C-04). The other
# pages are in app/controllers/teacher/.
class TeacherController < ApplicationController
  layout "teacher"
  before_action :require_teacher!

  def show
    @unit = "home"
    @home = Teacher::Home.new
  end
end
