require "test_helper"
require "rake"
require_relative "../support/decision_world"

# D-260: the operator records a decision from the host console (bin/rails banco:decide), never over HTTP.
# DecisionRecorder stays the only writer and every business guard of the kind still holds.
class DecisionConsoleTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  setup do
    build_decision_world
    @finding = ReviewFinding.create!(item_revision: @short, source: "review", severity: "major", field: "prompt", quote: "q", problem_it: "p", fix_it: "f")
  end

  def console(kind, **args) = DecisionConsole.call(kind: kind, teacher: "nik", os_user: "operator", **args)

  test "an unknown teacher is refused and nothing is written" do
    assert_no_difference "Decision.count" do
      result = console("approve_skill_graph", subject: "math", confirm: true, teacher: "mallory")
      assert_not result.ok
      assert_includes result.errors.first, "no_teacher"
    end
  end

  test "the flag off refuses" do
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    assert_no_difference "Decision.count" do
      result = console("approve_skill_graph", subject: "math", confirm: true)
      assert_not result.ok
      assert_includes result.errors.first, "disabled"
    end
  end

  test "a dry run writes nothing and shows the payload" do
    assert_no_difference "Decision.count" do
      result = console("approve_skill_graph", subject: "math")
      assert result.ok
      assert_not result.recorded
      assert_equal @graph.id, result.payload["revision_id"]
    end
  end

  test "CONFIRM writes exactly one decision with the console provenance" do
    assert_difference "Decision.count", 1 do
      result = console("approve_skill_graph", subject: "math", reason: "Operator approves.", confirm: true)
      assert result.recorded
    end
    d = Decision.order(:id).last
    assert_equal "approve_skill_graph", d.kind
    assert_equal @subject, d.subject
    assert_equal "nik", d.teacher_login
    assert_equal "console", d.remote_addr
    assert_equal "console", d.groups
    assert_equal "banco:decide operator", d.user_agent
    assert_equal "rake banco:decide", d.request_path
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, d.request_id)
    assert d.console?
    payload = JSON.parse(d.payload_json)
    assert_equal @graph.id, payload["revision_id"]
    assert_equal "console", payload["via"]
    assert_equal "Operator approves.", payload["console_reason"]
    assert_equal @graph, SubjectStage.approved_graph(@subject)
    assert SubjectStage.approved_from_console?(@subject, "approve_skill_graph")
  end

  test "approving an already approved graph is refused" do
    assert console("approve_skill_graph", subject: "math", confirm: true).ok
    assert_no_difference "Decision.count" do
      result = console("approve_skill_graph", subject: "math", confirm: true)
      assert_not result.ok
      assert_match(/already approved/, result.errors.join)
    end
  end

  test "an older revision than the latest is refused as on the web" do
    older = @graph
    SkillGraphRevision.create!(older.attributes.except("id").merge("seq" => older.seq + 1))
    assert_no_difference "Decision.count" do
      result = console("approve_skill_graph", subject: "math", revision: older.id, confirm: true)
      assert_not result.ok
      assert_match(/not the latest/, result.errors.join)
    end
  end

  test "the blueprint gate still refuses, and approves once it holds" do
    assert_no_difference "Decision.count" do
      result = console("approve_blueprint", subject: "math", confirm: true)
      assert_not result.ok
      assert_not_empty result.errors
    end
    make_blueprint_approvable!
    assert console("approve_skill_graph", subject: "math", confirm: true).ok
    assert console("dispose_finding", params: { finding_id: @finding.id, disposition: "dismissed" }, reason: "Va bene.", confirm: true).ok
    assert_difference "Decision.count", 1 do
      result = console("approve_blueprint", subject: "math", confirm: true)
      assert result.ok, result.errors.inspect
    end
    d = Decision.order(:id).last
    assert_equal "console", JSON.parse(d.payload_json)["via"]
    assert_equal @blueprint.id, SubjectStage.approved_blueprint(@subject).id
  end

  test "a finding disposition takes its parameters and its reason" do
    assert_no_difference "Decision.count" do
      result = console("dispose_finding", params: { finding_id: @finding.id, disposition: "dismissed" }, confirm: true)
      assert_not result.ok
      assert_match(/reason is required/, result.errors.join)
    end
    assert_difference "Decision.count", 1 do
      result = console("dispose_finding", params: { finding_id: @finding.id, disposition: "dismissed" }, reason: "Non è un errore.", confirm: true)
      assert result.ok, result.errors.inspect
    end
    payload = JSON.parse(Decision.order(:id).last.payload_json)
    assert_equal "Non è un errore.", payload["reason_it"]
    assert_equal "console", payload["via"]
    assert @finding.reload.disposed?
  end

  test "an unknown kind is refused" do
    result = console("approve_everything", confirm: true)
    assert_not result.ok
    assert_match(/unknown decision kind/, result.errors.join)
  end

  test "reconciliation treats a console decision as legitimate" do
    console("approve_skill_graph", subject: "math", confirm: true)
    result = DecisionReconciliation.call(since: 1.hour.ago)
    assert_empty result.items.select { |i| i[:type] == "decision_without_provenance" }
  end

  test "the teacher's graph page marks an approval made from the console" do
    console("approve_skill_graph", subject: "math", confirm: true)
    on(:web, "/teacher/subjects/math/graph", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_includes response.body, "(da console)"
  end

  test "no route of any listener maps to the console task and the agent API still cannot decide" do
    Rails.application.routes.routes.each do |route|
      target = "#{route.defaults[:controller]}##{route.defaults[:action]}"
      assert_no_match(/console|banco:decide/i, "#{route.path.spec} #{target}")
    end
    assert_no_difference "Decision.count" do
      on(:api, "/api/v1/decisions", method: :post, headers: { "Content-Type" => "application/json" }, params: { kind: "approve_skill_graph", revision_id: @graph.id }.to_json)
    end
    assert_includes [ 401, 404 ], response.status
    assert_not File.read(Rails.root.join("contract/commands.json")).match?(/decide|decision/i), "the CLI contract has no decision command"
  end

  test "the rake task is a dry run by default and records with CONFIRM=1" do
    Rake::Task.clear
    Rails.application.load_tasks
    saved = ENV.to_h.slice("KIND", "TEACHER", "SUBJECT", "CONFIRM")
    ENV.update("KIND" => "approve_skill_graph", "TEACHER" => "nik", "SUBJECT" => "math")
    out, = capture_io { Rake::Task["banco:decide"].reenable; Rake::Task["banco:decide"].invoke }
    assert_match(/dry run/, out)
    assert_equal 0, Decision.where(kind: "approve_skill_graph", remote_addr: "console").count
    ENV["CONFIRM"] = "1"
    out, = capture_io { Rake::Task["banco:decide"].reenable; Rake::Task["banco:decide"].invoke }
    assert_match(/recorded decision/, out)
    assert_equal 1, Decision.where(kind: "approve_skill_graph", remote_addr: "console").count
  ensure
    %w[KIND TEACHER SUBJECT CONFIRM].each { |k| saved&.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  test "the default OS user is the process account and never reads ENV[USER]" do
    saved = ENV["USER"]
    ENV["USER"] = "spoofed"
    expected = Etc.getpwuid(Process.euid).name.gsub(/[^A-Za-z0-9_.-]/, "").first(40)
    assert_equal expected, DecisionRecorder::Console.new(login: "nik").os_user
    result = DecisionConsole.call(kind: "approve_skill_graph", teacher: "nik", subject: "math", confirm: true)
    assert result.ok
    assert_equal "banco:decide #{expected}", Decision.order(:id).last.user_agent
    assert_not_includes Decision.order(:id).last.user_agent, "spoofed"
  ensure
    saved ? ENV["USER"] = saved : ENV.delete("USER")
  end

  test "a teacher login with a comma or surrounding spaces is refused, one in spaces is trimmed" do
    assert_no_difference "Decision.count" do
      assert_not console("approve_skill_graph", subject: "math", confirm: true, teacher: "nik,mallory").ok
      assert_not console("approve_skill_graph", subject: "math", confirm: true, teacher: "mallory, nik").ok
    end
    assert console("approve_skill_graph", subject: "math", confirm: true, teacher: "  nik  ").ok
    assert_equal "nik", Decision.order(:id).last.teacher_login
  end

  test "a missing subject is refused with a message" do
    assert_no_difference "Decision.count" do
      result = console("approve_skill_graph", subject: "nope", confirm: true)
      assert_not result.ok
      assert_match(/no subject/, result.errors.join)
    end
  end

  test "a dry run of dispose_finding leaves decisions and every touched table unchanged" do
    tables = ActiveRecord::Base.connection.tables - %w[schema_migrations ar_internal_metadata]
    counts = -> { tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{ActiveRecord::Base.connection.quote_table_name(t)}") ] } }
    before = counts.call
    result = console("dispose_finding", params: { finding_id: @finding.id, disposition: "dismissed" }, reason: "Va bene.")
    assert result.ok, result.errors.inspect
    assert_not result.recorded
    assert_equal before, counts.call
    assert_not @finding.reload.disposed?
  end

  test "the rake task exits 1 on a refusal" do
    Rake::Task.clear
    Rails.application.load_tasks
    saved = ENV.to_h.slice("KIND", "TEACHER", "SUBJECT", "CONFIRM", "PARAMS")
    run = lambda do |env|
      %w[KIND TEACHER SUBJECT CONFIRM PARAMS].each { |k| ENV.delete(k) }
      ENV.update(env)
      status = nil
      capture_io do
        Rake::Task["banco:decide"].reenable
        Rake::Task["banco:decide"].invoke
      rescue SystemExit => e
        status = e.status
      end
      status
    end
    base = { "KIND" => "approve_skill_graph", "TEACHER" => "nik", "SUBJECT" => "math", "CONFIRM" => "1" }
    assert_no_difference "Decision.count" do
      assert_equal 1, run.call(base.merge("TEACHER" => "mallory"))
      assert_equal 1, run.call(base.merge("PARAMS" => "{not json"))
      assert_equal 1, run.call(base.merge("PARAMS" => "[1]"))
      ENV["BANCO_DECISIONS_ENABLED"] = "0"
      assert_equal 1, run.call(base)
    end
  ensure
    %w[KIND TEACHER SUBJECT CONFIRM PARAMS].each { |k| saved&.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  test "the agent token gets 404, not just 401, on a would-be decision route" do
    token = ApiToken.issue!(role: "agent_claude", label: "console test")
    headers = { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    [ "/api/v1/decisions", "/api/v1/teacher/decisions/approve_skill_graph", "/teacher/decisions/approve_skill_graph" ].each do |path|
      assert_no_difference "Decision.count" do
        on(:api, path, method: :post, headers: headers, params: { revision_id: @graph.id }.to_json)
      end
      assert_equal 404, response.status, path
    end
  end

  test "the console origin is structurally unreachable from the web and the API" do
    # decision.rb only reads the origin's ADDR and GROUP constants to label a stored row (Decision#console?).
    allowed = %w[lib/tasks/decide.rake app/models/decision_console.rb app/models/decision_recorder.rb app/models/decision.rb]
    files = Dir[Rails.root.join("{app,lib}/**/*").to_s].select { |f| File.file?(f) }.map { |f| Pathname(f).relative_path_from(Rails.root).to_s }
    offenders = files.reject { |f| allowed.include?(f) }.select { |f| File.read(f).match?(/DecisionConsole|DecisionRecorder::Console/) }
    assert_empty offenders
    Dir[Rails.root.join("app/controllers/api/v1/**/*.rb").to_s].each do |f|
      assert_no_match(/DecisionRecorder|DecisionConsole/, File.read(f), f)
    end
  end
end
