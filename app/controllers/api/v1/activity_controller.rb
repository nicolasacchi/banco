module Api
  module V1
    # Who did what (D-334): the teachers' and bots' actions in one newest-first feed, so a teacher or a bot sees what the
    # others did on the same students. Read-only (SELECTs on the ledgers through Activity); bot_read and teacher tokens
    # only, since the feed names the logins and the tokens of the others.
    class ActivityController < Api::BaseController
      before_action { require_token_roles("bot_read", "teacher") }

      # GET /api/v1/activity[?since=ISO8601][&actor=LOGIN][&limit=N]: {rows: [...], actors: [logins of the rows]}.
      # since: a date or a moment (rows at or after it); actor: the login of the rows; limit: 1..200 (default 50).
      def show
        since = parse_since
        return if since == false # answered 422
        limit = params[:limit].presence ? Integer(params[:limit].to_s, 10, exception: false) : Activity::DEFAULT_LIMIT
        return refuse("E-FILES", "limit", "limit is a whole number from 1 to #{Activity::MAX_LIMIT}", "banco activity --limit 50", 422) unless limit&.positive?

        rows = Activity.recent(since: since, actor: params[:actor].presence, limit: limit)
        render json: { rows: rows, actors: rows.filter_map { |r| r.dig("actor", "login") }.uniq.sort }
      end

      private

      # nil without the parameter; a Time for an ISO 8601 moment or a date (its first moment, UTC); answers 422 and returns
      # false for anything else.
      def parse_since
        raw = params[:since].to_s.strip
        return nil if raw.empty?

        raw.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? Date.iso8601(raw).in_time_zone("UTC") : Time.iso8601(raw)
      rescue ArgumentError
        refuse("E-FILES", "since", "since is an ISO 8601 date or moment: 2026-11-15 or 2026-11-15T09:00:00Z", "banco activity --since 2026-11-15", 422)
        false
      end
    end
  end
end
