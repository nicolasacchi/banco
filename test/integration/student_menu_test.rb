require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/finished_run"
require_relative "../support/student_course_world"

# D-240: the front door sends each role to its page; Oggi is the student's home with the entry test and the
# course; one menu on every student page, a single "Pausa" item in a sitting, none in the teacher's preview.
class StudentMenuTest < ActionDispatch::IntegrationTest
  include MultiUser
  include FinishedRun
  include StudentCourseWorld

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def labels = css_select("nav.student-menu a").map(&:text)

  def student(key) = Student.create_with(kind: "student").find_or_create_by!(key: key)

  def warmup_done!(student) = AppEvent.create!(kind: "warmup_completed", student: student, payload_json: "{}")

  # ---- the front door ---------------------------------------------------------------------------------

  test "the bare address sends each role to its page" do
    { OFFICIAL => "/today", TRIAL => "/today", TEACHER => "/teacher", GUEST => "/teacher" }.each do |who, target|
      page(who, "/")
      assert_redirected_to target, who["Remote-User"]
    end
    [ UNMAPPED, {} ].each do |who|
      page(who, "/")
      assert_response :not_found
    end
  end

  test "an old link keeps working, and the bare address is a 404 on the other listeners" do
    build_ui_subject
    release_diagnosis!
    page(OFFICIAL, "/diagnosis")
    assert_response :success
    on(:api, "/", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :not_found
  end

  # ---- Oggi: the entry test block ----------------------------------------------------------------------

  test "the diagnosis is not released: the warm-up only, and no entry test in the menu once the warm-up is done" do
    build_ui_subject
    page(OFFICIAL, "/today")
    assert_select "#entry-test[data-state=closed]"
    assert_select "#entry-subjects", 0
    assert_select "#entry-warmup"
    assert_select "#entry-test a.button[href='/diagnosis/warmup']"
    assert_equal [ "Oggi", "Test d'ingresso", "Impostazioni" ], labels
    warmup_done!(student("student"))
    page(OFFICIAL, "/today")
    assert_select "#entry-test", 0
    assert_select "#course-closed"
    assert_equal [ "Oggi", "Impostazioni" ], labels
  end

  test "released: the official student no longer gets the warm-up; a trial student gets it first, then the subjects with one next button" do
    build_ui_subject
    release_diagnosis!
    page(OFFICIAL, "/today")
    assert_select "#entry-test[data-state=open]"
    assert_select "#entry-warmup", 0
    page(TRIAL, "/today")
    assert_select "#entry-warmup"
    assert_select "#entry-test a.button.secondary[href='/diagnosis/warmup']"
    page(OFFICIAL, "/today")
    assert_select "#entry-subjects li.subject[data-subject=math][data-state=not_started] .subject-state", "Da fare"
    assert_select "#entry-next", "Comincia"
    assert_select "form[action='/diagnosis/subjects/math'] #entry-next"
    assert_equal [ "Oggi", "Test d'ingresso", "Impostazioni" ], labels
  end

  test "in progress the button says Riprendi; all done lists the results and no button" do
    rows = build_ui_subject
    release_diagnosis!
    official = student("student")
    warmup_done!(official)
    run = Diagnosis::Conductor.run_for(official, rows[:subject])
    Diagnosis::Conductor.new(run).step!
    page(OFFICIAL, "/today")
    assert_select "#entry-warmup", 0
    assert_select "#entry-subjects li.subject[data-state=in_progress]"
    assert_select "#entry-next", "Riprendi"
    play_run(official, rows[:subject])
    page(OFFICIAL, "/today")
    assert_select "#entry-test[data-state=done]"
    assert_select "#entry-all-done"
    assert_select "#entry-next", 0
    assert_select "#entry-subjects a[href='/diagnosis/runs/#{run.id}/results']"
  end

  test "a trial student has the entry test without any release" do
    build_ui_subject(approve: false)
    page(TRIAL, "/today")
    assert_select "#trial-notice", /Account di prova/
    assert_select "#entry-test[data-state=open] #entry-next"
    assert_includes labels, "Test d'ingresso"
  end

  test "nothing at all: one friendly line" do
    warmup_done!(student("student"))
    page(OFFICIAL, "/today")
    assert_select "#entry-test", 0
    assert_select "#course-part", 0
    assert_select "#course-closed", /niente da fare/
  end

  # ---- Oggi with the course ------------------------------------------------------------------------------

  test "the course part and Materie appear after the release and not before" do
    build_student_world(release: false)
    warmup_done!(@official)
    page(OFFICIAL, "/today")
    assert_select "#course-part", 0
    assert_not_includes labels, "Materie"
    release_course!(@course)
    page(OFFICIAL, "/today")
    assert_select "#course-part li.topic[data-topic='#{TOPIC}']"
    assert_equal [ "Oggi", "Materie", "Impostazioni" ], labels
  end

  test "a trial student sees the course drafts and Materie" do
    build_student_world(approve: false, release: false)
    page(TRIAL, "/today")
    assert_select "#course-part li.topic"
    assert_includes labels, "Materie"
  end

  # ---- the menu ------------------------------------------------------------------------------------------

  test "the full menu on the course, practice, lesson and settings pages, with the current page marked" do
    build_student_world
    { "/today" => "Oggi", "/subjects" => "Materie", "/subjects/math" => "Materie", "/topics/#{TOPIC}" => "Materie",
      "/topics/#{TOPIC}/lesson" => "Materie", "/topics/#{TOPIC}/practice/#{SKILL}" => "Materie", "/settings" => "Impostazioni" }.each do |path, current|
      page(OFFICIAL, path)
      assert_response :success, path
      assert_select "nav.student-menu a", minimum: 3
      assert_select "nav.student-menu a[aria-current=page]", 1, path
      assert_select "nav.student-menu a[aria-current=page]", current, path
    end
  end

  test "the diagnosis pages mark Test d'ingresso as current" do
    build_ui_subject
    release_diagnosis!
    page(OFFICIAL, "/diagnosis")
    assert_select "nav.student-menu a[aria-current=page]", "Test d'ingresso"
    assert_select "h1", "Test d'ingresso"
    page(TRIAL, "/diagnosis/warmup")
    assert_select "nav.student-menu a[aria-current=page]", "Test d'ingresso"
  end

  test "Esci is in the menu only when a logout address is set" do
    page(OFFICIAL, "/today")
    assert_select "a#logout-link", 0
    ENV["BANCO_LOGOUT_URL"] = "https://auth.example.test/logout"
    page(OFFICIAL, "/today")
    assert_select "nav.student-menu a#logout-link[href='https://auth.example.test/logout']", "Esci"
    assert_equal "Esci", labels.last
  end

  test "the settings page holds the preferences, and the diagnosis page no longer does" do
    build_ui_subject
    release_diagnosis!
    page(OFFICIAL, "/settings")
    assert_select "form[action='/diagnosis/preferences'] input[name=theme]", 2
    assert_select "form[action='/diagnosis/preferences'] input[name=size]", 3
    page(OFFICIAL, "/diagnosis")
    assert_select "input[name=theme]", 0
    page(TEACHER, "/settings")
    assert_response :forbidden
  end

  test "in a sitting the menu is the one item Pausa, and the results page has the full menu" do
    rows = build_ui_subject
    release_diagnosis!
    official = student("student")
    run = Diagnosis::Conductor.run_for(official, rows[:subject])
    page(OFFICIAL, "/diagnosis/runs/#{run.id}")
    assert_response :success
    assert_equal [ "Pausa: torna a Oggi" ], labels
    assert_select "nav.student-menu a#sitting-leave[href='/today']"
    assert_select "#leave-confirm[hidden]"
    play_run(official, rows[:subject])
    page(OFFICIAL, "/diagnosis/runs/#{run.id}/results")
    assert_includes labels, "Oggi"
    assert_includes labels, "Impostazioni"
  end

  test "the teacher's preview has no student menu" do
    build_ui_subject
    page(TEACHER, "/teacher/preview")
    assert_response :success
    assert_select "nav.student-menu", 0
    subject = Subject.find_by!(key: "math")
    on(:web, "/teacher/preview/subjects/math", method: :post, headers: TEACHER, remote_addr: EDGE)
    page(TEACHER, URI(response.location).path)
    assert_response :success
    assert_select "nav.student-menu", 0
    assert_select "#preview-close"
    assert_select "#leave-confirm", 0
    assert_equal "math", subject.key
  end
end
