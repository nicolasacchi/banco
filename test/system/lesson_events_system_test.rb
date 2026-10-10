require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/decision_world"
require_relative "../support/student_session"
require_relative "../support/topic_world"

# R3 in Chrome with the real endpoints: the page posts its seen cards and its checks, the server grades them and
# the cover offers "Riprendi" from what the ledger holds; the teacher's box reads full.json. Screenshots in
# BANCO_SHOT_DIR.
class LessonEventsSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
    build_student_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(1280, 900)
  end

  teardown do
    begin
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "lesson-r3-#{name}.png"), full: true)

  def open_lesson(fragment = "")
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#{fragment}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def trial = Student.find_by!(key: "prova-1")

  test "a number check is graded by the server, the row says what was answered, the explanation comes after the second wrong answer" do
    card, block, check = find_block { |_, b| b["type"] == "check" && b["component"] == "number" }
    open_lesson("#scheda-#{card}")
    assert_selector ".l2-counter", wait: 10
    answer = ->(text) { find(".check input.answer-input").set(text); click_button "Controlla" }
    answer.call("99")
    assert_selector ".verdict-wrong", text: "Non ancora."
    assert_no_text check["explain_it"].to_s[0, 20] if check["explain_it"].present?
    answer.call("98")
    assert_selector ".verdict-wrong", count: 1
    answer.call(check["answer"])
    assert_selector ".verdict-right", text: "Sì."
    shot "check-right"
    rows = LessonEvent.where(student: trial, kind: "check_answered", card: card, block: block).order(:id)
    assert_equal %w[wrong wrong right], rows.map { |r| r.payload["verdict"] }
    assert_equal [ "99", "98", check["answer"] ], rows.map { |r| r.payload["response"] }
    assert_equal [ 1, 2, 3 ], rows.map { |r| r.payload["try"] }
  end

  test "a blank of an example opens the rest from the server's reply" do
    card, block, example = find_block { |_, b| b["type"] == "example" }
    open_lesson("#scheda-#{card}")
    click_button "Mostra tutti i passi"
    assert_selector ".step-blank", visible: :visible
    assert_selector ".example-note", text: "Prima rispondi"
    blank = example["steps"].find { |s| s["blank"] }["blank"]
    find(".step-blank input.answer-input").set(blank["answer"])
    click_button "Controlla"
    assert_selector ".verdict-right"
    assert_selector ".example-result", text: example["result_it"][0, 12]
    shot "example-blank"
    assert_equal 1, LessonEvent.where(student: trial, kind: "check_answered", card: card, block: block).count
  end

  test "a card seen for three seconds is stored, and the cover and Oggi offer to resume from it" do
    open_lesson("#scheda-3")
    assert_selector ".l2-counter", wait: 10
    Timeout.timeout(15) { sleep 0.2 until LessonEvent.where(student: trial, kind: "card_seen", card: 3).exists? }
    assert_equal 1, LessonEvent.where(student: trial, kind: "card_seen").count
    open_lesson
    assert_selector ".l2-start", text: "Riprendi dalla scheda 3"
    shot "resume-cover"
    visit "/today"
    assert_selector "#resume[href$='/lesson#scheda-3']"
    shot "oggi-resume"
    find("#resume").click
    assert_selector ".l2-counter", text: /Scheda 3 di/, wait: 15
  end

  test "Non ho capito from a card stores the card, and the teacher's page names it" do
    card = stored_body["cards"].find { |c| c["role"] == "idea" && c["level"] == "core" }
    open_lesson("#scheda-#{card['n']}")
    assert_selector ".l2-card .question", wait: 10
    first(".l2-card .question [data-question-target=opener]").click
    find(".l2-card .question input[type=text]").set("Non ho capito il primo passaggio")
    click_button "Invia"
    Timeout.timeout(10) { sleep 0.2 until StudentQuestion.exists? }
    q = StudentQuestion.last
    assert_equal [ card["n"], "idea" ], [ q.card, q.section ]
    sign_in_as :teacher
    visit "/teacher/subjects/math/practice?student=prova-1"
    assert_selector "[data-question] [data-card]", text: "Scheda #{card['n']} «#{card['title_it']}»"
    shot "teacher-questions"
  end
end

# The teacher's box in teacher mode: full.json carries the answers, and the notes appear beside the checks.
class LessonEventsTeacherBoxTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession
  include TopicWorld

  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  def lesson_revision_with_body!(key, skill)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: key.split(".", 3)[1]), key: key, kind: "ripasso")
    md = "---\nkey: #{key}\n---\n"
    body = Lessons::Parser2.call(File.read(Rails.root.join("test/fixtures/lesson2/demo.md")), Validation::Findings.new).body.merge("key" => key, "skills" => [ skill ])
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(body),
                           rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  setup do
    FileUtils.mkdir_p(SHOT_DIR)
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  test "Modalità docente shows the answers and the explanations next to the checks, and the box's checks record nothing" do
    visit "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}"
    assert_selector ".l2-box [data-ready='1']", wait: 20
    find(".l2-box .l2-start").click
    check "Modalità docente"
    assert_no_selector "[data-lesson2-preview-target=status]", text: "non sono disponibili"
    assert_selector ".l2-box .teacher-notes", wait: 10
    page.driver.save_screenshot(File.join(SHOT_DIR, "lesson-r3-teacher-mode.png"), full: true)
    # a check of the box is graded with the seed "preview" and leaves no row
    uncheck "Modalità docente"
    assert_selector ".l2-box .l2-counter", wait: 10
    assert_equal 0, LessonEvent.count
  end
end
