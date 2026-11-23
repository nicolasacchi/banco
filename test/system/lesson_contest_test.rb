require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# «Per me va bene così» on a check of a lesson/2 (D-396), in Chrome against the real endpoints (the trial student S, and the teacher in /teacher/preview): not before
# the first try, not on a right answer; after a wrong one the button, one comment, «Mandato al docente», the check finished and the way on open. The teacher's
# preview shows no button and writes no comment. The kinds of check are tested alone in lesson_check_kinds_test.rb, the service in
# test/models/lessons/check_contest_test.rb.
class LessonContestSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  BUTTON = "Per me va bene così".freeze

  def lesson_body
    @check_kinds ||= Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/check_kinds.md").read, Validation::Findings.new).body.merge("key" => TOPIC)
  end

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    build_student_world(approve: true, release: true)
    page.driver.resize(390, 800)
  end

  teardown do
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def card_of(component) = stored_body["cards"].find { |c| c["blocks"].any? { |b| b["component"] == component } }["n"]

  def open_lesson(root)
    visit "about:blank"
    visit "#{root}/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 30)
  end

  def go(card)
    page.execute_script("window.lessonApi.goTo(#{card}, { focus: false })")
    assert_selector "article#scheda-#{card}", wait: 10
  end

  test "S sends a wrong answer: the button after the first try only, one comment, «Mandato al docente», the check finished and the way on open" do
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    open_lesson("")
    student = Student.find_by!(key: "prova-1")

    card = card_of("normalized_text")
    go card
    within("#scheda-#{card}") do
      assert_no_button BUTTON # before the first try
      find("input[type=text]").set("nome")
      click_button "Controlla"
      assert_selector ".verdict-wrong"
      assert_text "Pensi di avere ragione?"
      click_button BUTTON
      assert_selector ".verdict-sent", text: "Mandato al docente"
      assert_no_button BUTTON
      assert_selector "form.check.is-done"
      assert_selector ".verdict-explain", text: "Il verbo dice che cosa succede"
      assert_button "Controlla", disabled: true
    end

    comment = Comment.where(student: student).sole
    assert_equal [ "error", "lesson", "card:#{card}/block:#{comment.anchor[/block:(\d+)/, 1]}", "La mia risposta, secondo me giusta: «nome»." ],
                 comment.attributes.values_at("reason", "page_kind", "anchor", "text_it")
    assert_equal 1, LessonEvent.where(student: student, kind: "check_contested").count
    assert_equal [ "wrong" ], LessonEvent.where(student: student, kind: "check_answered").map { |e| e.payload["verdict"] }

    # the way on is open: the next card opens and its check is answered
    other = card_of("tiles")
    go other
    within("#scheda-#{other}") do
      assert_no_button BUTTON
      %w[Marco legge un libro].each { |w| find(".tiles-bank .tile-bank:not(.is-used)", text: w, exact_text: true).click }
      click_button "Controlla"
      assert_selector ".verdict-right", text: "Sì."
      assert_no_button BUTTON # a right answer needs no teacher
    end
    assert_equal 1, Comment.where(student: student).count
    summary = Lessons::Progress.summary(student, @lesson_revision.reload)
    assert_equal [ 2, 1, 1 ], [ summary.checks_answered, summary.checks_contested, summary.first_try_right ]
  end

  test "the teacher's preview shows no button after a wrong answer, and writes no comment" do
    sign_in_as :teacher
    open_lesson("/teacher/preview")
    card = card_of("normalized_text")
    go card
    within("#scheda-#{card}") do
      find("input[type=text]").set("nome")
      click_button "Controlla"
      assert_selector ".verdict-wrong"
      assert_no_button BUTTON
      assert_no_selector ".check-contest"
    end
    assert_equal 0, Comment.count
    assert_equal 0, LessonEvent.where(kind: "check_contested").count
  end
end
