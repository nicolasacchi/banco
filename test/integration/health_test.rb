require "test_helper"

# banco health (GET /api/v1/health): the parts of the installation, read-only.
class HealthTest < ActionDispatch::IntegrationTest
  setup { @token = ApiToken.issue!(role: "agent_claude", label: "health test") }

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
