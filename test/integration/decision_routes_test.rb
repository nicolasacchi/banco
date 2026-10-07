require "test_helper"
require_relative "../support/decision_world"

# Firm rule 2 (D-08): every decision route answers 404 on the API and harness
# listeners, 403 unless ALL of flag, teacher, CSRF and a computer that is not the
# student's hold, and records a decision with its provenance when everything is right.
class DecisionRoutesTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  setup { build_decision_world }

  # kind => [path, params], each possible right now (a voided run takes no more decisions: void is last). Built after the world exists.
  def cases
    {
      "approve_skill_graph" => [ "/teacher/skill-graph-revisions/#{@graph.id}/approve", {} ],
      "approve_blueprint" => [ "/teacher/blueprint-revisions/#{@blueprint.id}/approve", {} ],
      "confirm_test_reviewed" => [ "/teacher/blueprint-revisions/#{@blueprint.id}/confirm-reviewed", {} ],
      "dispose_finding" => [ "/teacher/findings/#{@finding.id}/disposition", { disposition: "dismissed", reason_it: "Non è un errore." } ],
      "confirm_grade" => [ "/teacher/grade-proposals/#{@proposal.id}/confirm", {} ],
      "reject_grade" => [ "/teacher/grade-proposals/#{@rejected.id}/reject", { reason_it: "Troppo severa." } ],
      "resolve_attempt" => [ "/teacher/attempts/#{@attempt.id}/resolve", { verdict: "correct", reason_it: "Giusta." } ],
      "extend_diagnosis_run" => [ "/teacher/runs/#{@run.id}/extend", { reason_it: "Serve altro tempo." } ],
      "close_diagnosis_run" => [ "/teacher/runs/#{@run.id}/close", { reason_it: "Basta così." } ],
      "void_revision_attempts" => [ "/teacher/item-revisions/#{@short.id}/void-attempts", { reason_it: "Item sbagliato." } ],
      "record_consent" => [ "/teacher/consent", { acknowledged: true } ],
      "kind_override" => [ "/teacher/subjects/math/kind-override", { skill: "math.number", override_kind: "learn", reason_it: "Non l'ha studiato." } ],
      "release_diagnosis" => [ "/teacher/release", {} ],
      "void_diagnosis_run" => [ "/teacher/runs/#{@run.id}/void", { reason_it: "Interrotta." } ]
    }
  end

  setup do
    @finding = ReviewFinding.create!(item_revision: @short, source: "review", severity: "major", field: "prompt", quote: "q", problem_it: "p", fix_it: "f")
    @rejected = GradeProposal.create!(attempt: @attempt, agent_session: @session, points_json: "[]", total: 0, max_total: 2, threshold: 0.6, meets_threshold: false)
    approve_graph_row!
    make_blueprint_approvable!
    ReviewFinding.where(severity: "major").find_each { |f| dispose_in_ledger(f) }
  end

  def dispose_in_ledger(finding)
    Decision.create!(kind: "dispose_finding", subject: @subject, payload_json: { finding_id: finding.id, disposition: "dismissed", reason_it: "ok" }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
  end

  # Release needs consent and the warm-up first, so its case is tried last.
  def prepare_release!
    AppEvent.create!(kind: "warmup_completed", student: @student)
    approve_ui_subject!(@subject, @graph, @blueprint)
    decide("/teacher/consent", { acknowledged: true })
    assert_response :success
  end

  test "every decision route is a 404 on the API and the harness listeners, even with everything right" do
    cases.each do |kind, (path, params)|
      %i[api harness].each do |listener|
        assert_no_difference "Decision.count", "#{kind} on #{listener}" do
          decide(path, params, listener: listener)
        end
        assert_response :not_found, "#{kind} on #{listener}"
        decide(path, params, listener: listener, csrf: false)
        assert_response :not_found, "#{kind} on #{listener} without a token"
      end
    end
  end

  test "every decision route is a 403 when the flag is off" do
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    cases.each do |kind, (path, params)|
      assert_no_difference "Decision.count", kind do
        decide(path, params)
      end
      assert_response :forbidden, kind
    end
    ENV.delete("BANCO_DECISIONS_ENABLED")
    decide(cases["record_consent"].first, { acknowledged: true })
    assert_response :forbidden
  end

  test "every decision route is a 403 without the teacher group, for a user outside the list, for the student and with no identity" do
    token = csrf_token
    {
      "no group" => { "Remote-User" => "nik", "Remote-Groups" => "users" },
      "outside the list" => { "Remote-User" => "mallory", "Remote-Groups" => "banco-teacher" },
      "student" => { "Remote-User" => "student", "Remote-Groups" => "banco-student" },
      "no identity" => {}
    }.each do |label, headers|
      cases.each do |kind, (path, params)|
        assert_no_difference "Decision.count", "#{kind} #{label}" do
          decide(path, params, headers: headers, token: token)
        end
        assert_response :forbidden, "#{kind} #{label}"
      end
    end
  end

  test "a forged teacher identity from a peer that is not the edge proxy is a 403" do
    token = csrf_token
    assert_no_difference "Decision.count" do
      decide(cases["record_consent"].first, { acknowledged: true }, remote_addr: "10.0.0.5", token: token)
    end
    assert_response :forbidden
  end

  test "every decision route is a 403 without a CSRF token or with a wrong one, though the environment disables forgery protection" do
    ActionController::Base.allow_forgery_protection = false
    cases.each do |kind, (path, params)|
      assert_no_difference "Decision.count", kind do
        decide(path, params, csrf: false)
      end
      assert_response :forbidden, "#{kind} without a token"
      assert_no_difference "Decision.count", kind do
        decide(path, params, csrf: false, token: "forged-token")
      end
      assert_response :forbidden, "#{kind} with a forged token"
    end
  end

  test "every decision route is a 403 on the student's computer (cookie banco_device=student)" do
    token = csrf_token
    cookies[:banco_device] = "student"
    cases.each do |kind, (path, params)|
      assert_no_difference "Decision.count", kind do
        decide(path, params, token: token)
      end
      assert_response :forbidden, kind
    end
  end

  test "the student's pages set the banco_device cookie; the teacher's do not" do
    on(:web, "/teacher", headers: TEACHER, remote_addr: EDGE)
    assert_nil cookies[:banco_device]
    on(:web, "/teacher/preview", headers: TEACHER, remote_addr: EDGE)
    assert_nil cookies[:banco_device]
    on(:web, "/diagnosis", headers: { "Remote-User" => "student", "Remote-Groups" => "banco-student" }, remote_addr: EDGE)
    assert_response :success
    assert_not_nil response.headers["Set-Cookie"].to_s[/banco_device=/]
  end

  test "every decision route records a decision with its provenance when everything is right" do
    prepare_release!
    cases.except("record_consent").each do |kind, (path, params)|
      assert_difference -> { Decision.where(kind: kind).count }, 1, kind do
        decide(path, params)
      end
      assert_includes [ 200, 302, 303 ], response.status, "#{kind}: #{response.body}"
      assert_equal kind, json["kind"] if response.status == 200
    end
    Decision.where(kind: DecisionRecorder::KINDS).where("id > ?", 0).find_each do |d|
      next unless d.request_path.start_with?("/teacher")

      assert_equal "nik", d.teacher_login
      assert_equal "banco-teacher", d.groups
      assert_equal EDGE, d.remote_addr
      assert_predicate d.request_id, :present?
    end
  end

  test "a form post is redirected to /teacher" do
    token = csrf_token
    on(:web, "/teacher/consent", method: :post, headers: TEACHER, params: { acknowledged: "1", authenticity_token: token }, remote_addr: EDGE)
    assert_redirected_to "/teacher"
    assert_equal 1, Decision.where(kind: "record_consent").count
  end

  test "the decision row keeps the browser, the path and the request id; the payload is what was decided" do
    token = csrf_token
    on(:web, "/teacher/consent", method: :post, headers: TEACHER.merge("Content-Type" => "application/json", "User-Agent" => "TestBrowser/1", "X-CSRF-Token" => token),
                                 params: { acknowledged: true }.to_json, remote_addr: EDGE)
    decision = Decision.where(kind: "record_consent").sole
    assert_equal "TestBrowser/1", decision.user_agent
    assert_equal "/teacher/consent", decision.request_path
    assert_equal({ "acknowledged" => true, "statement_it" => "" }, JSON.parse(decision.payload_json))
  end

  test "a missing target is a 404 and a decision that is not possible now is a 422 with its reasons" do
    decide("/teacher/findings/999999/disposition", { disposition: "dismissed", reason_it: "x yz" })
    assert_response :not_found
    decide("/teacher/runs/#{@run.id}/void", {})
    assert_response :unprocessable_entity
    assert_includes json["reasons"], "a reason is required"
    decide("/teacher/release", {})
    assert_response :unprocessable_entity
    assert_includes json["reasons"], "the consent is not recorded"
    assert_equal 0, Decision.where(kind: %w[void_diagnosis_run release_diagnosis]).count
  end

  test "a request id seen before is refused, not recorded twice" do
    token = csrf_token
    2.times do
      on(:web, "/teacher/consent", method: :post, headers: TEACHER.merge("Content-Type" => "application/json", "X-Request-Id" => "same-id", "X-CSRF-Token" => token),
                                   params: { acknowledged: true }.to_json, remote_addr: EDGE)
    end
    assert_includes [ 409, 422 ], response.status
    assert_equal 1, Decision.where(kind: "record_consent").count
  end

  test "no API route maps to a decision" do
    api_routes = Rails.application.routes.routes.select { |r| r.path.spec.to_s.start_with?("/api/") }
    assert_not_empty api_routes
    api_routes.each do |route|
      target = "#{route.defaults[:controller]}##{route.defaults[:action]}"
      assert_no_match(/decision/i, target, route.path.spec.to_s)
      assert_no_match(%r{\A/api/v1/(.*/)?(decisions?|approve|release|consent|dispose|confirm|resolve|void|extend|close)\b}, route.path.spec.to_s.sub("(.:format)", ""))
      assert_not route.defaults[:controller].to_s.start_with?("teacher"), route.path.spec.to_s
    end
  end

  test "Decision rows are created only by DecisionRecorder in the application code" do
    offenders = Dir[Rails.root.join("{app,lib,bin,config,db}/**/*.{rb,rake}").to_s].select do |file|
      next false if file.end_with?("app/models/decision_recorder.rb")

      File.read(file).match?(/Decision\.(create|new|insert|upsert|find_or_create)|decisions\.(create|build)|INSERT INTO "?decisions/i)
    end
    assert_empty offenders.map { |f| f.delete_prefix("#{Rails.root}/") }
  end
end
