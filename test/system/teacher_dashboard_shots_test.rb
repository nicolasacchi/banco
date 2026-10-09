require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/topic_world"
require_relative "../support/student_session"

# Screenshots of the teacher's dashboard with five subjects in different states, so that the several-row layout and the
# order of "Da fare adesso" can be looked at. Only when BANCO_SHOT_DIR names a folder.
class TeacherDashboardShotsTest < ApplicationSystemTestCase
  include DecisionWorld
  include TopicWorld
  include StudentSession

  setup do
    @session = AgentSession.create!(label: "rev", role: "reviewer", agent: "omp", model: "gpt-5.2")
    # math: the test is ready to approve and one topic of the course waits; physics: the graph waits; history: all approved
    # (no work left); chemistry: an open finding; english: nothing written yet.
    @world = build_ui_subject(approve: false, components: %w[number choice])
    @subject = @world[:subject]
    Decision.create!(kind: "approve_skill_graph", subject: @subject, payload_json: { revision_id: SkillGraphRevision.where(subject: @subject).last.id }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "teacher", groups: "banco-teacher", remote_addr: "127.0.0.1")
    make_blueprint_approvable!(@world[:blueprint])
    build_topic_world
    record_viewed!
    build_ui_subject(key: "physics", name: "Fisica", position: 2, approve: false, components: %w[number choice])
    build_ui_subject(key: "history", name: "Storia", position: 3, approve: true, components: %w[number choice])
    chem = build_ui_subject(key: "chemistry", name: "Chimica", position: 4, approve: false, components: %w[number choice])
    revision = chem[:revisions]["number"]
    ReviewFinding.create!(item_revision: revision, source: "blind_solve", blind_solve: BlindSolve.create!(item_revision: revision, agent_session: @session, answers_json: "[]", results_json: "[]"),
                          severity: "blocker", code: "E-BLIND-SOLVE-MISMATCH", instance: 1, field: "instances/1", quote: "x", problem_it: "Non torna.", fix_it: "Controlla.")
    Subject.find_or_create_by!(key: "english") { |s| s.name_it = "Inglese"; s.position = 5 }
    sign_in_as :teacher
  end
  teardown { sign_out_env }

  test "shots" do
    dir = ENV["BANCO_SHOT_DIR"].presence or skip "BANCO_SHOT_DIR is not set"
    prefix = ENV.fetch("BANCO_SHOT_PREFIX", "dashboard")
    [ [ 1366, 900, "1366" ], [ 390, 844, "390" ] ].each do |w, h, label|
      page.driver.resize(w, h)
      visit "/teacher"
      assert_selector "#dashboard[data-dashboard-ready=true]"
      assert_selector "li.dash-row", count: 5
      sleep 0.5
      page.driver.save_screenshot(File.join(dir, "#{prefix}-#{label}.png"), full: true)
    end
  end
end
