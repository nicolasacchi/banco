require "application_system_test_case"
require_relative "../support/student_course_world"
require_relative "../support/student_session"

# The end of a topic (D-366) on a 390 px phone, in Chrome: the last exercise right without help, «Un altro esercizio», the closing screen with
# the next topic and its two buttons, each of which works; the same for a topic known from the first visit, for the teacher in the preview
# (its own addresses) and in English. D-373: after the two buttons, «Vedi lo schema» (a secondary button of 44 px) opens the topic's schema with the
# summary drawn, also in the preview and in English. No sideways scroll, targets of at least 44 px, no console or log error.
class TopicDoneSystemTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  PREVIEW = "/teacher/preview".freeze
  TITLE = "Hai finito questo argomento!".freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    build_progress_world
    page.driver.resize(390, 844)
    @problems = []
    page.driver.browser.page.on("Log.entryAdded") do |params|
      entry = params["entry"] || {}
      @problems << "log #{entry['level']}: #{entry['text']} #{entry['url']}" if %w[error warning].include?(entry["level"]) && entry["source"] != "deprecation" && entry["text"].to_s !~ /favicon/
    end
  end

  teardown do
    assert_empty @problems, "the browser reported problems"
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def as_student
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    @base = ""
    @actor = Student.find_by!(key: "prova-1")
  end

  def as_teacher_in_preview
    ENV["BANCO_STUDENT_USERS"] = ""
    sign_in_as :teacher
    @base = PREVIEW
    @actor = Student.current_preview
  end

  # n exercises right without help for the acting student, straight into the ledger (the page tests the last one).
  def play(topic_revision, skill, count)
    count.times do
      choice = serve!(student: @actor, topic: topic_revision, skill: skill)
      answer!(choice, correct_raw(choice), student: @actor)
    end
  end

  def started_skill = "math.#{PROGRESS_STARTED.split('.').last}"
  def started_revision = @progress_topics.fetch(PROGRESS_STARTED)

  def no_sideways_scroll? = page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    loop do
      return if yield

      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
  end

  # The screen on the page: the title, the offer with the next topic's name, the two buttons and the free slot; nothing about anything else.
  def assert_closing_screen(next_title:, title: TITLE, offer: "Vuoi farne un altro? Eccolo:", next_label: "Vai al prossimo argomento", today_label: "Torna a Oggi", schema_label: "Vedi lo schema")
    assert_selector "#topic-done h2", text: title, wait: 30
    assert_selector "#topic-done-offer", text: "#{offer} #{next_title}"
    assert_selector "#topic-done-actions a.button", count: 2
    assert_selector "#topic-done-actions a.button", text: next_label
    assert_selector "#topic-done-actions a.button", text: today_label
    assert_selector "#topic-done-extra a.button.secondary", count: 1, text: schema_label
    assert_no_selector "#check", visible: :visible
    assert_no_selector "#next-actions", visible: :visible
    assert no_sideways_scroll?, "no sideways scroll with the closing screen"
    2.times do |i|
      box = page.evaluate_script("(() => { const r = document.querySelectorAll('#topic-done-actions a.button')[#{i}].getBoundingClientRect(); return [r.width, r.height, r.right]; })()")
      assert_operator box[1], :>=, 43.9, "button #{i + 1}: a target of at least 44 px"
      assert_operator box[2], :<=, 390, "button #{i + 1}: inside the phone's window"
    end
    schema = page.evaluate_script("(() => { const r = document.querySelector('#topic-done-extra a.button').getBoundingClientRect(); const b = document.querySelector('#topic-done-actions').getBoundingClientRect(); return [r.width, r.height, r.right, r.top - b.bottom]; })()")
    assert_operator schema[1], :>=, 43.9, "«#{schema_label}»: a target of at least 44 px"
    assert_operator schema[2], :<=, 390, "«#{schema_label}»: inside the phone's window"
    assert_operator schema[3], :>=, 0, "«#{schema_label}» is after the two buttons"
  end

  # The schema of the topic (D-372) the link opens: its page, with the summary of the lesson drawn (the world's lessons are the first format).
  def assert_schema_page(topic, base: "", title: "Schema: ")
    assert_current_path "#{base}/topics/#{topic}/schema"
    assert_selector "h1", text: title
    assert_selector "#schema-page[data-unlocked=true]"
    assert_selector "#schema-summary", text: "Un termine che cambia lato cambia segno.", wait: 15
    assert no_sideways_scroll?, "no sideways scroll on the schema"
  end

  def right_answer_on_page
    serve = page.find("[data-practice-target=itemBox]", visible: :all)["data-comment-serve-id"].then { |id| PracticeServe.find(id) }
    find("input[inputmode=decimal]").set(JSON.parse(serve.item_instance.answer_json).to_s)
    click_button "Controlla"
    assert_selector "#feedback", text: "Corretto."
  end

  test "a trial student on a phone: the last exercise right, «Un altro esercizio», the screen, and each button goes where it says" do
    as_student
    play(started_revision, started_skill, 2)
    visit "/topics/#{PROGRESS_STARTED}/practice/#{started_skill}"
    assert_selector "#check:not([disabled])", wait: 30
    assert_no_selector "#topic-done", visible: :visible
    right_answer_on_page
    click_button "Un altro esercizio"
    assert_closing_screen(next_title: TOPIC_TITLE)
    assert_equal "demonstrated", Course::StudentView.new(@actor).state(started_skill).state
    assert_selector "#skill-state", text: "Dimostrata"

    find("#topic-done-actions a.button", text: "Vai al prossimo argomento").click
    assert_current_path "/topics/#{TOPIC}"
    assert_selector "h1", text: TOPIC_TITLE

    visit "/topics/#{PROGRESS_STARTED}/practice/#{started_skill}"
    assert_closing_screen(next_title: TOPIC_TITLE)
    find("#topic-done-extra a.button", text: "Vedi lo schema").click
    assert_schema_page(PROGRESS_STARTED)
    assert_selector "h1", text: "Frazioni"

    visit "/topics/#{PROGRESS_STARTED}/practice/#{started_skill}"
    assert_closing_screen(next_title: TOPIC_TITLE)
    find("#topic-done-actions a.button", text: "Torna a Oggi").click
    assert_current_path "/today"
    assert_selector "#topbar-title", text: "Oggi", visible: :all
  end

  test "a topic known from the start: opening practice on it shows the screen at once, and the list still reaches the exercises" do
    as_student
    play(@topic_revision, SKILL, 3)
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_closing_screen(next_title: "Frazioni")
    served = PracticeServe.where(student: @actor).count

    page.execute_script("document.querySelector('#exercise-list details').open = true")
    assert_selector "#exercise-list details.exercise-done summary", text: /Già fatti \(\d+\)/
    find("#exercise-list details.exercise-done summary").click
    assert_equal served, PracticeServe.where(student: @actor).count, "the screen served nothing"
    find("#exercise-list details.exercise-done .exercise-link", match: :first).click
    assert_selector "#check:not([disabled])", wait: 30
    assert_no_selector "#topic-done", visible: :visible
    assert no_sideways_scroll?, "no sideways scroll on the exercise chosen from the list"
  end

  test "the teacher in the preview, on a phone: the same screen, the buttons go to the preview's own pages" do
    as_teacher_in_preview
    play(started_revision, started_skill, 2)
    visit "#{PREVIEW}/topics/#{PROGRESS_STARTED}/practice/#{started_skill}"
    assert_selector "#check:not([disabled])", wait: 30
    right_answer_on_page
    click_button "Un altro esercizio"
    assert_closing_screen(next_title: TOPIC_TITLE)
    assert_equal [ "#{PREVIEW}/topics/#{TOPIC}", "#{PREVIEW}/today" ], page.all("#topic-done-actions a.button").map { |a| URI(a[:href]).path }
    assert_equal [ "#{PREVIEW}/topics/#{PROGRESS_STARTED}/schema" ], page.all("#topic-done-extra a.button").map { |a| URI(a[:href]).path }

    find("#topic-done-actions a.button", text: "Vai al prossimo argomento").click
    assert_current_path "#{PREVIEW}/topics/#{TOPIC}"
    visit "#{PREVIEW}/topics/#{PROGRESS_STARTED}/practice/#{started_skill}"
    assert_closing_screen(next_title: TOPIC_TITLE)
    find("#topic-done-extra a.button", text: "Vedi lo schema").click
    assert_schema_page(PROGRESS_STARTED, base: PREVIEW)
    visit "#{PREVIEW}/topics/#{PROGRESS_STARTED}/practice/#{started_skill}"
    assert_closing_screen(next_title: TOPIC_TITLE)
    find("#topic-done-actions a.button", text: "Torna a Oggi").click
    assert_current_path "#{PREVIEW}/today"
    assert_equal [ @actor.id ], PracticeServe.where(topic_revision: started_revision).where.not(student_id: Student.find_by!(key: "student").id).pluck(:student_id).uniq
  end

  test "English on a phone: the title, the offer and both buttons are English, the next topic's name stays Italian" do
    as_student
    Diagnosis::Preferences.record(@actor, language: "en")
    play(@topic_revision, SKILL, 3)
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_closing_screen(next_title: "Frazioni", title: "You have finished this topic!", offer: "Want to do another one? Here it is:",
                          next_label: "Go to the next topic", today_label: "Back to Today", schema_label: "See the schema")
    assert_no_text "Hai finito"
    assert_no_text "Torna a Oggi"
    assert_no_text "Vedi lo schema"
    find("#topic-done-extra a.button", text: "See the schema").click
    assert_schema_page(TOPIC, title: "Summary: ")
    assert_selector "#schema-lesson", text: "Read the lesson again"
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_closing_screen(next_title: "Frazioni", title: "You have finished this topic!", offer: "Want to do another one? Here it is:",
                          next_label: "Go to the next topic", today_label: "Back to Today", schema_label: "See the schema")
    find("#topic-done-actions a.button", text: "Back to Today").click
    assert_current_path "/today"
    assert_selector "#topbar-title", text: "Today", visible: :all
  end
end
