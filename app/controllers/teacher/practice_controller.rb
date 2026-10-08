module Teacher
  # What a student did in practice, for the teacher (A10, D-217): ?student=KEY picks a trial student.
  class PracticeController < Teacher::BaseController
    def show
      subject! or return
      @unit = "#{@subject.key}:practice"
      @progress = Teacher::PracticeProgress.new(@subject, viewed_student)
    end

    def skill
      subject! or return
      @unit = "#{@subject.key}:practice"
      @progress = Teacher::PracticeProgress.new(@subject, viewed_student)
      @skill = params[:skill].to_s
      return head(:not_found) unless @progress.present? && @progress.skill_keys.include?(@skill)

      @row = @progress.skill_row(@skill)
      @trail = @progress.trail(@skill)
    end
  end
end
