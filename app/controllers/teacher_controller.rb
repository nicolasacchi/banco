# The teacher's first page, the dashboard (C-04, D-242): what to do now, one row per subject. The other
# pages are in app/controllers/teacher/.
class TeacherController < ApplicationController
  layout "teacher"
  include ViewedStudent
  before_action :require_reader!

  def show
    @unit = "home"
    @digest = Teacher::DashboardDigest.current # before the page is read: a change in between shows at the next poll
    @dashboard = Teacher::Dashboard.new(student: viewed_student)
  end
end
