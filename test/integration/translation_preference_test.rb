require "test_helper"
require_relative "../support/student_ui_rows"

# The student's choice of the Italian translation (D-402): «Quando la chiedo» (ask, the default) or «Sempre visibile» (always), kept like the
# theme in the student_preference event, put on <html> as data-translation. The teacher's pages and the preview always have it open.
class TranslationPreferenceTest < ActionDispatch::IntegrationTest
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

  def as_student(path, method: :get, params: nil, headers: {}) = on(:web, path, method: method, headers: STUDENT.merge(headers), params: params, remote_addr: EDGE)
  def as_teacher(path, method: :get, params: nil) = on(:web, path, method: method, headers: TEACHER, params: params, remote_addr: EDGE)

  test "the default is ask, with its own reader, and `for` still answers theme and size only" do
    assert_equal "ask", Diagnosis::Preferences.translation(@rows[:student])
    assert_equal %i[theme size], Diagnosis::Preferences.for(@rows[:student]).keys
    as_student "/diagnosis"
    assert_select "html[data-translation=ask]"
  end

  test "the settings page has the two choices, asked by default, and a choice is kept and put on every page" do
    as_student "/settings"
    assert_select "fieldset[data-comment-anchor='setting:translation'] legend", "Traduzione in italiano"
    assert_select "input[name=translation]" do |inputs|
      assert_equal %w[ask always], inputs.map { |i| i["value"] }
    end
    assert_select "input[name=translation][value=ask][checked]"
    assert_select "fieldset[data-comment-anchor='setting:translation'] label span", text: "Quando la chiedo"
    assert_select "fieldset[data-comment-anchor='setting:translation'] label span", text: "Sempre visibile"
    assert_select "input[name=translation]" do |inputs|
      assert(inputs.all? { |i| i["data-action"] == "change->settings#choose" }, "no new script: the existing settings controller saves it at once")
    end

    as_student "/diagnosis/preferences", method: :post, params: { translation: "always" }
    assert_redirected_to "/settings"
    event = AppEvent.where(kind: "student_preference").sole
    assert_equal "always", JSON.parse(event.payload_json)["translation"]
    as_student "/settings"
    assert_select "html[data-translation=always]"
    assert_select "input[name=translation][value=always][checked]"
    as_student "/today"
    assert_select "html[data-translation=always]"
  end

  test "the other preferences keep the translation and the translation keeps the others; an unknown value and an unchanged one write nothing new" do
    as_student "/diagnosis/preferences", method: :post, params: { translation: "always" }
    as_student "/diagnosis/preferences", method: :post, params: { theme: "dark" }
    payload = JSON.parse(AppEvent.where(kind: "student_preference").order(:id).last.payload_json)
    assert_equal %w[dark always], payload.values_at("theme", "translation")
    before = AppEvent.where(kind: "student_preference").count
    as_student "/diagnosis/preferences", method: :post, params: { translation: "sometimes" }
    as_student "/diagnosis/preferences", method: :post, params: { translation: "always" }
    assert_equal before, AppEvent.where(kind: "student_preference").count
    assert_equal "always", Diagnosis::Preferences.translation(@rows[:student])
    as_student "/diagnosis/preferences", method: :post, params: { translation: "ask" }
    assert_equal "ask", Diagnosis::Preferences.translation(@rows[:student])
  end

  test "the JSON reply carries the translation" do
    as_student "/diagnosis/preferences", method: :post, params: { translation: "always" }, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "always", response.parsed_body["translation"]
    assert_equal "cream", response.parsed_body["theme"]
  end

  test "the teacher's pages and the preview always have the translation open, and the preview has no choice of its own" do
    as_teacher "/teacher"
    assert_select "html[data-translation=always]"
    as_student "/diagnosis/preferences", method: :post, params: { translation: "ask" }
    as_teacher "/teacher/preview/today"
    assert_select "html[data-translation=always]"
    as_teacher "/teacher/preview/settings"
    assert_select "input[name=translation]", 0
    before = AppEvent.where(kind: "student_preference").count
    as_teacher "/teacher/preview/preferences", method: :post, params: { translation: "ask", theme: "dark" }
    payload = JSON.parse(AppEvent.where(kind: "student_preference").order(:id).last.payload_json)
    assert_equal "ask", payload["translation"]
    assert_equal before + 1, AppEvent.where(kind: "student_preference").count, "the preview's own theme is recorded for the preview student, not the student's choice"
    assert_equal "ask", Diagnosis::Preferences.translation(@rows[:student])
  end
end
