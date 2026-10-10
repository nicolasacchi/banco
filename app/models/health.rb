# What `banco health --json` and bin/preflight report: whether this installation can
# serve the student and the agents right now. Read-only except for one insert that
# is rolled back (the database really is writable).
#
#   Health.check  # => {ok: true, db: "ok", queue: "ok", grader: "ok", chrome: "ok", ...}
#
# Each part says "ok" or what is wrong. A part that does not apply here (no
# Solid Queue outside production, no sidecar Chrome in development, no backup
# directory configured) says "not_applicable" or "not_configured" and does not
# turn ok false. The decisions flag is reported and never gates: it is the
# operator's switch, off until the proofs are done (D-08).
module Health
  DISK_MIN_FREE_MB = 1024
  BACKUP_MAX_AGE_HOURS = 36
  QUEUE_HEARTBEAT_SECONDS = 120
  EGRESS_PROBE = "http://1.1.1.1/".freeze

  class << self
    # chrome: false skips the browser (the cheap parts only).
    def check(chrome: true, chrome_wait: 30)
      parts = {
        db: db, queue: queue, grader: grader,
        chrome: chrome ? browser(chrome_wait) : "skipped",
        chrome_egress: chrome ? egress(chrome_wait) : "skipped",
        harness: chrome ? harness(chrome_wait) : "skipped",
        disk: disk, backup: backup, student_users: student_users
      }
      problems = parts.filter_map { |name, value| name if failing?(name, value) }
      { ok: problems.empty?, problems: problems.map(&:to_s) }.merge(parts).merge(
        validation_queue: validation_queue,
        decisions: { enabled: ENV["BANCO_DECISIONS_ENABLED"] == "1" },
        lesson2: { enabled: Banco::Lesson2.enabled? },
        diagnosis: { released: Diagnosis::Release.open? },
        contract: Contract.digest, checked_at: Time.current.utc.iso8601
      )
    end

    private

    OK_VALUES = %w[ok busy not_applicable not_configured skipped blocked].freeze

    def failing?(name, value)
      return !%w[ok not_applicable].include?(value) if name == :queue

      value = value[:status] if value.is_a?(Hash)
      !OK_VALUES.include?(value)
    end

    def db
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("INSERT INTO app_events (kind, created_at) VALUES ('health_probe', datetime('now'))")
        raise ActiveRecord::Rollback
      end
      "ok"
    rescue StandardError => e
      "error: #{e.class}: #{e.message.to_s.first(120)}"
    end

    # Production runs Solid Queue on its own database; elsewhere jobs run in the process.
    def queue
      return "not_applicable" unless Rails.application.config.active_job.queue_adapter.to_s == "solid_queue"

      fresh = SolidQueue::Process.where("last_heartbeat_at > ?", QUEUE_HEARTBEAT_SECONDS.seconds.ago).count
      fresh.positive? ? "ok" : "error: no Solid Queue process has a heartbeat in the last #{QUEUE_HEARTBEAT_SECONDS} s"
    rescue StandardError => e
      "error: #{e.class}: #{e.message.to_s.first(120)}"
    end

    # Why chrome, chrome_egress and harness say "busy": validations waiting for the one
    # Chrome lane. Informational, never gates (D-162).
    def validation_queue
      { waiting: ItemRevision.unsettled.count }
    rescue StandardError => e
      { error: "#{e.class}: #{e.message.to_s.first(120)}" }
    end

    def grader
      Grading::Expression.worker.request("op" => "ping")
      "ok"
    rescue StandardError => e
      "error: #{e.class}: #{e.message.to_s.first(120)}"
    end

    def browser(wait)
      case Validation::ChromeRunner.available?(wait: wait)
      when true then "ok"
      when :busy then "busy"
      else "unavailable"
      end
    rescue StandardError => e
      "error: #{e.class}: #{e.message.to_s.first(120)}"
    end

    # With the sidecar configured, agent code must not be able to leave the
    # internal network: Chrome loads an address outside it and must fail.
    def egress(wait)
      return "not_configured" if ENV["BANCO_CHROME_HOST"].blank?

      Validation::ChromeRunner.session(wait: wait) do |session|
        session.context do |ctx|
          page = ctx.create_page
          reached = begin
            page.go_to(ENV.fetch("BANCO_EGRESS_PROBE", EGRESS_PROBE))
            page.network.status.to_i.between?(100, 599)
          rescue Ferrum::Error
            false
          end
          reached ? "open" : "blocked"
        end
      end
    rescue Validation::ChromeRunner::Busy
      "busy"
    rescue StandardError => e
      "error: #{e.class}: #{e.message.to_s.first(120)}"
    end

    # Chrome must reach the harness listener, or every generator validation fails
    # with E-CHROME-UNAVAILABLE while chrome says ok (D-153). Any HTTP status counts.
    def harness(wait)
      return "not_configured" if ENV["BANCO_CHROME_HOST"].blank?

      Validation::ChromeRunner.session(wait: wait) do |session|
        session.context do |ctx|
          page = ctx.create_page
          begin
            page.go_to("#{Validation::Harness.base_url}/up")
            page.network.status.to_i.between?(100, 599) ? "ok" : "unreachable"
          rescue Ferrum::Error => e
            "unreachable: #{e.class}: #{e.message.to_s.first(100)}"
          end
        end
      end
    rescue Validation::ChromeRunner::Busy
      "busy"
    rescue StandardError => e
      "error: #{e.class}: #{e.message.to_s.first(120)}"
    end

    # BANCO_STUDENT_USERS must be well formed once it is set (D-219): a bad pair is a problem, and the
    # map still counts as configured, so unmapped logins get the 403 page. Positions only.
    def student_users
      return "not_configured" unless Banco::EdgeProxy.student_map_configured?

      bad = Banco::EdgeProxy.student_map_problems
      return "error: BANCO_STUDENT_USERS has no valid pair, so every student login is refused" if Banco::EdgeProxy.student_map.empty? && bad.empty?

      bad.empty? ? "ok" : "error: BANCO_STUDENT_USERS has a bad pair at position #{bad.join(', ')} (login=key, key [a-z0-9-]+, not preview or all)"
    end

    def disk
      path = ENV["BANCO_DATA_DIR"].presence || Rails.root.join("storage").to_s
      free_mb = `df -Pk #{Shellwords.escape(path)} 2>/dev/null`.lines.last.to_s.split[3].to_i / 1024
      { status: free_mb >= DISK_MIN_FREE_MB ? "ok" : "low", free_mb: free_mb, min_mb: DISK_MIN_FREE_MB }
    rescue StandardError => e
      { status: "error: #{e.class}" }
    end

    # The newest file of BANCO_BACKUP_DIR must be younger than 36 hours.
    def backup
      dir = ENV["BANCO_BACKUP_DIR"].presence
      return "not_configured" unless dir

      newest = Dir.glob(File.join(dir, "*")).select { |f| File.file?(f) }.max_by { |f| File.mtime(f) }
      return { status: "missing", dir_present: Dir.exist?(dir) } unless newest

      age = ((Time.current - File.mtime(newest)) / 3600.0).round(1)
      { status: age <= BACKUP_MAX_AGE_HOURS ? "ok" : "stale", age_hours: age, max_age_hours: BACKUP_MAX_AGE_HOURS }
    rescue StandardError => e
      { status: "error: #{e.class}" }
    end
  end
end
