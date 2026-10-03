require "test_helper"
require_relative "../support/student_ui_rows"

# The student's theme and text size (B-11): kept on the server, applied to every page
# the student sees, the default cream and normal; the teacher cannot set them for S.
class PreferencesTest < ActionDispatch::IntegrationTest
  include StudentUiRows

  EDGE = ListenerHelpers::EDGE_IP
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze
  TEACHER = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze

  setup do
    @saved = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    ENV["BANCO_TEACHER_USERS"] = "nik"
    @rows = build_ui_subject
    release_diagnosis!
  end

  teardown { %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS].each { |k| @saved.key?(k) ? ENV[k] = @saved[k] : ENV.delete(k) } }

  def as_student(path, method: :get, params: nil) = on(:web, path, method: method, headers: STUDENT, params: params, remote_addr: EDGE)

  test "the default is cream and the normal size, with the font stylesheet and the vendored font" do
    as_student "/diagnosis"
    assert_select "html[data-theme=cream][data-size=normal]"
    assert_select "link[rel=stylesheet][href*=application]"
    assert_includes Rails.root.join("app/assets/stylesheets/application.css").read, "Atkinson Hyperlegible"
  end

  test "a choice is stored on the server and shows on the next page, on any computer" do
    as_student "/diagnosis/preferences", method: :post, params: { theme: "dark", size: "larger" }
    assert_redirected_to "/diagnosis"
    event = AppEvent.where(kind: "student_preference").sole
    assert_equal @rows[:student].id, event.student_id
    as_student "/diagnosis"
    assert_select "html[data-theme=dark][data-size=larger]"
    assert_select "input[name=theme][value=dark][checked]"
    assert_select "input[name=size][value=larger][checked]"
  end

  test "an unknown value is ignored and the old choice stays; saying the same again writes nothing" do
    as_student "/diagnosis/preferences", method: :post, params: { theme: "dark", size: "large" }
    as_student "/diagnosis/preferences", method: :post, params: { theme: "neon", size: "huge" }
    as_student "/diagnosis/preferences", method: :post, params: { theme: "dark", size: "large" }
    assert_equal 1, AppEvent.where(kind: "student_preference").count
    assert_equal({ theme: "dark", size: "large" }, Diagnosis::Preferences.for(@rows[:student]))
  end

  test "the preview and the teacher's pages keep the defaults and the teacher cannot set the student's choice" do
    as_student "/diagnosis/preferences", method: :post, params: { theme: "dark", size: "large" }
    on(:web, "/teacher/preview", headers: TEACHER, remote_addr: EDGE)
    assert_select "html[data-theme=cream][data-size=normal]"
    on(:web, "/diagnosis/preferences", method: :post, headers: TEACHER, params: { theme: "cream" }, remote_addr: EDGE)
    assert_response :forbidden
    assert_equal 1, AppEvent.where(kind: "student_preference").count
  end
end
