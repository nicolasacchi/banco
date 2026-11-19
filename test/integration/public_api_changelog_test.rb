require "test_helper"
require_relative "../support/changelog_world"
require_relative "../support/public_api_tokens"

# D-375, «Novità» over the API: every token role reads it. audience=teacher (the default) is every entry and every topic approved again with the revision
# ids, and the teacher's reason for the tokens that read the teacher's words; audience=student is what the student reads: his entries and the topics
# his course shows, no reason, no revision id, no decision number, never one of his comments. Read-only.
class PublicApiChangelogTest < ActionDispatch::IntegrationTest
  include ChangelogWorld
  include PublicApiTokens

  PATH = "/api/v1/changelog".freeze
  REASON = "SEGRETO-DEL-DOCENTE: la correzione cambia il segno.".freeze
  ROLES = %w[teacher bot_read agent_claude agent_omp ci].freeze

  setup do
    build_student_world
    @tokens = ROLES.to_h { |role| [ role, issue_token(role) ] }
    @second = travel_to(Time.zone.local(2026, 11, 19, 9, 30)) { revise!(lesson_findings_reason_it: REASON) }
  end

  def get_for(role, query = "") = api_as(@tokens.fetch(role), "#{PATH}#{query}")

  test "every token role reads the teacher's changelog: every entry, and the updates with the two revisions" do
    ROLES.each do |role|
      get_for(role)
      assert_response :success, role
      assert_equal %w[audience content_updates entries], json.keys.sort, role
      assert_equal "teacher", json["audience"]
      assert_equal Changelog::Entries.all.map(&:id), json["entries"].map { |e| e["id"] }, role
      update = json["content_updates"].sole
      assert_equal [ TOPIC, "math", TOPIC_TITLE, @topic_revision.id, @second.id, "2026-11-19" ], update.values_at("topic", "subject", "title_it", "old_revision_id", "new_revision_id", "date"), role
      assert update["decision_id"].is_a?(Integer)
    end
  end

  test "an entry is as the file holds it; the teacher's list names the decisions" do
    get_for("teacher")
    entry = json["entries"].find { |e| e["id"] == "my-schemas" }
    assert_equal({ "id" => "my-schemas", "date" => "2026-11-19", "audience" => [ "student" ], "kind" => "software", "title_it" => "I miei schemi",
                   "body_it" => "Quando finisci un argomento si apre il suo schema, un colpo d'occhio per ricordarlo. Li trovi tutti in «I miei schemi» e li puoi stampare.",
                   "title_en" => "My summaries", "body_en" => entry["body_en"], "link" => "/schemas", "decisions" => [ "D-372" ] }, entry)
    teacher_only = json["entries"].find { |e| e["id"] == "teacher-grading-review" }
    assert_equal [ [ "teacher" ], [ "D-368" ], nil ], [ teacher_only["audience"], teacher_only["decisions"], teacher_only["title_en"] ]
  end

  test "the teacher's reason goes to the tokens that read the teacher's words, not to a content agent's" do
    %w[teacher bot_read].each do |role|
      get_for(role)
      assert_equal REASON, json["content_updates"].sole["reason_it"], role
    end
    %w[agent_claude agent_omp ci].each do |role|
      get_for(role)
      assert_not json["content_updates"].sole.key?("reason_it"), role
      assert_not_includes response.body, "SEGRETO-DEL-DOCENTE", role
    end
  end

  test "audience=student is what the student reads: his entries, the topics his course shows, one line per topic and day, no reason, no ids, no decisions" do
    build_hidden_topic!
    ROLES.each do |role|
      get_for(role, "?audience=student")
      assert_response :success, role
      assert_equal %w[audience content_updates entries student], json.keys.sort
      assert_equal [ "student", "student" ], [ json["audience"], json["student"] ]
      assert_equal Changelog::Entries.for(:student).map(&:id), json["entries"].map { |e| e["id"] }
      assert json["entries"].none? { |e| e.key?("decisions") }, "the student's list names no decision"
      assert_equal [ { "date" => "2026-11-19", "topics" => [ { "topic" => TOPIC, "title_it" => TOPIC_TITLE, "line_it" => "Esercizi o lezione rivisti." } ] } ], json["content_updates"]
      assert_not_includes response.body, HIDDEN_TOPIC
      assert_not_includes response.body, "SEGRETO-DEL-DOCENTE"
      assert_no_match(/old_revision_id|decision_id/, response.body)
    end
  end

  test "student=KEY reads another student's view; an unknown student is 404, and a student with audience teacher is refused" do
    get_for("teacher", "?audience=student&student=prova-1")
    assert_response :success
    assert_equal "prova-1", json["student"]
    get_for("teacher", "?audience=student&student=nessuno")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    get_for("teacher", "?student=student")
    assert_response :unprocessable_entity
    assert_equal [ "E-FILES", "student" ], json.values_at("code", "field")
  end

  test "since keeps the entries from that day and the updates from that day on; a bad value or audience is a 422" do
    get_for("teacher", "?since=2026-11-19")
    assert_equal "2026-11-19", json["since"]
    assert json["entries"].all? { |e| e["date"] >= "2026-11-19" }
    assert_equal 1, json["content_updates"].size
    get_for("teacher", "?since=2026-11-20")
    assert_empty json["content_updates"]
    get_for("teacher", "?since=ieri")
    assert_response :unprocessable_entity
    assert_equal [ "E-FILES", "since" ], json.values_at("code", "field")
    get_for("teacher", "?audience=parent")
    assert_response :unprocessable_entity
    assert_equal "audience", json["field"]
  end

  test "no token is 401, and reading writes nothing" do
    api_as(nil, PATH)
    assert_response :unauthorized
    assert_no_difference [ "Decision.count", "AppEvent.count", "Comment.count" ] do
      get_for("teacher")
      get_for("ci", "?audience=student")
    end
  end

  test "a comment of the student is never in it" do
    comment_on(@official, "/topics/#{TOPIC}", "topic", at: Time.zone.local(2026, 11, 18, 9, 0), text: "PAROLE-DELLO-STUDENTE")
    %w[teacher ci].each do |role|
      get_for(role)
      get_for(role, "?audience=student")
      assert_not_includes response.body, "PAROLE-DELLO-STUDENTE"
      assert_not json.key?("followups")
    end
  end
end
