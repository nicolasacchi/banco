module Teacher
  # «Contestazioni» (D-368): where the grader may be wrong, before the student says so. Read-only: the exercises with their tries, the rate of tries
  # that were not right and of manual corrections, the ones «da controllare», and the not-right tries with the signals that make them doubtful
  # (Teacher::GradingReview). It writes nothing, decides nothing and has no table; the same rows come over the API (Api::V1::GradingReviewController).
  # A guest, and so a view link, sees the numbers but never what the student typed.
  class GradingController < Teacher::BaseController
    def show
      @student = viewed_student
      @filters = filters
      @review = Teacher::GradingReview.new(student: @student, since: since_time, subject: @filters[:subject]) if @student
      @subjects = Subject.order(:position)
      @subject_names = @subjects.to_h { |subject| [ subject.key, subject.name_it ] }
    end

    private

    # The filters of the query that mean something; any other value is left out (a page, not an API: no error for a stale link).
    def filters = { subject: params[:subject].presence_in(Subject.pluck(:key)), since: day(params[:since]) }.compact

    # A date as 2026-11-16, or nil.
    def day(text)
      text.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.iso8601(text.to_s).iso8601 : nil
    rescue Date::Error
      nil
    end

    def since_time = @filters[:since] ? Date.iso8601(@filters[:since]).in_time_zone("UTC") : nil
  end
end
