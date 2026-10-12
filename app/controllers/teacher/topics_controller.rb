module Teacher
  # One topic for approval: the lesson, its review, the samples of every pinned item. Opening the page of the
  # latest topic revision is what the approval gate calls "read the page" (teacher_viewed_topic); a guest and
  # the student's computer only read.
  class TopicsController < Teacher::BaseController
    # The box of a lesson/2 holds the free pages' frames (D-281, SPEC B4): this page and the student's lesson page alone may frame the pages origin.
    content_security_policy { |policy| policy.frame_src Pages.origin }

    def show
      subject! or return
      @unit = "#{@subject.key}:topic"
      @review = Teacher::TopicReview.new(@subject, params[:topic].to_s)
      return head(:not_found) unless @review.present?

      record_topic_view(@review.latest) if @review.latest
    end

    private

    def record_topic_view(revision)
      return if request.cookies[DecisionRecorder::DEVICE_COOKIE].present? || !current_identity&.teacher?
      return if Approval::TopicGate.viewed?(revision)

      AppEvent.create!(kind: Approval::TopicGate::VIEW_KIND, payload_json: { topic_revision_id: revision.id }.to_json)
    end
  end
end
