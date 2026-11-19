module Teacher
  # «Novità» (D-375), the teacher's side: everything that changed, the entries for the student and for the teacher, and the topics approved again
  # with the teacher's reason, the old and the new revision and the link to the topic page. Read-only for the teacher and the guest (and a view
  # link); nothing is written. The same rows come over the API (Api::V1::ChangelogController).
  class ChangelogController < Teacher::BaseController
    def show
      @filters = filters
      feed = Changelog::Feed.teacher(since: @filters[:since])
      @entries = @filters[:audience] ? feed.entries.select { |e| e.audience.include?(@filters[:audience]) } : feed.entries
      @updates = feed.updates
    end

    private

    # The filters that mean something; any other value is left out (a page, not an API: no error for a stale link).
    def filters = { audience: params[:audience].presence_in(Changelog::Entries::AUDIENCES), since: day(params[:since]) }.compact

    # A date as 2026-11-16, or nil.
    def day(text)
      text.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.iso8601(text.to_s) : nil
    rescue Date::Error
      nil
    end
  end
end
