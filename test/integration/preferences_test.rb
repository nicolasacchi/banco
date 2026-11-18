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
    assert_redirected_to "/settings"
    event = AppEvent.where(kind: "student_preference").sole
    assert_equal @rows[:student].id, event.student_id
    as_student "/settings"
    assert_select "html[data-theme=dark][data-size=larger]"
    assert_select "input[name=theme][value=dark][checked]"
    assert_select "input[name=size][value=larger][checked]"
  end

  test "each of the seven sizes can be chosen and is kept, smallest first on the settings page" do
    assert_equal %w[minimum tiny smallest small normal large larger], Diagnosis::Preferences::SIZES
    as_student "/settings"
    assert_select "input[name=size]" do |inputs|
      assert_equal %w[minimum tiny smallest small normal large larger], inputs.map { |i| i["value"] }
    end
    assert_equal [ "Minimo", "Piccolissimo", "Molto piccolo", "Piccolo", "Normale", "Grande", "Molto grande" ], css_select("fieldset[data-comment-anchor='setting:size'] label span").map(&:text), "D-354: Minimo (12 px) then Piccolissimo (14 px), so «Minimo» no longer looks like «Molto piccolo»"
    assert_select "label", text: "Minimo"
    assert_select "label", text: "Piccolissimo"
    assert_select "label", text: "Molto piccolo"
    assert_select "label", text: "Piccolo"
    %w[minimum tiny smallest small].each do |size|
      as_student "/diagnosis/preferences", method: :post, params: { theme: "cream", size: size }
      as_student "/settings"
      assert_select "html[data-size=#{size}]"
      assert_select "input[name=size][value=#{size}][checked]"
      assert_equal size, Diagnosis::Preferences.for(@rows[:student])[:size]
    end
  end

  test "the lesson dialog texts list the seven sizes, smallest first, and the four themes, and a size chosen there is kept" do
    assert_equal({ "minimum" => "Minimo", "tiny" => "Piccolissimo", "smallest" => "Più piccolo", "small" => "Piccolo", "normal" => "Normale", "large" => "Grande", "larger" => "Più grande" }, I18n.t("lesson2.sizes").transform_keys(&:to_s))
    assert_equal %w[minimum tiny smallest small normal large larger], I18n.t("lesson2.sizes").keys.map(&:to_s)
    assert_equal({ "cream" => "Crema", "light" => "Chiaro", "dark" => "Scuro", "auto" => "Automatico" }, I18n.t("lesson2.themes").transform_keys(&:to_s))
    as_student "/diagnosis/preferences", method: :post, params: { size: "minimum" }
    assert_equal "minimum", Diagnosis::Preferences.for(@rows[:student])[:size]
  end

  test "the four themes are offered and kept; auto is on <html> as the choice with cream until the page's script follows the device (D-350)" do
    assert_equal %w[cream light dark auto], Diagnosis::Preferences::THEMES
    as_student "/settings"
    assert_select "input[name=theme]" do |inputs|
      assert_equal %w[cream light dark auto], inputs.map { |i| i["value"] }
    end
    %w[Crema Chiaro Scuro Automatico].each { |label| assert_select "label", text: label }
    { "light" => "light", "dark" => "dark", "auto" => "cream" }.each do |theme, shown|
      as_student "/diagnosis/preferences", method: :post, params: { theme: theme }
      assert_equal theme, Diagnosis::Preferences.for(@rows[:student])[:theme]
      as_student "/settings"
      assert_select "html[data-theme=#{shown}][data-theme-choice=#{theme}]"
      assert_select "input[name=theme][value=#{theme}][checked]"
    end
    assert_select "script[nonce]", text: /prefers-color-scheme/
  end

  test "a choice on the settings page is posted as it is made: the form carries the endpoint, every radio its action, and «Salva» stays for no script (D-354)" do
    as_student "/settings"
    assert_select "form#preferences[data-controller=settings][data-settings-url-value='/diagnosis/preferences'][data-settings-saved-value=Salvato]"
    assert_select "input[name=theme][data-action='change->settings#choose']", 4
    assert_select "input[name=size][data-action='change->settings#choose']", 7
    assert_select "form#preferences button[type=submit]", "Salva"
    assert_select "#settings-status[role=status][data-settings-target=status]"
    as_student "/diagnosis/preferences", method: :post, params: { size: "tiny" }
    assert_redirected_to "/settings", "the form without a script still saves and goes back"
    as_student "/settings"
    assert_select "html[data-size=tiny]"
    assert_select "input[name=size][value=tiny][checked]"
  end

  test "the script's request is JSON and answers the choice now in force; in the preview it goes to the preview's endpoint" do
    on(:web, "/diagnosis/preferences", method: :post, headers: STUDENT.merge("Accept" => "application/json"), params: { size: "minimum" }, remote_addr: EDGE)
    assert_response :success
    assert_equal "minimum", response.parsed_body["size"]
    assert_equal "minimum", Diagnosis::Preferences.for(@rows[:student])[:size]
    on(:web, "/teacher/preview/settings", headers: TEACHER, remote_addr: EDGE)
    assert_select "form#preferences[data-settings-url-value='/teacher/preview/preferences']"
    on(:web, "/teacher/preview/preferences", method: :post, headers: TEACHER.merge("Accept" => "application/json"), params: { size: "tiny", theme: "dark" }, remote_addr: EDGE)
    assert_response :success
    assert_equal({ "theme" => "dark", "size" => "tiny" }, response.parsed_body.slice("theme", "size"))
    assert_equal "minimum", Diagnosis::Preferences.for(@rows[:student])[:size], "the preview's choice is not the student's"
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

  test "Ascolta is on until the student turns it off, the speed is normal until the student asks for slower, and the choice is kept (D-283)" do
    assert_equal({ lesson_view: "cards", reduce_motion: false, listen: true, slower: false }, Diagnosis::Preferences.lesson(@rows[:student]))
    as_student "/diagnosis/preferences", method: :post, params: { slower: "true" }
    assert_equal({ lesson_view: "cards", reduce_motion: false, listen: true, slower: true }, Diagnosis::Preferences.lesson(@rows[:student]))
    as_student "/diagnosis/preferences", method: :post, params: { listen: "false" }
    assert_equal({ lesson_view: "cards", reduce_motion: false, listen: false, slower: true }, Diagnosis::Preferences.lesson(@rows[:student]), "the other choices stay")
    as_student "/diagnosis/preferences", method: :post, params: { listen: "false" }
    assert_equal 2, AppEvent.where(kind: "student_preference").count, "saying the same again writes nothing"
    assert_equal({ theme: "cream", size: "normal" }, Diagnosis::Preferences.for(@rows[:student]), "theme and size are untouched")
  end
end
