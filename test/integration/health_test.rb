require "test_helper"

# banco health (GET /api/v1/health): the parts of the installation, read-only.
class HealthTest < ActionDispatch::IntegrationTest
  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "health test")
    Banco::PagesApp.reset_cookie_count! # the counter is the process's: another test may have left it
  end

  def api(path) = on(:api, path, headers: { "Authorization" => "Bearer #{@token}" })

  test "health answers with ok and each part, and leaves no row behind" do
    before = AppEvent.count
    Health.stub(:disk, { status: "ok", free_mb: 50_000, min_mb: Health::DISK_MIN_FREE_MB }) do
      api "/api/v1/health?chrome=0"
    end
    assert_response :ok
    record_example "health", "no-chrome"
    body = response.parsed_body
    assert_equal true, body["ok"]
    assert_equal "ok", body["db"]
    assert_equal "ok", body["grader"]
    assert_equal "skipped", body["chrome"]
    assert_equal "not_applicable", body["queue"]
    assert_equal "not_configured", body["backup"]
    assert_equal({ "waiting" => 0 }, body["validation_queue"])
    assert_equal({ "enabled" => false }, body["decisions"].slice("enabled"))
    assert_equal before, AppEvent.count
  end

  test "a problem turns ok false and is named" do
    Health.stub(:disk, { status: "low", free_mb: 10, min_mb: Health::DISK_MIN_FREE_MB }) do
      report = Health.check(chrome: false)
      assert_equal false, report[:ok]
      assert_equal [ "disk" ], report[:problems]
    end
  end

  test "a bad pair in BANCO_STUDENT_USERS is a problem that names its position and never its value" do
    with_env("BANCO_STUDENT_USERS" => nil) { assert_equal "not_configured", Health.check(chrome: false)[:student_users] }
    with_env("BANCO_STUDENT_USERS" => "kid-a=student,secretish,trial-x=preview") do
      report = Health.check(chrome: false)
      assert_includes report[:problems], "student_users"
      assert_match(/position 2, 3/, report[:student_users])
      assert_no_match(/secretish|kid-a/, report[:student_users])
    end
    with_env("BANCO_STUDENT_USERS" => "kid-a=student") { assert_equal "ok", Health.check(chrome: false)[:student_users] }
  end

  test "the backup directory counts only when configured, and a stale copy fails it" do
    Dir.mktmpdir do |dir|
      with_env("BANCO_BACKUP_DIR" => dir) do
        assert_equal "missing", Health.check(chrome: false)[:backup][:status]
        file = File.join(dir, "banco.sqlite3")
        File.write(file, "x")
        assert_equal "ok", Health.check(chrome: false)[:backup][:status]
        old = Time.now - 40 * 3600
        File.utime(old, old, file)
        report = Health.check(chrome: false)
        assert_equal "stale", report[:backup][:status]
        assert_includes report[:problems], "backup"
      end
    end
  end

  test "the backup is the newest file of the day directories backup.sh writes, a read-only mount included, and the working directory never counts (D-369)" do
    Dir.mktmpdir do |dir|
      with_env("BANCO_BACKUP_DIR" => dir) do
        day = File.join(dir, "2026-11-19")
        Dir.mkdir(day)
        file = File.join(day, "production.sqlite3.gz")
        File.write(file, "x" * 2048)
        File.utime(Time.now - 3 * 3600, Time.now - 3 * 3600, file)
        Dir.mkdir(File.join(dir, ".tmp.abc123"))
        File.write(File.join(dir, ".tmp.abc123", "production.sqlite3"), "half-written") # fresh, but not a backup

        backup = Health.check(chrome: false)[:backup]
        assert_equal "ok", backup[:status]
        assert_in_delta 3.0, backup[:age_hours], 0.1
        assert_equal "2026-11-19/production.sqlite3.gz", backup[:newest]
        assert_equal 36, backup[:max_age_hours]

        old = Time.now - 37 * 3600
        File.utime(old, old, file)
        assert_equal "stale", Health.check(chrome: false)[:backup][:status], "the working directory's fresh file must not hide a stale backup"

        File.utime(Time.now - 35 * 3600, Time.now - 35 * 3600, file)
        File.chmod(0o500, day)
        File.chmod(0o500, dir)
        begin
          assert_equal "ok", Health.check(chrome: false)[:backup][:status], "35 h is still fresh, and reading needs no write permission"
        ensure
          File.chmod(0o700, dir)
          File.chmod(0o700, day)
        end

        newer = File.join(dir, "2026-11-18")
        Dir.mkdir(newer)
        File.write(File.join(newer, "production_queue.sqlite3.gz"), "y")
        assert_equal "2026-11-18/production_queue.sqlite3.gz", Health.check(chrome: false)[:backup][:newest], "the newest file wins across the day directories"
      end
    end
  end

  test "a backup directory that is gone says missing and fails (a lost mount is not not_configured)" do
    with_env("BANCO_BACKUP_DIR" => File.join(Dir.tmpdir, "banco-no-such-backup-dir")) do
      report = Health.check(chrome: false)
      assert_equal({ status: "missing", dir_present: false }, report[:backup])
      assert_includes report[:problems], "backup"
    end
  end

  test "jobs: not applicable without Solid Queue, and never gating" do
    assert_equal({ status: "not_applicable" }, Health.jobs)
    api "/api/v1/health?chrome=0"
    assert_equal({ "status" => "not_applicable" }, response.parsed_body["jobs"])
  end

  test "jobs: the failures of the last 24 hours by class, and the speech backlog" do
    c = ApplicationRecord.connection
    c.create_table(:solid_queue_jobs) do |t|
      t.string :queue_name, null: false
      t.string :class_name, null: false
      t.datetime :created_at, null: false
    end
    c.create_table(:solid_queue_failed_executions) do |t|
      t.bigint :job_id, null: false
      t.text :error
      t.datetime :created_at, null: false
    end
    c.create_table(:solid_queue_ready_executions) do |t|
      t.bigint :job_id, null: false
      t.string :queue_name, null: false
      t.datetime :created_at, null: false
    end
    c.create_table(:solid_queue_scheduled_executions) do |t|
      t.bigint :job_id, null: false
      t.string :queue_name, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :created_at, null: false
    end
    queue_models = [ SolidQueue::Job, SolidQueue::FailedExecution, SolidQueue::ReadyExecution, SolidQueue::ScheduledExecution ]
    queue_models.each(&:reset_column_information)

    now = Time.current
    job = ->(klass, queue) { c.insert("INSERT INTO solid_queue_jobs (queue_name, class_name, created_at) VALUES (#{c.quote(queue)}, #{c.quote(klass)}, #{c.quote(now)})") }
    failed = ->(id, at) { c.execute("INSERT INTO solid_queue_failed_executions (job_id, created_at) VALUES (#{id}, #{c.quote(at)})") }
    ready = ->(queue, at) { c.execute("INSERT INTO solid_queue_ready_executions (job_id, queue_name, created_at) VALUES (1, #{c.quote(queue)}, #{c.quote(at)})") }

    Health.stub(:solid_queue?, true) do
      clean = Health.jobs
      assert_equal "ok", clean[:status]
      assert_equal({ total: 0, by_class: {} }, clean[:failed_24h])
      assert_equal({ ready: 0, scheduled: 0, oldest_ready_minutes: nil }, clean[:speech])

      2.times { failed.call(job.call("SpeakLessonRevisionJob", "speech"), now - 2.hours) }
      failed.call(job.call("SearchEmbedJob", "search"), now - 23.hours)
      failed.call(job.call("SpeakLessonRevisionJob", "speech"), now - 25.hours) # too old
      ready.call("speech", now - 90.minutes)
      ready.call("speech", now - 5.minutes)
      ready.call("search", now - 500.minutes)
      c.execute("INSERT INTO solid_queue_scheduled_executions (job_id, queue_name, scheduled_at, created_at) VALUES (4, 'speech', #{c.quote(now + 5.minutes)}, #{c.quote(now)})")

      report = Health.jobs
      assert_equal "failed", report[:status]
      assert_equal({ total: 3, by_class: { "SearchEmbedJob" => 1, "SpeakLessonRevisionJob" => 2 } }, report[:failed_24h])
      assert_equal 2, report[:speech][:ready]
      assert_equal 1, report[:speech][:scheduled]
      assert_in_delta 90, report[:speech][:oldest_ready_minutes], 1
      assert_not_includes Health.check(chrome: false)[:problems], "jobs", "failed jobs are reported, never a problem"
    end
  ensure
    queue_models&.each(&:reset_column_information)
  end

  test "the decisions flag is reported and never gates" do
    with_env("BANCO_DECISIONS_ENABLED" => "1") do
      report = Health.check(chrome: false)
      assert_equal true, report[:decisions][:enabled]
      assert_equal true, report[:ok]
    end
  end

  test "an unavailable grader shows as a failing part, never a crash" do
    Grading::Expression.stub(:worker, -> { raise Grading::Expression::Unavailable, "down" }) do
      report = Health.check(chrome: false)
      assert_equal false, report[:ok]
      assert_match(/\Aerror:/, report[:grader])
    end
  end

  test "harness probe is not configured without a sidecar and fails when Chrome cannot reach it" do
    assert_equal "not_configured", Health.send(:harness, 1)
    assert_equal "skipped", Health.check(chrome: false)[:harness]
    assert Health.send(:failing?, :harness, "unreachable: Ferrum::StatusError: x")
  end

  test "with a sidecar Chrome the harness URL is the internal alias, not loopback" do
    with_env("BANCO_CHROME_HOST" => "banco-chrome", "BANCO_HARNESS_URL" => nil) do
      assert_equal "http://banco-harness:#{Banco::Listeners.ports.fetch(:harness)}", Validation::Harness.base_url
    end
    with_env("BANCO_CHROME_HOST" => nil, "BANCO_HARNESS_URL" => nil) do
      assert_match(%r{\Ahttp://127\.0\.0\.1:\d+\z}, Validation::Harness.base_url)
    end
    with_env("BANCO_CHROME_HOST" => "banco-chrome", "BANCO_HARNESS_URL" => "http://x:1") do
      assert_equal "http://x:1", Validation::Harness.base_url
    end
  end
end
