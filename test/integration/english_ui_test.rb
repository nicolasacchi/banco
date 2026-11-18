require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-356: the student may choose English for the interface. The chrome (menus, buttons, the messages the code generates) follows the choice;
# the lessons, the exercises and the teacher's words stay Italian; the teacher's pages and the preview are always Italian; Italian stays
# the default and nothing changes for it.
class EnglishUiTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup do
    build_student_world
    @row = Student.find_by!(key: "student")
  end

  def english! = Diagnosis::Preferences.record(@row, language: "en")

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def menu = css_select("nav.student-menu a").map { |a| a.text.squish }

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(headers) = post_json(headers, "/practice/serves", { topic: TOPIC, skill: SKILL })

  def answer_for(headers, serve, raw)
    post_json(headers, "/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: raw, source: "text" })
  end

  def labels_of(selector, attribute) = JSON.parse(css_select(selector).first[attribute])

  # ---- the preference ----------------------------------------------------------------------------------------

  test "the language is Italian until chosen, English is kept with the theme and the size, an unknown one is ignored" do
    assert_equal "it", Diagnosis::Preferences.language(@row)
    assert_equal %w[it en], Diagnosis::Preferences::LANGUAGES
    assert_equal({ theme: "cream", size: "normal" }, Diagnosis::Preferences.for(@row), "`for` still answers theme and size only")

    Diagnosis::Preferences.record(@row, language: "en", theme: "dark")
    assert_equal "en", Diagnosis::Preferences.language(@row)
    Diagnosis::Preferences.record(@row, size: "large")
    Diagnosis::Preferences.record(@row, lesson_view: "scroll")
    assert_equal "en", Diagnosis::Preferences.language(@row), "another choice leaves the language"
    assert_equal({ theme: "dark", size: "large" }, Diagnosis::Preferences.for(@row))

    Diagnosis::Preferences.record(@row, language: "fr")
    Diagnosis::Preferences.record(@row, language: "")
    assert_equal "en", Diagnosis::Preferences.language(@row), "an unknown value is ignored"
    count = AppEvent.where(kind: "student_preference").count
    Diagnosis::Preferences.record(@row, language: "en")
    assert_equal count, AppEvent.where(kind: "student_preference").count, "saying the same again writes nothing"

    Diagnosis::Preferences.record(@row, language: "it")
    assert_equal "it", Diagnosis::Preferences.language(@row)
  end

  test "the settings page offers the two languages, saves the choice and says so in the language chosen" do
    page(OFFICIAL, "/settings")
    assert_select "html[lang=it]"
    assert_select "fieldset legend", "Lingua dell'app"
    assert_select "input[name=language]" do |inputs|
      assert_equal %w[it en], inputs.map { |i| i["value"] }
    end
    assert_select "input[name=language][value=it][checked]"
    assert_select "label", text: "Italiano"
    assert_select "label", text: "English"

    on(:web, "/diagnosis/preferences", method: :post, headers: OFFICIAL, params: { theme: "cream", size: "normal", language: "en" }, remote_addr: EDGE)
    assert_redirected_to "/settings"
    page(OFFICIAL, "/settings")
    assert_select "html[lang=en]"
    assert_select "#settings-saved", "Done. I saved your choice."
    assert_select "h1", "Settings"
    assert_select "fieldset legend", "App language"
    assert_select "input[name=language][value=en][checked]"
    assert_select "label", text: "Italiano", count: 1
    assert_equal "en", Diagnosis::Preferences.language(@row)

    on(:web, "/diagnosis/preferences", method: :post, headers: OFFICIAL, params: { theme: "cream", size: "normal", language: "it" }, remote_addr: EDGE)
    page(OFFICIAL, "/settings")
    assert_select "html[lang=it]"
    assert_select "#settings-saved", "Fatto. Ho salvato la scelta."
  end

  # ---- the student's pages -----------------------------------------------------------------------------------

  test "Italian, the default: the pages are as they were" do
    page(OFFICIAL, "/today")
    assert_select "html[lang=it]"
    assert_select "#topbar-title", "Oggi"
    assert_includes menu, "Impostazioni"
    page(OFFICIAL, "/subjects")
    assert_select "a.subject-name", Subject.find_by!(key: "math")[:name_it], "no English name unless the student asks"
    page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
    assert_select "button#check", "Controlla"
    assert_equal "Controlla", labels_of("main.practice", "data-practice-labels-value")["submit"]
    reply = answer_for(OFFICIAL, serve_for(OFFICIAL), "  ")
    assert_equal Grading::Result.message("empty"), reply["message_it"]
    assert_equal "Scrivi una risposta prima di continuare.", reply["message_it"]
  end

  test "English: Oggi, the menu, the subjects and the settings are English, and <html lang> follows" do
    english!
    page(OFFICIAL, "/today")
    assert_response :success
    assert_select "html[lang=en]"
    assert_select "#topbar-title", "Today"
    assert_select "button#student-menu-open", /Menu/
    assert_includes menu, "Settings"
    assert_includes menu, "My comments"
    refute_includes menu, "Impostazioni"
    assert_select "#course-part-title", "For today"

    page(OFFICIAL, "/subjects")
    assert_select "html[lang=en]"
    assert_select "a.subject-name", "Mathematics"
    page(OFFICIAL, "/subjects/math")
    assert_select "html[lang=en]"
    assert_select "h1", "Mathematics"
    page(OFFICIAL, "/topics/#{TOPIC}")
    assert_select "html[lang=en]"
    assert_select "h1", TOPIC_TITLE, "the topic's title is course content: Italian"
    page(OFFICIAL, "/comments")
    assert_select "html[lang=en]"
    assert_select "h1", "My comments"
    page(OFFICIAL, "/search")
    assert_select "html[lang=en]"
    assert_select "h1", "Search"
    page(OFFICIAL, "/diagnosis/warmup")
    assert_select "html[lang=en]"
  end

  test "English: the lesson page chrome is English and the lesson's text stays Italian" do
    english!
    page(OFFICIAL, "/topics/#{TOPIC}/lesson")
    assert_response :success
    assert_select "html[lang=en]"
    assert_select "a", text: "Back to the topic"
    assert_includes response.body, "Le equazioni servono in quasi ogni"
    assert_includes response.body, "Una equazione è come una bilancia in equilibrio"
    assert_equal I18n.t("lesson.show_solution", locale: :en), labels_of("main.lesson", "data-lesson-labels-value")["show_solution"]
    refute_equal I18n.t("lesson.show_solution", locale: :it), labels_of("main.lesson", "data-lesson-labels-value")["show_solution"]
  end

  test "English: the practice page, its script's labels, and the messages the code generates are English; the exercise stays Italian" do
    english!
    page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
    assert_select "html[lang=en]"
    assert_select "button#check", "Check"
    assert_select ".paper-note", /working is on paper/
    labels = labels_of("main.practice", "data-practice-labels-value")
    assert_equal "Check", labels["submit"]
    assert_equal I18n.t("practice.exercises", locale: :en), labels["exercises"]
    texts = labels_of("main.practice", "data-practice-texts-value")
    assert_equal "Send", texts["send"]
    assert_equal "I don't know", texts["dont_know"]

    serve = serve_for(OFFICIAL)
    assert_equal I18n.t("grading.messages.empty", locale: :en), answer_for(OFFICIAL, serve, "  ")["message_it"]
    wrong = answer_for(OFFICIAL, serve, wrong_raw)
    assert_includes [ I18n.t("practice.unrecognised", locale: :en), I18n.t("practice.unrecognised_no_hint", locale: :en) ], wrong["message_it"]
  end

  test "English: the warm-up's prompts and the words of its matching are English, and no answer reaches the browser" do
    english!
    page(OFFICIAL, "/diagnosis/warmup/tasks")
    tasks = response.parsed_body.fetch("tasks")
    assert_equal "Choose an answer. What is 2 + 2?", tasks.first["prompt_it"]
    matching = tasks.find { |t| t["id"] == "matching" }
    assert_equal %w[four two five one three], matching["display"]["right"].map { |o| o["text"] }
    refute tasks.any? { |t| t.key?("answer") || t.key?("accept") }

    Diagnosis::Preferences.record(@row, language: "it")
    page(OFFICIAL, "/diagnosis/warmup/tasks")
    assert_equal "Scegli una risposta. Quanto fa 2 + 2?", response.parsed_body.fetch("tasks").first["prompt_it"]
  end

  test "English: the lesson 2 chrome is English, the figures' vocabulary stays Italian" do
    helper = Class.new { include LessonPagesHelper }.new
    I18n.with_locale(:en) do
      texts = helper.lesson2_texts
      assert_equal "Back to the topic", texts["back_to_topic"]
      assert_equal "Listen", texts.dig("speech", "listen")
      assert texts.dig("pages", "open").start_with?("Open the interactive part"), "the free page block's button"
      assert_equal I18n.t("lesson_chart.chart_more", locale: :it), texts["chart_more"], "a figure's vocabulary is not translated"
    end
    I18n.with_locale(:it) { assert_equal "Torna all'argomento", helper.lesson2_texts["back_to_topic"] }
  end

  # ---- what stays Italian ------------------------------------------------------------------------------------

  test "the teacher's preview and the teacher's pages are Italian, whatever the preview student or the student chose" do
    english!
    Diagnosis::Preferences.record(Student.current_preview, language: "en")
    page(TEACHER, "/teacher/preview/today")
    assert_response :success
    assert_select "html[lang=it]"
    page(TEACHER, "/teacher/preview/settings")
    assert_select "html[lang=it]"
    assert_select "h1", "Impostazioni"
    assert_select "input[name=language]", 0
    page(TEACHER, "/teacher")
    assert_select "html[lang=it]"
    assert_equal "it", I18n.locale.to_s, "the locale is put back after a request"
  end

  test "a contested answer: the message to the student is English, the comment the teacher reads is Italian" do
    english!
    serve = serve_for(OFFICIAL)
    answer_for(OFFICIAL, serve, wrong_raw)
    body = post_json(OFFICIAL, "/practice/serves/#{serve['serve_id']}/contest", {})
    assert_response :success
    assert_equal "contested", body["status"]
    assert_equal I18n.t("practice.contested", locale: :en), body["message_it"]
    assert_equal "La mia risposta, secondo me giusta: «#{wrong_raw}».", PracticeContest.last.comment.text_it
  end

  test "a subject's name follows the locale, and the search index is built in Italian whatever the locale of the job" do
    chemistry = Subject.new(key: "chemistry", name_it: "Chimica")
    I18n.with_locale(:en) { assert_equal "Integrated science Chemistry", chemistry.name_it }
    assert_not_equal "Integrated science Chemistry", chemistry.name_it

    seen = []
    Search::Builders.stub(:docs, ->(_group) { seen << I18n.locale; [] }) do
      I18n.with_locale(:en) do
        Search::Indexer.reindex(%w[topics])
        assert_equal :en, I18n.locale, "the locale is put back"
      end
    end
    assert_equal [ :it ], seen
  end
end
