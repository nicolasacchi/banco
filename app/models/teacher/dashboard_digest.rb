module Teacher
  # A cheap fingerprint of everything the dashboard shows, from the watermarks of the ledger: the row count and
  # the largest id of each table that can change a number on the page. The ledger is append-only (firm rule 4),
  # so a change anywhere is a new row with a larger id: MAX(id) alone is enough and is an index-only read. The heartbeat of the teacher's own minutes is left out: it would change
  # the digest every minute. One query.
  module DashboardDigest
    TABLES = %w[decisions item_revisions item_validations item_reviews blind_solves review_findings finding_responses
                finding_assessments grade_proposals blueprint_revisions skill_graph_revisions course_revisions topic_revisions
                lesson_revisions lesson_reviews diagnosis_runs diagnosis_events attempts attempt_gradings practice_serves
                practice_attempts practice_gradings practice_events student_questions students].freeze
    APP_EVENTS_WHERE = "kind <> '#{Minutes::KIND}'".freeze

    TTL = Rails.env.test? ? 0 : 5 # seconds: several open tabs share one computation
    LOCK = Mutex.new
    @memo = nil

    module_function

    def current
      Digest::SHA256.hexdigest(watermarks.map { |name, max| "#{name}:#{max}" }.join(";"))[0, 16]
    end

    # For the polling endpoint: the same value, at most TTL seconds old.
    def cached
      LOCK.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @memo = [ now, current ] if @memo.nil? || now - @memo[0] >= TTL
        @memo[1]
      end
    end

    def reset_cache!
      LOCK.synchronize { @memo = nil }
    end

    # [[table, max id]]
    def watermarks
      parts = TABLES.map { |t| "SELECT '#{t}' AS name, MAX(id) AS m FROM #{t}" }
      parts << "SELECT 'app_events', MAX(id) FROM app_events WHERE #{APP_EVENTS_WHERE}"
      ApplicationRecord.connection.select_rows(parts.join(" UNION ALL "))
    end
  end
end
