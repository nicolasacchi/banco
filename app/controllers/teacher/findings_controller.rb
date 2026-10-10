module Teacher
  # All the findings the teacher has to decide, across subjects: the dashboard's lines, on a page of their own
  # (D-243). Links open in the same tab here.
  class FindingsController < Teacher::BaseController
    def show
      @same_tab = true
      @todos = Dashboard.new(student: viewed_student).todos.select { |t| t.kind == :findings }
    end
  end
end
