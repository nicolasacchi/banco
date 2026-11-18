module Teacher
  # «Valutazioni» (D-365): what the student thinks of the exercises and lessons, 1 to 5 stars and a comment, newest first, filtered by subject,
  # topic and kind, with the average and the count of every target. Read-only for the teacher and the guest (and a view link): the teacher only
  # reads it, there is no reply, no thread and no decision, and nothing here touches an engine, a gate or a grade (the same rows come over the API
  # to a bot_read or teacher token, Api::V1::RatingsController). A trial student's ratings are listed and marked; they never count in an average.
  class RatingsController < Teacher::BaseController
    LIMIT = 200

    def show
      @filters = filters
      @list = Ratings::List.new(**@filters)
      @rows = @list.rows(limit: LIMIT)
      @total = @list.total
      @targets = @list.targets
      @summary = @list.summary
      @subjects = Subject.order(:position)
      @topics = Lesson.where(id: TopicRevision.where(id: Rating.select(:topic_revision_id)).select(:lesson_id)).order(:key).pluck(:key)
    end

    private

    # The filters of the query that mean something; any other value is left out (a page, not an API: no error for a stale link).
    def filters
      {
        subject: params[:subject].presence_in(Subject.pluck(:key)),
        topic: params[:topic].to_s.match?(Teacher::Refs::KEY) ? params[:topic].to_s : nil,
        kind: params[:kind].presence_in(Rating::KINDS),
        target: params[:target].to_s.match?(Teacher::Refs::KEY) ? params[:target].to_s : nil
      }.compact
    end
  end
end
