require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/decision_world"

# D-243: the persistent teacher menu, the breadcrumb and the subject switcher.
class TeacherMenuTest < ActionDispatch::IntegrationTest
  include MultiUser
  include DecisionWorld

  setup do
    build_decision_world
    Subject.find_or_create_by!(key: "english") { |s| s.name_it = "Inglese"; s.position = 2 }
  end

  def page(path, headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  SECTIONS = {
    "/teacher" => "menu-home",
    "/teacher/findings" => "menu-findings",
    "/teacher/corrections" => "menu-corrections",
    "/teacher/students" => "menu-students",
    "/teacher/subjects/math/test" => "menu-subjects"
  }.freeze

  test "every teacher page has the menu with the current section marked" do
    SECTIONS.each do |path, id|
      page(path)
      assert_response :success, path
      assert_select "nav#teacher-menu a#menu-home", "Cruscotto"
      assert_select "#teacher-menu button#menu-subjects", "Materie"
      %w[Rilievi Correzioni Studenti].each { |l| assert_select "#teacher-menu a", text: l }
      assert_select "#teacher-menu [aria-current]", 1, "#{path}: exactly one current item"
      assert_select "#teacher-menu ##{id}[aria-current]", 1, path
    end
  end

  test "the Materie panel lists the subjects with their links and is closed and keyboard ready" do
    page("/teacher")
    assert_select "button#menu-subjects[aria-expanded=false][aria-controls=menu-subjects-panel]"
    assert_select "#menu-subjects-panel[hidden]"
    assert_select "#menu-subjects-panel li[data-menu-subject]", Subject.count
    assert_select "#menu-subjects-panel li[data-menu-subject=math]" do
      %w[Grafo Test Corso Resoconto].each { |l| assert_select "a", text: l }
      assert_select "a[href=?]", "/teacher/subjects/math/test/all", text: "Tutte le domande"
    end
  end

  test "the teacher sees Prova come S, the guest does not, Esci follows the variable" do
    page("/teacher")
    assert_select "#menu-preview"
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    page("/teacher", headers: GUEST)
    assert_select "#teacher-menu a#menu-findings"
    assert_select "#menu-preview", 0
    assert_select "#teacher-menu #logout-link", 0
    ENV["BANCO_LOGOUT_URL"] = "https://auth.example.test/logout"
    page("/teacher")
    assert_select "#teacher-menu a#logout-link[href=?]", "https://auth.example.test/logout", text: "Esci"
  end

  test "the breadcrumb and the switcher per page type" do
    cases = {
      "/teacher/subjects/math/graph" => [ "Grafo", "/teacher/subjects/english/graph" ],
      "/teacher/subjects/math/test" => [ "Test", "/teacher/subjects/english/test" ],
      "/teacher/subjects/math/test/all" => [ "Tutte le domande", "/teacher/subjects/english/test" ],
      "/teacher/subjects/math/test/skills/math.number" => [ "math.number", "/teacher/subjects/english/test" ],
      "/teacher/subjects/math/course" => [ "Corso", "/teacher/subjects/english/course" ],
      "/teacher/subjects/math/report" => [ "Resoconto", "/teacher/subjects/english/report" ],
      "/teacher/subjects/math/practice" => [ "Pratica", "/teacher/subjects/english/practice" ]
    }
    cases.each do |path, (last, switch)|
      page(path)
      next unless response.successful?

      assert_select "nav#breadcrumb li:first-child a", "Cruscotto"
      assert_select "nav#breadcrumb li:nth-child(2)", /#{Regexp.escape(@subject.name_it)}/
      assert_select "nav#breadcrumb [aria-current=page]", 1, path
      assert_select "nav#breadcrumb li:last-child", /#{Regexp.escape(last)}/, path unless last == "math.number"
      assert_select "details#subject-switch summary", "Cambia materia"
      assert_select "details#subject-switch a[href=?]", switch if switch
      assert_select "details#subject-switch [aria-current=page]", @subject.name_it
    end
    page("/teacher")
    assert_select "nav#breadcrumb", 0
    page("/teacher/corrections")
    assert_select "nav#breadcrumb", 0
  end

  test "the skill breadcrumb goes through Test and the switcher falls back to the test of the other subject" do
    page("/teacher/subjects/math/test/skills/math.number")
    assert_response :success
    assert_select "nav#breadcrumb li a[href=?]", "/teacher/subjects/math/test", text: "Test"
    assert_select "details#subject-switch a[href$='/test']"
  end

  test "the findings page lists the open findings of the subjects, in the same tab, and the students page the links" do
    page("/teacher/findings")
    assert_response :success
    assert_select "a[target=_blank]", 0
    page("/teacher/students")
    assert_response :success
    assert_select "section[data-student] li a[href*='/report']", minimum: Subject.count
    assert_select "section[data-student] li a[href*='/practice']", minimum: Subject.count
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    page("/teacher/students", headers: GUEST)
    assert_response :success
    page("/teacher/findings", headers: GUEST)
    assert_response :success
  end
end
