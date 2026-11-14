require "test_helper"
require "rake"
require "tmpdir"
require_relative "../support/public_api_tokens"

# D-330: a public token renews itself on use and never expires while it is used; the bot learns what changed in the
# software (GET /api/v1/updates), reads its docs (GET /api/v1/docs/:name) and downloads the CLI's release build of the
# image (GET /api/v1/cli/:file), from allowlists only; through the edge only the public roles, as for every other route.
class PublicApiUpdatesTest < ActionDispatch::IntegrationTest
  include PublicApiTokens

  EDGE = ListenerHelpers::EDGE_IP

  setup do
    @saved_edge = ENV.to_h.slice("BANCO_EDGE_PROXY")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    @scratch = Pathname(Dir.mktmpdir("banco-dist"))
    Updates.dist_dir = @scratch.join("absent") # development: no release build
  end

  teardown do
    @saved_edge.key?("BANCO_EDGE_PROXY") ? ENV["BANCO_EDGE_PROXY"] = @saved_edge["BANCO_EDGE_PROXY"] : ENV.delete("BANCO_EDGE_PROXY")
    Updates.dist_dir = nil
    FileUtils.rm_rf(@scratch)
  end

  def row(token) = ApiToken.find_by!(public_id: public_id(token))

  def renewals(token) = ApiTokenRenewal.where(api_token: row(token)).order(:id).to_a

  def run_task(name, env)
    Rails.application.load_tasks unless Rake::Task.task_defined?(name)
    task = Rake::Task[name]
    task.reenable
    with_env(env) { capture_io { task.invoke } }.first
  end

  # A release build in the scratch directory: two listed binaries, one listed but missing, one present but not listed,
  # a line that names a path, a listed symlink to a file outside dist/, a listed directory, and build.json.
  def build_dist
    dist = @scratch.join("dist")
    dist.mkpath
    files = { "banco-linux-amd64" => "linux program", "banco-windows-arm64.exe" => "windows program", "banco-darwin-amd64" => "not listed" }
    files.each { |name, body| dist.join(name).write(body) }
    @scratch.join("outside").write("outside program")
    File.symlink(@scratch.join("outside"), dist.join("banco-darwin-arm64"))
    dist.join("banco-windows-amd64.exe").mkpath
    sums = [ "#{Digest::SHA256.hexdigest('linux program')}  banco-linux-amd64",
             "#{Digest::SHA256.hexdigest('windows program')} *banco-windows-arm64.exe",
             "#{'0' * 64}  banco-linux-arm64",
             "#{'1' * 64}  ../build.json",
             "#{'2' * 64}  SHA256SUMS",
             "#{Digest::SHA256.hexdigest('outside program')}  banco-darwin-arm64",
             "#{'3' * 64}  banco-windows-amd64.exe" ]
    dist.join("SHA256SUMS").write(sums.join("\n") + "\n")
    dist.join("build.json").write(%({"version":"0.1.0+abcdef123456","built_at":"2026-11-14T10:00:00Z"}\n))
    Updates.dist_dir = dist
    dist
  end

  # ---- renewal on use

  test "a public token renews once a day, to now plus its lifetime" do
    token = issue_token("bot_read", expires_at: 30.days.from_now)
    api_as(token, "/api/v1/status")
    assert_response :success
    assert_empty renewals(token), "a fresh token has its whole lifetime: nothing to renew"

    travel 1.day + 1.minute
    api_as(token, "/api/v1/status")
    assert_response :success
    assert_equal 1, renewals(token).size
    assert_in_delta 30.days.from_now.to_f, renewals(token).last.expires_at.to_f, 2
    assert_in_delta 30.days.from_now.to_f, row(token).effective_expires_at.to_f, 2
    3.times { api_as(token, "/api/v1/status") }
    assert_equal 1, renewals(token).size, "at most one renewal a day"

    travel 1.day + 1.minute
    api_as(token, "/api/v1/token")
    assert_equal 2, renewals(token).size
    assert_equal renewals(token).last.expires_at.utc.iso8601, json["expires_at"]
  end

  test "a token used within its lifetime never expires, an idle one does" do
    used = issue_token("teacher", expires_at: 3.days.from_now)
    idle = issue_token("bot_read", expires_at: 3.days.from_now)
    10.times do
      travel 2.days
      api_as(used, "/api/v1/status")
      assert_response :success
    end
    assert_operator row(used).effective_expires_at, :>, 1.day.from_now
    api_as(idle, "/api/v1/status")
    assert_response :unauthorized
    assert_empty renewals(idle)
  end

  test "a one-day token renews at half its lifetime" do
    token = issue_token("bot_read", expires_at: 1.day.from_now)
    assert_equal 1, row(token).lifetime_days
    travel 11.hours
    api_as(token, "/api/v1/status")
    assert_empty renewals(token)
    travel 2.hours
    api_as(token, "/api/v1/status")
    assert_equal 1, renewals(token).size
    assert_in_delta 1.day.from_now.to_f, renewals(token).last.expires_at.to_f, 2
  end

  test "the content roles never renew" do
    tokens = %w[agent_claude agent_omp ci].to_h { |role| [ role, issue_token(role, expires_at: 2.days.from_now) ] }
    travel 1.day + 12.hours
    tokens.each_value { |token| api_as(token, "/api/v1/status") }
    assert_equal 0, ApiTokenRenewal.count
    travel 1.day
    tokens.each do |role, token|
      api_as(token, "/api/v1/status")
      assert_response :unauthorized, role
    end
  end

  test "an expired token is not resurrected and a revoked one is not renewed" do
    expired = issue_token("bot_read", expires_at: 2.days.from_now)
    revoked = issue_token("teacher", expires_at: 2.days.from_now)
    ApiTokenRevocation.create!(api_token: row(revoked), reason: "test")
    travel 1.day + 12.hours
    api_as(revoked, "/api/v1/status")
    assert_response :unauthorized
    assert_nil row(revoked).renew_on_use!, "the model refuses a revoked token too"
    travel 1.day
    api_as(expired, "/api/v1/status")
    assert_response :unauthorized
    assert_nil row(expired).renew_on_use!
    assert_equal 0, ApiTokenRenewal.count
  end

  test "a refused request does not renew: a teacher token whose teacher left the list, a bot_read token that writes" do
    teacher = issue_token("teacher", expires_at: 3.days.from_now)
    bot = issue_token("bot_read", expires_at: 3.days.from_now)
    travel 2.days
    ENV["BANCO_TEACHER_USERS"] = "someone-else"
    api_as(teacher, "/api/v1/status")
    assert_response :forbidden
    api_as(bot, "/api/v1/decisions", method: :post, body: { kind: "approve_skill_graph", params: { subject: "math" } })
    assert_response :forbidden
    assert_equal 0, ApiTokenRenewal.count
  end

  test "the renewals are append-only" do
    token = issue_token("bot_read", expires_at: 2.days.from_now)
    travel 1.day + 1.hour
    api_as(token, "/api/v1/status")
    renewal = renewals(token).last
    assert_raises(ActiveRecord::StatementInvalid) { renewal.update_column(:expires_at, 1.year.from_now) }
    assert_raises(ActiveRecord::StatementInvalid) { renewal.delete }
  end

  test "a renewal that fails is logged and the request goes on" do
    token = issue_token("bot_read", expires_at: 2.days.from_now)
    row = ApiToken.lookup(public_id(token))
    calls = 0
    failing = row.merge(renew: lambda { |_now|
      calls += 1
      raise ActiveRecord::StatementInvalid, "database is locked"
    })
    Banco::TokenAuth.lookup = ->(id) { id == public_id(token) ? failing : nil }
    api_as(token, "/api/v1/status")
    assert_response :success
    api_as(token, "/api/v1/updates")
    assert_response :success
    assert_equal 2, calls
    assert_equal 0, ApiTokenRenewal.count
  ensure
    Banco::TokenAuth.reset!
  end

  test "banco:token:list and expired? read the effective expiry" do
    token = issue_token("bot_read", expires_at: 3.days.from_now)
    travel 2.days
    api_as(token, "/api/v1/status")
    travel 2.days # past the expiry it was issued with, before the renewed one
    assert_operator row(token).expires_at, :<, Time.current
    assert_not row(token).expired?
    out = run_task("banco:token:list", {})
    effective = row(token).effective_expires_at.utc.strftime("%Y-%m-%d %H:%M")
    assert_match(/#{public_id(token)}\s+bot_read\s+.*#{effective}\s+active/, out)
    travel 2.days
    assert row(token).expired?
    assert_match(/#{public_id(token)}.*expired/, run_task("banco:token:list", {}))
  end

  # ---- GET /api/v1/token

  test "GET /api/v1/token shows the token without its secret" do
    token = issue_token("teacher", expires_at: 30.days.from_now)
    api_as(token, "/api/v1/token")
    assert_response :success
    assert_equal({ "public_id" => public_id(token), "role" => "teacher", "teacher" => TEACHER_LOGIN, "label" => "public api test teacher",
                   "created_at" => row(token).created_at.utc.iso8601, "expires_at" => row(token).expires_at.utc.iso8601,
                   "renews_on_use" => true, "lifetime_days" => 30, "revoked" => false }, json)
    assert_not_includes response.body, Banco::TokenAuth::FORMAT.match(token)[2]
    assert_not_includes response.body, row(token).secret_sha256
    assert_equal "no-store", response.headers["Cache-Control"]

    api_as(issue_token("agent_omp", expires_at: 10.days.from_now), "/api/v1/token")
    assert_equal [ "agent_omp", nil, false, 10 ], json.values_at("role", "teacher", "renews_on_use", "lifetime_days")
  end

  # ---- GET /api/v1/updates

  test "GET /api/v1/updates without a release build: the commit, the contract digest of the header, the docs and every change" do
    api_as(issue_token("bot_read"), "/api/v1/updates")
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal Grading.git_sha, json.dig("server", "commit")
    assert_nil json.dig("server", "built_at")
    assert_equal response.headers["X-Banco-Contract"], json["contract_digest"]
    assert_equal Contract.digest, json["contract_digest"]
    assert_equal({ "version" => nil, "files" => [] }, json["cli"])
    assert_equal(%w[bot api].map { |name| { "name" => name, "sha256" => Digest::SHA256.file(Rails.root.join("docs/#{name}.md")).hexdigest } }, json["docs"])
    index_rows = Rails.root.join("docs/decisions.md").read.scan(/^\| D-\d{3,} \|/).size
    assert_equal index_rows, json["changes"].size
    numbers = json["changes"].map { |c| c["number"].delete_prefix("D-").to_i }
    assert_equal numbers.sort, numbers, "newest last"
    d327 = json["changes"].find { |c| c["number"] == "D-327" }
    assert_equal "2026-11-14", d327["date"]
    assert_equal "implemented", d327["status"]
    assert_includes d327["title"], "the public API on api.banco.scc.im"
    d328 = json["changes"].find { |c| c["number"] == "D-328" }
    assert_includes d328["title"], "`/subjects/:key/course|topics/:topic|test`", "a | inside the title is kept"
    assert_equal "implemented", d328["status"]
  end

  test "GET /api/v1/updates?since=D-NNN lists the later changes only, and refuses another since" do
    token = issue_token("bot_read")
    api_as(token, "/api/v1/updates?since=D-327")
    assert_response :success
    numbers = json["changes"].map { |c| c["number"] }
    assert_includes numbers, "D-328"
    assert_includes numbers, "D-330"
    assert numbers.all? { |n| n.delete_prefix("D-").to_i > 327 }, numbers.inspect
    api_as(token, "/api/v1/updates?since=D-9999")
    assert_equal [], json["changes"]
    [ "327", "D-1", "D-32x", "" ].each do |since|
      api_as(token, "/api/v1/updates?since=#{CGI.escape(since)}")
      assert_response :unprocessable_entity, since
      assert_equal [ "E-FILES", "since" ], json.values_at("code", "field"), since
    end
  end

  test "GET /api/v1/updates lists the listed binaries that are there, with the build's version and time" do
    build_dist
    api_as(issue_token("teacher"), "/api/v1/updates")
    assert_response :success
    assert_equal "2026-11-14T10:00:00Z", json.dig("server", "built_at")
    assert_equal "0.1.0+abcdef123456", json.dig("cli", "version")
    assert_equal [
      { "name" => "banco-linux-amd64", "os" => "linux", "arch" => "amd64", "sha256" => Digest::SHA256.hexdigest("linux program"), "size" => 13 },
      { "name" => "banco-windows-arm64.exe", "os" => "windows", "arch" => "arm64", "sha256" => Digest::SHA256.hexdigest("windows program"), "size" => 15 }
    ], json.dig("cli", "files")
  end

  # ---- GET /api/v1/docs/:name

  test "GET /api/v1/docs/:name serves bot and api, nothing else" do
    token = issue_token("bot_read")
    { "bot" => "docs/bot.md", "api" => "docs/api.md" }.each do |name, path|
      api_as(token, "/api/v1/docs/#{name}")
      assert_response :success
      text = Rails.root.join(path).read
      assert_equal({ "name" => name, "sha256" => Digest::SHA256.hexdigest(text), "text" => text }, json)
    end
    %w[decisions course readme BOT].each do |name|
      api_as(token, "/api/v1/docs/#{name}")
      assert_response :not_found, name
    end
    api_as(token, "/api/v1/docs/decisions")
    assert_equal [ "E-NOT-FOUND", "name" ], json.values_at("code", "field")
    [ "/api/v1/docs/..%2FAGENTS", "/api/v1/docs/../AGENTS.md", "/api/v1/docs/bot.md", "/api/v1/docs/%2Fetc%2Fpasswd" ].each do |path|
      api_as(token, path)
      assert_response :not_found, path
      assert_not_includes response.body, "agent guide", path
    end
  end

  # ---- GET /api/v1/cli/:file

  test "GET /api/v1/cli/:file streams a listed binary with its sha256, and nothing that SHA256SUMS does not list" do
    build_dist
    token = issue_token("bot_read")
    api_as(token, "/api/v1/cli/banco-linux-amd64")
    assert_response :success
    assert_equal "linux program", response.body
    assert_equal Digest::SHA256.hexdigest("linux program"), response.headers["X-Banco-Sha256"]
    assert_equal Contract.digest, response.headers["X-Banco-Contract"]
    assert_equal "no-store", response.headers["Cache-Control"]
    api_as(token, "/api/v1/cli/banco-windows-arm64.exe")
    assert_equal "windows program", response.body

    # present but not listed, listed but missing, a listed symlink and directory, and every way out of the directory
    [ "/api/v1/cli/banco-darwin-amd64", "/api/v1/cli/banco-linux-arm64", "/api/v1/cli/SHA256SUMS", "/api/v1/cli/build.json",
      "/api/v1/cli/banco-darwin-arm64", "/api/v1/cli/banco-windows-amd64.exe",
      "/api/v1/cli/..%2Fbuild.json", "/api/v1/cli/../dist/SHA256SUMS", "/api/v1/cli/banco-linux-amd64%2F..%2F..%2FGemfile",
      "/api/v1/cli/%2Fetc%2Fpasswd", "/api/v1/cli/banco-..-amd64", "/api/v1/cli/banco-linux-amd64.exe" ].each do |path|
      api_as(token, path)
      assert_response :not_found, path
      [ "linux program", "windows program", "not listed", "outside program" ].each { |body| assert_not_includes response.body, body, path }
    end
  end

  test "GET /api/v1/cli/:file is 404 without a release build" do
    api_as(issue_token("bot_read"), "/api/v1/cli/banco-linux-amd64")
    assert_response :not_found
    assert_equal [ "E-NOT-FOUND", "file" ], json.values_at("code", "field")
  end

  # ---- the edge

  test "through the edge only the public roles reach the new routes; no token is 401" do
    build_dist
    paths = %w[/api/v1/token /api/v1/updates /api/v1/docs/bot /api/v1/cli/banco-linux-amd64]
    %w[bot_read teacher].each do |role|
      token = issue_token(role)
      paths.each do |path|
        api_as(token, path, remote_addr: EDGE)
        assert_response :success, "#{role} #{path}"
      end
    end
    %w[agent_claude agent_omp ci].each do |role|
      token = issue_token(role)
      paths.each do |path|
        api_as(token, path, remote_addr: EDGE)
        assert_response :forbidden, "#{role} #{path}"
        assert_equal [ "E-AUTH", "not_public_role" ], json.values_at("code", "reason")
        api_as(token, path) # the local listener still serves it
        assert_response :success, "#{role} #{path} locally"
      end
    end
    paths.each do |path|
      api_as(nil, path, remote_addr: EDGE)
      assert_response :unauthorized, path
      assert_nil response.headers["X-Banco-Contract"]
    end
  end
end
