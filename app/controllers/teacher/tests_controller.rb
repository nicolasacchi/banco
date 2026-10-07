module Teacher
  # The entry test of a subject, for approval: the overview and one screen per skill.
  class TestsController < Teacher::BaseController
    def show
      subject! or return
      @unit = "#{@subject.key}:test"
      @review = Teacher::TestReview.new(@subject)
    end

    # Every question of the test on one page, read-only. Opening it counts as opening every
    # pinned item (the gate's "opened" condition), because all of them are shown.
    def all
      subject! or return
      @unit = "#{@subject.key}:test"
      @review = Teacher::TestReview.new(@subject)
      return head(:not_found) unless @review.present?

      @all = Teacher::AllQuestions.new(@review)
      record_views(@all.pinned_ids & ItemRevision.where(id: @all.pinned_ids).pluck(:id))
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
