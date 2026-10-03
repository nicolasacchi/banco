module Teacher
  # The skill graph of a subject, for approval (C-04).
  class GraphsController < Teacher::BaseController
    def show
      subject! or return
      @unit = "#{@subject.key}:graph"
      @review = Teacher::GraphReview.new(@subject)
    end
  end
end
