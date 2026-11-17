require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/validation_fixtures"

# D-344: Scienze motorie has no entry test, so no blueprint: and until its content is written no graph and no course either. The teacher's pages
# render, say there is no test instead of "Da scrivere", and nothing that counts the entry test waits for it.
class PhysicalEducationPagesTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  KEY = "physical_education".freeze

  setup do
    build_decision_world
    @pe = Subject.create!(key: KEY, name_it: "Scienze motorie", position: 12)
  end

  def page(path, headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  test "the teacher's dashboard shows the subject with no test to write and no diagnosis line" do
    page("/teacher")
    assert_response :success
    assert_select "li.dash-row[data-subject=#{KEY}]" do
      assert_select ".subject-name", "Scienze motorie"
      assert_select "[data-cell=test]", text: /Nessun test d'ingresso/
      assert_select "[data-cell=test] a", 0
      assert_select "[data-cell=students]", text: /Diagnosi non disponibile/, count: 0
      assert_select "[data-cell=course]", text: /Nessuna mappa del corso/
    end
    assert_select "li.dash-row[data-subject=math] [data-cell=test]", text: /Nessun test d'ingresso/, count: 0
    assert_select "[data-todo]", text: /Scienze motorie/, count: 0, message: "nothing waits for a subject with no content"
    assert_select "li[data-menu-subject=#{KEY}] a" do |links|
      hrefs = links.map { |a| a["href"] }
      assert_includes hrefs, "/teacher/subjects/#{KEY}/graph"
      assert_includes hrefs, "/teacher/subjects/#{KEY}/course"
      assert_not_includes hrefs, "/teacher/subjects/#{KEY}/test", "the menu offers no entry test for it"
    end
    assert_select "li[data-menu-subject=math] a[href='/teacher/subjects/math/test']"
  end

  test "the teacher's pages of the subject render with no graph, no blueprint and no course" do
    %w[graph course report].each do |name|
      page("/teacher/subjects/#{KEY}/#{name}")
      assert_response :success, name
    end
    page("/teacher/subjects/#{KEY}/test")
    assert_response :success
    assert_select "main", text: /non ha un test d'ingresso/
    assert_select "#test-approve", 0
    page("/teacher/subjects/#{KEY}/test/all")
    assert_response :not_found
    page("/teacher/subjects/#{KEY}/test/skills/#{KEY}.bones-and-joints")
    assert_response :not_found
  end

  test "its stage is drafting without a graph and approved with the approved graph alone: no blueprint is ever needed" do
    assert_equal "drafting", SubjectStage.for(@pe)[:stage]
    graph = SkillGraphRevision.create!(subject: @pe, seq: 1, body_json: JSON.generate(ValidationFixtures::GRAPH.merge("subject" => KEY)))
    assert_equal "awaiting_teacher", SubjectStage.for(@pe)[:stage], "the graph is in: only the teacher is left"
    Decision.create!(kind: "approve_skill_graph", subject: @pe, payload_json: JSON.generate(revision_id: graph.id), request_id: SecureRandom.hex(4),
                     teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
    assert_equal "approved", SubjectStage.for(@pe)[:stage]
    page("/teacher")
    assert_select "li.dash-row[data-subject=#{KEY}][data-stage=approved]"
    assert_select "li.dash-row[data-subject=#{KEY}] [data-cell=test]", text: /Nessun test d'ingresso/
  end

  test "the release of the diagnosis counts the subjects that have an entry test, and not this one" do
    assert_equal Subject.where.not(key: KEY).count, Teacher::Dashboard.new.release.total
    assert_includes Subject.order(:position).map(&:key), KEY
    assert_not_includes Subject.with_entry_test.map(&:key), KEY, "DecisionRecorder#release_diagnosis asks the graph and the test of these only"
  end

  test "the entry test list, Oggi's block and the report never take it as a test" do
    rows = Diagnosis::Availability.for(@student)
    assert_not_includes rows.map { |r| r.subject.key }, KEY
    report = Diagnosis::Report.call(student: @student)
    assert_not_includes report[:subjects].map { |s| s[:subject] }, KEY
    one = Diagnosis::Report.call(subject: @pe, student: @student)[:subjects].first
    assert_equal [ "not_started", false ], [ one[:status], one[:entry_test][:approved] ]
    page("/teacher/subjects/#{KEY}/report")
    assert_response :success
  end
end
