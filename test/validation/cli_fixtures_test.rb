require "test_helper"
require "open3"
require "tmpdir"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"

# The compiled CLI against the API listener (a real HTTP server in the test process):
# the content agent's whole cycle on bad fixtures (M5). Needs Go and Chrome; skips
# with a message when either is missing.
class CliFixturesTest < ActiveSupport::TestCase
  include ChromeHelper
  include CourseRows
  F = ValidationFixtures
  TRANSIENT_BUDGET = 600 # seconds

  class << self
    # One binary per test process: the test workers are forks and build their own.
    def bin = @bin ||= Rails.root.join("tmp/banco-test-#{Process.pid}").to_s

    def build_cli
      return @built unless @built.nil?

      @built = system({ "GOFLAGS" => "-buildvcs=false" }, "go", "build", "-o", bin, "./cli", chdir: Rails.root.to_s, out: File::NULL, err: File::NULL)
      path = bin
      at_exit { FileUtils.rm_f(path) }
      @built
    end
  end

  setup do
    require_chrome!
    skip "go is not installed" unless system("go", "version", out: File::NULL, err: File::NULL)
    skip "the CLI did not build" unless self.class.build_cli
    @previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    @token = ApiToken.issue!(role: "agent_claude", label: "cli fixtures")
    build_course
    @tmp = Dir.mktmpdir("banco-cli-")
  end

  teardown do
    ActiveJob::Base.queue_adapter = @previous_adapter if @previous_adapter
    FileUtils.rm_rf(@tmp) if @tmp
  end

  # Runs the compiled CLI; returns [exit status, parsed stdout or nil, parsed stderr or nil].
  def banco(*args, as: :author)
    env = { "BANCO_URL" => ValidationServers.url(:api), "BANCO_TOKEN" => @token, "BANCO_POLL_MS" => "200", "BANCO_SESSION" => session_of(as).id.to_s }
    # Test processes share one Chrome lock and the host is loaded. A dry run that finds
    # the lock taken (exit 5, E-CHROME-BUSY) or Chrome slow to answer (exit 6,
    # E-CHROME-UNAVAILABLE, the API's 503 "retry in 30 s") waits and asks again, as the
    # error's "next" says. Only those two transient codes are retried, for a bounded time; any other failure (a real bug) is returned at once, and so is the last
    # transient answer when the budget runs out.
    result = nil
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TRANSIENT_BUDGET
    loop do
      out, err, status = Open3.capture3(env, self.class.bin, *args, chdir: @tmp)
      result = [ status.exitstatus, (JSON.parse(out) rescue nil), (JSON.parse(err.lines.last.to_s) rescue nil), out, err ]
      transient = (status.exitstatus == 5 && err.include?("E-CHROME-BUSY")) ||
                  (status.exitstatus == 6 && err.include?("E-CHROME-UNAVAILABLE"))
      return result if !transient || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep(1 + rand * 2)
    end
  end

  # One session per role: the author writes item.json and the generator, the verifier verify.mjs (A-04).
  def session_of(role)
    @sessions ||= {}
    @sessions[role] ||= AgentSession.create!(label: "cli", role: role.to_s, agent: "test", model: "claude-test")
  end

  def item_dir(name, files)
    dir = File.join(@tmp, name)
    FileUtils.mkdir_p(dir)
    files.each { |file, text| File.write(File.join(dir, file), text) }
    dir
  end

  def graph_file(doc)
    path = File.join(@tmp, "graph-#{SecureRandom.hex(3)}.json")
    File.write(path, JSON.generate(doc))
    path
  end

  # ---- the three bad fixtures of the M5 verify ------------------------------------------

  test "E-GRAPH-CYCLE: skill-graph submit --dry-run exits 3 with the code, and stores nothing" do
    doc = JSON.parse(JSON.generate(F::GRAPH))
    doc["skills"].find { |s| s["key"] == "math.integer-operations" }["prerequisites"] = [ "math.percentages" ]
    code, out, err, _o, e = banco("skill-graph", "submit", "--subject", "math", graph_file(doc), "--dry-run")
    assert_equal 3, code, e
    assert_nil out
    assert_equal "E-GRAPH-CYCLE", err["code"]
    assert_equal true, err["dry_run"]
    assert_includes err["codes"], "E-GRAPH-CYCLE"
    assert_equal 1, SkillGraphRevision.where(subject: @subject).count # the course's own graph only
  end

  test "E-SOLUTION-IN-DISPLAY: work submit --dry-run exits 3 with the code" do
    source = <<~JS
      export function generate(seed, rng) {
        const x = rng.int(100, 900);
        const a = rng.int(2, 40);
        return {
          display: { stem_it: "Risolvi $x+" + a + "=" + (x + a) + "$.", table: { header: ["Dato"], rows: [[String(x)]] } },
          answer: String(x),
          errors: [{ code: "sign_error", value: String(x + 2 * a) }],
          solution: { steps: [{ text_it: "Togli " + a + "." }], final: "x = " + x }
        };
      }
    JS
    dir = item_dir("leaky", F.generated_files(generator: source, verify: nil))
    code, _out, err, _o, e = banco("work", "submit", dir, "--dry-run")
    assert_equal 3, code, e
    assert_equal "E-SOLUTION-IN-DISPLAY", err["code"]
    assert(err["findings"].any? { |f| f["code"] == "E-SOLUTION-IN-DISPLAY" && f["field"].start_with?("generated") })
    assert_equal 0, Item.count
  end

  test "E-VERIFY-REJECTS: dry run, then the stored revision's work status --wait exits 3" do
    wrong = F::VERIFY.sub("Number(m[2]) - Number(m[1])", "Number(m[2]) + Number(m[1])")
    dir = item_dir("badverify", F.generated_files(verify: nil))
    code, out, _err, _o, e = banco("work", "submit", dir, "--item", "badverify")
    assert_equal 0, code, e
    # The author cannot add verify.mjs (A-04); the verifier's wrong one is what fails.
    File.write(File.join(dir, "verify.mjs"), wrong)
    code, _out, err, _o, e = banco("work", "submit", dir, "--dry-run")
    assert_equal 3, code, e
    assert_equal "E-VERIFY-AUTHOR", err["code"]
    vdir = File.join(@tmp, "badverify-v")
    code, _out, _err, _o, e = banco("work", "open", "badverify", "--role", "verifier", "--dir", vdir, as: :verifier)
    assert_equal 0, code, e
    File.write(File.join(vdir, "verify.mjs"), wrong)
    code, _out, err, _o, e = banco("work", "submit", vdir, "--dry-run", as: :verifier)
    assert_equal 3, code, e
    assert_equal "E-VERIFY-REJECTS", err["code"]
    assert_equal 1, ItemRevision.count

    code, out, _err, _o, e = banco("work", "submit", vdir, as: :verifier)
    assert_equal 0, code, e
    assert_equal false, out["replayed"]
    code, status, err, _o, e = banco("work", "status", out["revision_id"].to_s, "--wait")
    assert_equal 3, code, e
    assert_equal "failed", status["status"]
    assert_equal "E-VERIFY-REJECTS", err["code"]
    assert_equal 24, status["instances"] # materialized all the same
  end

  # ---- the good fixture and the cycle between author and verifier ---------------------------------

  test "the good fixture: dry run passes with 24 instances; the author's run is E-VERIFY-MISSING; the verifier completes it" do
    dir = item_dir("good", F.generated_files(verify: nil))
    code, _out, err, _o, e = banco("work", "submit", dir, "--dry-run")
    assert_equal 3, code, e # E-VERIFY-MISSING is an error, with the instances
    assert_equal "E-VERIFY-MISSING", err["code"]
    code, out, _err, _o, e = banco("work", "submit", dir)
    assert_equal 0, code, e
    first = out["revision_id"]
    code, status, err, _o, _e = banco("work", "status", first.to_s, "--wait")
    assert_equal 3, code
    assert_equal "E-VERIFY-MISSING", err["code"]
    assert_equal 24, status["instances"]

    vdir = File.join(@tmp, "verifier")
    code, opened, _err, _o, e = banco("work", "open", "good", "--role", "verifier", "--dir", vdir, as: :verifier)
    assert_equal 0, code, e
    assert_equal "verifier", opened["role"]
    assert_not File.exist?(File.join(vdir, "generator.mjs")), "the verifier never receives generator.mjs"
    instances = JSON.parse(File.read(File.join(vdir, "instances.json")))
    assert_equal 8, instances.size
    assert instances.first.key?("answer")
    File.write(File.join(vdir, "verify.mjs"), F::VERIFY)
    code, out, _err, _o, e = banco("work", "submit", vdir, as: :verifier)
    assert_equal 0, code, e
    assert_equal 2, out["seq"]
    code, status, _err, _o, e = banco("work", "status", out["revision_id"].to_s, "--wait")
    assert_equal 0, code, e
    assert_equal "passed", status["status"]

    code, st, _err, _o, e = banco("status", "--json")
    assert_equal 0, code, e
    assert_equal "math", st["subjects"].first["key"]
    assert_equal 1, st["subjects"].first["items"]["passed"]
  end
end
