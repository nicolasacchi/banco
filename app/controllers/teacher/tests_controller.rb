module Teacher
  # The entry test of a subject, for approval: the overview and one screen per skill.
  class TestsController < Teacher::BaseController
    def show
      subject! or return
      @unit = "#{@subject.key}:test"
      @review = Teacher::TestReview.new(@subject)
    end

    def skill
      subject! or return
      @unit = "#{@subject.key}:test"
      @review = Teacher::TestReview.new(@subject)
      @row = @review.present? && @review.skill_row(params[:skill].to_s) or return head(:not_found)

      record_views(@row.item_ids)
      @cards = @review.cards(@row.skill)
      rows = @review.skill_rows
      at = rows.index(@row)
      @previous = at.to_i.positive? ? rows[at - 1] : nil
      @next = rows[at + 1]
    end
  end
end
