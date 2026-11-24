require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/course_path_world"

# D-328: the teacher's pages as JSON over the API, read-only, for every token role. Each endpoint says what the page says for
# the same world (the invented course of CoursePathWorld); the page is read in the same test and the two are compared.
class TeacherViewsApiTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include CoursePathWorld

  READ_ROLES = %w[bot_read teacher].freeze
  CONTENT_ROLES = %w[agent_claude agent_omp ci].freeze

  setup do
    build_course_path_world
    @major = path_finding!(@ready_items.first)
    # Both reading roles read the same (the content roles are refused, D-327); a teacher token acts as a login on the teacher list (MultiUser lists "nik"), and none needs a session.
    @tokens = (READ_ROLES + CONTENT_ROLES).to_h { |role| [ role, ApiToken.issue!(role: role, label: "views #{role}", expires_at: 30.days.from_now, teacher_login: ("nik" if role == "teacher")) ] }
  end

  def api(path, token: @tokens.fetch("bot_read"))
    headers = token ? { "Authorization" => "Bearer #{token}" } : {}
    on(:api, path, headers: headers)
  end

  def json = response.parsed_body

  def page(path) = on(:web, path, headers: TEACHER, remote_addr: EDGE)

  def topic_path(key = CoursePathWorld::READY, query = "") = "/api/v1/teacher/subjects/math/topics/#{key}#{query}"

  ENDPOINTS = [ "/api/v1/teacher/home", "/api/v1/teacher/subjects/math/course", "/api/v1/teacher/subjects/math/test",
                "/api/v1/teacher/subjects/math/topics/#{CoursePathWorld::READY}" ].freeze

  # ---- who may read ---------------------------------------------------------------------------

  test "no token, a wrong token and a malformed header are refused with E-AUTH" do
    ENDPOINTS.each do |path|
      api(path, token: nil)
      assert_response :unauthorized, path
      assert_equal "E-AUTH", json["code"]
      api(path, token: "bnc_aaaaaaaa_#{'x' * 43}")
      assert_response :unauthorized, path
    end
  end

  test "a content agent's token is refused: these pages hold the third reviewer's opinions and the student's progress (D-327)" do
    ENDPOINTS.each do |path|
      CONTENT_ROLES.each do |role|
        api(path, token: @tokens.fetch(role))
        assert_response :forbidden, "#{role} #{path}"
        assert_equal [ "E-AUTH", "token_role" ], json.values_at("code", "reason")
      end
    end
  end

  test "every role that may read gets the same answer" do
    ENDPOINTS.each do |path|
      bodies = @tokens.slice(*READ_ROLES).map do |role, token|
        api(path, token: token)
        assert_response :success, "#{role} #{path}"
        response.body
      end
      assert_equal 1, bodies.uniq.size, "#{path} differs between roles"
    end
  end

  test "the endpoints are on the API listener only" do
    on(:web, "/api/v1/teacher/home", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
  end

  test "a read changes nothing: no decision, no app event (the page does record that the teacher read it)" do
    assert_no_difference [ "AppEvent.count", "Decision.count", "Comment.count" ] do
      ENDPOINTS.each { |path| api(path) }
      api(topic_path(CoursePathWorld::READY, "?lesson=full"))
      api("/api/v1/teacher/subjects/math/course?only=ready")
    end
    assert_difference "AppEvent.count", 1 do
      page("/teacher/subjects/math/topics/#{CoursePathWorld::READY}")
    end
  end

  # ---- home -----------------------------------------------------------------------------------

  test "home says what the dashboard says: counts, to-dos in order, a row per subject" do
    api("/api/v1/teacher/home")
    body = json
    page("/teacher")
    assert_response :success
    %w[findings corrections topics comments contests].each do |kind|
      assert_equal css_select("li[data-count='#{kind}'] b").first.text.to_i, body["counts"][kind], kind
    end
    assert_equal css_select("#todo-list > li").map { |li| li["data-todo"] }, body["todos"].map { |t| t["kind"].to_s }
    assert_operator body["todos"].size, :>, 0
    row = body["subjects"].find { |s| s["key"] == "math" }
    li = css_select("li.dash-row[data-subject='math']").first
    assert_equal li["data-stage"], row["stage"]
    assert_equal li.css("[data-waiting]").map { |w| w["data-waiting"] }, row["waiting"].map { |w| w["code"].to_s }
    assert(row["waiting"].all? { |w| w["text_it"].present? })
    assert_includes li.at_css("[data-course-line]").text, "Corso: #{row['course']['approved']} approvati su #{row['course']['total']}"
    assert_equal({ "approved" => 1, "total" => 4, "open" => false, "awaiting" => 1, "in_review" => 1, "missing" => 1 }, row["course"])
    assert_equal %w[student prova-1], row["students"].map { |s| s["student"] }
    assert_equal [ true, false ], row["students"].map { |s| s["official"] }
    assert_equal css_select("li[data-student-cell]").size / body["subjects"].size, row["students"].size
  end

  test "home takes ?student=KEY like the page and refuses an unknown key" do
    api("/api/v1/teacher/home?student=prova-1")
    assert_response :success
    assert_equal "prova-1", json["student"]
    api("/api/v1/teacher/home?student=nobody")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    api("/api/v1/teacher/home?student=Bad%20Key")
    assert_response :not_found
  end

  # ---- the course path ------------------------------------------------------------------------

  test "course lists the path as the page does: order, stage, badge, counts, what is missing" do
    api("/api/v1/teacher/subjects/math/course")
    body = json
    page("/teacher/subjects/math/course")
    assert_response :success
    from_page = css_select("ol.path > li").map { |li| [ li["data-topic"], li["data-stage"], li["data-badge"] ] }
    assert_equal from_page, body["topics"].map { |t| [ t["key"], t["stage"], t["badge"] ] }
    assert_equal [ CoursePathWorld::READY, CoursePathWorld::WORKING, CoursePathWorld::MISSING, CoursePathWorld::DONE ], body["topics"].map { |t| t["key"] }
    assert_equal %w[1 2 3 4], body["topics"].map { |t| t["number"].to_s }
    css_select("ol.path > li").each do |li|
      step = body["topics"].find { |t| t["key"] == li["data-topic"] }
      assert_equal li.at_css("[data-stage-label]").text.strip, step["badge_it"]
      missing = li.at_css("[data-missing]")
      missing ? assert_equal(missing.text.strip, step["missing_it"]) : assert_nil(step["missing_it"])
      if step["lesson_written"]
        assert_equal li.at_css("[data-count=findings]")["data-open"].to_i, step["open_findings"]
        assert_equal li.at_css("[data-count=exercises]").text.strip, "#{step['exercises']} esercizi"
      else
        assert_nil li.at_css("[data-count=exercises]")
        assert_equal 0, step["exercises"]
      end
      assert_equal li.css("[data-progress]").map { |p| p["data-progress"] }, step["progress"].map { |p| p["student"] }
    end
    summary = css_select("#course-summary").first
    assert_equal summary["data-ready"].to_i, body["counts"]["ready"]
    assert_equal summary["data-open"] == "true", body["open"]
    assert_equal({ "in_map" => 4, "approved" => 1, "awaiting" => 1, "missing" => 1, "ready" => 1 }, body["counts"])
    assert_equal css_select("#course-release").first["data-releasable"] == "true", body["release"]["releasable"]
    assert_equal css_select("#course-release [data-check]").map { |c| [ c["data-check"], c["data-done"] == "true" ] }, body["release"]["checks"].map { |c| [ c["name"], c["done"] ] }
    assert_equal css_select("#course-skills [data-skill]").map { |s| s["data-skill"] }, body["skills"].map { |s| s["key"] }
  end

  test "course with only=ready keeps the topics that wait for the teacher, as the page filter does" do
    api("/api/v1/teacher/subjects/math/course?only=ready")
    assert_equal [ CoursePathWorld::READY ], json["topics"].map { |t| t["key"] }
    page("/teacher/subjects/math/course?only=ready")
    assert_equal [ CoursePathWorld::READY ], css_select("ol.path > li").map { |li| li["data-topic"] }
  end

  test "a topic outside the programme is listed apart, as the page lists it under Fuori programma" do
    extra = "extra.math.number-curiosities"
    entries = CoursePathWorld::PATH_TOPICS + [ { key: extra, kind: "extra", title_it: "Curiosità sui numeri", skills: [ "math.number" ], minutes: 15, term: 1, after: [] } ]
    build_course_map(subject: @subject, topics: entries)
    api("/api/v1/teacher/subjects/math/course")
    assert_equal [ extra ], json["extra_topics"].map { |t| t["key"] }
    assert_equal [ true ], json["extra_topics"].map { |t| t["extra"] }
    assert_equal 4, json["topics"].size
    page("/teacher/subjects/math/course")
    assert_equal [ extra ], css_select("#course-extra-topics li.path-step").map { |li| li["data-topic"] }
  end

  test "course of a subject with no course map says so, and an unknown subject is E-NOT-FOUND" do
    Subject.create!(key: "geography", name_it: "Geografia", position: 5)
    api("/api/v1/teacher/subjects/geography/course")
    assert_response :success
    assert_equal false, json["present"]
    assert_equal "geography", json.dig("subject", "key")
    api("/api/v1/teacher/subjects/history/course")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
  end

  # ---- one topic ------------------------------------------------------------------------------

  test "topic says what the page says: the exercises in level order with their samples, the findings, the approval" do
    # The page first: opening it records that the teacher read it, and the API then shows the same state.
    page("/teacher/subjects/math/topics/#{CoursePathWorld::READY}")
    assert_response :success
    html = Nokogiri::HTML(response.body)
    api(topic_path)
    body = json
    assert_response :success
    cards = html.css("[data-exercise-card]")
    assert_equal cards.map { |c| c["data-exercise-card"].to_i }, body["exercises"].map { |e| e["revision_id"] }
    assert_equal cards.map { |c| c["data-level"].to_i }, body["exercises"].map { |e| e["level"] }
    assert_equal [ 1, 2, 3 ], body["exercises"].map { |e| e["level"] }
    assert_equal cards.map { |c| c["data-seen"] == "true" }, body["exercises"].map { |e| e["seen"] }
    assert_equal html.css("[data-purpose]").map { |p| p.text.strip }, body["exercises"].map { |e| e["purpose_it"] }
    assert_equal cards.map { |c| c.at_css(".gate")["data-approvable"] == "true" }, body["exercises"].map { |e| e["card"]["gate"]["approvable"] }
    assert_equal 4, body["exercises"].first["samples"].size
    assert_equal html.css("[data-key]").first.text.strip, body["exercises"].first["samples"].first["key"]
    assert_equal html.css("[data-lesson-finding]").map { |f| f["data-lesson-finding"] }, body["findings"]["lesson"].map { |f| f["id"] }
    item_findings = html.css("[data-finding]").map { |f| [ f["data-finding"].to_i, f["data-severity"] ] }
    assert_equal item_findings.sort, body["findings"]["items"].flat_map { |i| i["findings"] }.map { |f| [ f["id"], f["severity"] ] }.sort
    assert_includes item_findings, [ @major.id, "major" ]
    assert_equal @major.problem_it, body["findings"]["items"].flat_map { |i| i["findings"] }.find { |f| f["id"] == @major.id }["problem_it"]
    assert_equal "finding_right", body["findings"]["items"].flat_map { |i| i["findings"] }.find { |f| f["id"] == @major.id }.dig("opinion", "verdict")
    assert_equal html.css("#topic-summary").first["data-approved"] == "true", body["approved"]["latest"]
    assert_equal html.css("#step-approve").first["data-approvable"] == "true", body["approval"]["gate_approvable"]
    checks = html.css("#approve-checks li").map { |li| [ li["data-check"], li["data-done"] == "true" ] }
    assert_equal checks.drop(3).reject { |name, _| name == "other" }, body["approval"]["checks"].map { |c| [ c["name"], c["done"] ] }
    assert_equal %w[read_lesson seen_exercises findings], checks.first(3).map(&:first)
    assert_equal({ "lesson_read" => false, "exercises_seen" => false, "findings_clear" => false, "approved" => false }, body["steps"])
    assert_equal @ready.id, body.dig("latest", "id")
    assert_equal CoursePathWorld::READY, body["key"]
    assert_equal false, body["extra"]
  end

  test "the lesson text comes only with lesson=full" do
    api(topic_path)
    assert_nil json["lesson"]["body"]
    assert_equal "banco.lesson/1", json["lesson"]["schema"]
    api(topic_path(CoursePathWorld::READY, "?lesson=full"))
    assert_equal "banco.lesson/1", json.dig("lesson", "body", "schema")
    assert_kind_of Hash, json.dig("lesson", "body", "sections")
  end

  test "an approved topic and a topic not written" do
    approve_path_topic!(@ready, CoursePathWorld::READY)
    api(topic_path)
    assert_equal true, json["approved"]["latest"]
    assert_equal @ready.id, json["approved"]["revision_id"]
    assert json["steps"]["approved"]
    page("/teacher/subjects/math/topics/#{CoursePathWorld::READY}")
    assert_equal "true", css_select("#topic-summary").first["data-approved"]
    api(topic_path(CoursePathWorld::MISSING))
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    page("/teacher/subjects/math/topics/#{CoursePathWorld::MISSING}")
    assert_response :not_found
    api("/api/v1/teacher/subjects/math/topics/not-a-topic")
    assert_response :not_found
  end

  test "reading the page and the exercises through the browser shows in the API steps" do
    token = csrf_token(headers: TEACHER)
    headers = TEACHER.merge("X-CSRF-Token" => token, "Content-Type" => "application/json", "Accept" => "application/json")
    on(:web, "/teacher/topic-revisions/#{@ready.id}/seen", method: :post, remote_addr: EDGE, params: { part: "lesson" }.to_json, headers: headers)
    on(:web, "/teacher/topic-revisions/#{@ready.id}/seen", method: :post, remote_addr: EDGE, params: { part: "exercise", item_revision_id: @ready_items.first.id }.to_json, headers: headers)
    api(topic_path)
    assert_equal true, json["steps"]["lesson_read"]
    assert_equal [ true, false, false ], json["exercises"].map { |e| e["seen"] }
  end

  # ---- the entry test -------------------------------------------------------------------------

  test "test says what the page says: skills, pinned items, open findings, the gate" do
    api("/api/v1/teacher/subjects/math/test")
    body = json
    assert_response :success
    page("/teacher/subjects/math/test")
    assert_response :success
    assert_equal css_select("li[data-skill]").map { |li| li["data-skill"] }, body["skills"].map { |s| s["skill"] }
    assert_operator body["skills"].size, :>, 1
    assert_equal css_select("[data-open-finding]").map { |li| li["data-open-finding"].to_i }, body["open_findings"].map { |f| f["id"] }
    assert_equal css_select("#test-approve").first["data-approvable"] == "true", body["approval"]["approvable"]
    assert_equal css_select("#open-findings").first["data-open-findings"].to_i, body["open_findings"].size
    assert_equal css_select("#open-findings").first["data-clear-findings"].to_i, body["clear_open_findings"].size
    assert_equal @world[:blueprint].id, body.dig("blueprint", "id")
    assert_equal [ false ], [ body["approved"] ]
    assert_equal body["skills"].sum { |s| s["items"].size }, body.dig("blueprint", "pinned_items")
    first = body["skills"].first["items"].first
    assert_equal [ "item", "revision_id", "seq", "gate", "review", "blind_solve", "findings", "catalogue" ].sort, (first.keys & [ "item", "revision_id", "seq", "gate", "review", "blind_solve", "findings", "catalogue" ]).sort
    assert_equal %w[all-correct all-wrong], body["traces"].map { |t| t["script"] }
    assert_equal body["settings"]["not_measured_it"], css_select("#test-not-measured").first.text.strip
  end

  test "test of a subject with no entry test says so" do
    Subject.create!(key: "geography", name_it: "Geografia", position: 5)
    api("/api/v1/teacher/subjects/geography/test")
    assert_response :success
    assert_equal false, json["present"]
    api("/api/v1/teacher/subjects/history/test")
    assert_response :not_found
  end
end
