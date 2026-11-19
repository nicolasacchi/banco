require "application_system_test_case"
require_relative "../support/lesson_links_world"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"
require_relative "../support/sitting_answers"
require_relative "../support/changelog_world"
require_relative "../support/english_audit"

# D-364. The student set the app to English (D-356) and wrote «perfetto… ma dà problemi». This walks every page and state of the student's site
# with `language: en`, on a desktop window and on a 390 px phone, and collects what a student would trip on instead of stopping at the first one
# (test/support/english_audit.rb): `translation missing` and raw `%{names}`, Italian chrome (the strings of the Italian locale files that show on a
# page while English is on; the lesson and exercise content is not in them), JavaScript and console errors, CSP violations, text that does not fit
# its button or label at 390 px, a page that scrolls sideways, forms that fail. A part of the walk that cannot go on says why and the next part runs.
# Pages: Oggi, the menu, Materie, a subject, a topic, its lesson (cards, checks, «Prova tu», the lesson's map, settings and menu), the practice
# page (a wrong answer, hints, the solution, «Fai controllare», a typical error, the reminder, «Già fatti»), the entry-test list, a sitting and its
# results, the warm-up, «I miei commenti» and a conversation, the comment box, search, settings (sizes, themes, language, the voices), privacy and account.
class EnglishWalkTest < ApplicationSystemTestCase
  include LessonLinksWorld
  include StudentUiRows
  include SittingAnswers
  include ChangelogWorld
  include StudentSession
  include EnglishAudit

  EDITOR_KEYS = {
    "ed_fraction" => [ "3", "/", "4", :Right ],
    "ed_power" => [ "x", "^", "2", :Right, "+", "3", "x" ],
    "ed_product" => [ "3", "a", "^", "2", :Right, "b" ],
    "ed_square" => [ "(", "a", "+", "b", ")", "^", "2" ],
    "ed_root" => %w[r a d 8],
    "ed_decimal" => [ "0", ",", "7", "5" ],
    "ed_division" => [ "1", "2", ":", "4" ]
  }.freeze
  TYPICAL = "Hai sbagliato un segno.".freeze # the item's own catalogue message, course content (Italian on purpose)

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_student_world(approve: true, release: true)
    @rows = build_ui_subject(key: "italian", name: "Italiano", position: 2, components: %w[number choice ordering matching], sitting_minutes: 120)
    release_diagnosis!
    @student = Student.find_by!(key: "student")
    Diagnosis::Preferences.record(@student, language: "en")
    sign_in_as :student
    audit_setup
    allow_content(stored_body)
  end

  teardown do
    audit_teardown
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  # Each walk is its own test, so that one stays far below the time a system test may take.
  {
    "the pages of the course" => :walk_pages,
    "the lesson" => :walk_lesson,
    "the practice page" => :walk_practice,
    "the end of a topic" => :walk_topic_done,
    "the entry test, a sitting and its results" => :walk_entry_test,
    "the warm-up" => :walk_warmup,
    "comments, search, privacy and account" => :walk_comments_and_info
  }.each do |name, walker|
    { "on a desktop" => :desktop!, "on a 390 px phone" => :phone! }.each do |where, size|
      test "English: #{name}, #{where}" do
        send(size)
        send(walker)
        assert_no_findings
      end
    end
  end

  def italian_subject = en("subjects.display_name_it.italian")

  # ---- settings, Oggi, the menu, Materie, a subject, a topic ---------------------------------------------

  def walk_pages
    section("Settings") do
      visit "/settings"
      assert_selector "html[lang=en]"
      assert_selector "h1", text: en("settings.title")
      assert_selector "legend", text: en("diagnosis.preferences.language")
      check_page "Settings"
      Diagnosis::Preferences::SIZES.each do |size|
        choose en("diagnosis.preferences.sizes.#{size}")
        assert_selector "html[data-size=#{size}]"
        wait_until { Diagnosis::Preferences.for(@student)[:size] == size }
        check_page "Settings, size #{size}"
      end
      choose en("diagnosis.preferences.sizes.normal")
      assert_selector "#settings-status", text: en("settings.saved_now")
      Diagnosis::Preferences::THEMES.each do |theme|
        choose en("diagnosis.preferences.themes.#{theme}")
        assert_selector "html[data-theme-choice=#{theme}]"
        wait_until { Diagnosis::Preferences.for(@student)[:theme] == theme }
        check_page "Settings, theme #{theme}"
      end
      choose en("diagnosis.preferences.themes.cream")
      assert_selector "html[data-theme-choice=cream]"
      choose "English" # the language it is in: nothing reloads, nothing changes
      assert_selector "#settings-status", text: en("settings.saved_now")
      assert_selector "html[lang=en]"
      assert_equal "en", Diagnosis::Preferences.language(@student)
      assert_selector "#voci h2", text: en("lesson2.voices.title")
      assert_selector "#voci p", text: en("lesson2.voices.intro")
      assert_selector "#voci .voice-group, #voci p.hint", wait: 10 # the voices of this device, or the line that there are none
      assert_selector "#settings-info-links a", text: en("privacy.settings_links.account")
      check_page "Settings, the voices"
    end

    section("Oggi") do
      visit "/today"
      assert_selector "html[lang=en]"
      assert_selector "#topbar-title", text: en("student.menu.today"), visible: :all # a phone may hide the bar's title
      assert_selector "h1", text: en("today.title")
      assert_selector "#entry-test-title", text: en("today.entry.title")
      assert_selector "#entry-next", text: en("diagnosis.actions.start")
      assert_selector "#my-path-title", text: en("progress.today.title")
      assert_selector "#course-part-title", text: en("today.suggestions")
      check_page "Today"
    end

    section("The menu") do
      visit "/today"
      find("#student-menu-open").click
      assert_selector "#student-menu-dialog[open]"
      { today: "student.menu.today", subjects: "student.menu.subjects", schemas: "student.menu.schemas", search: "student.menu.search", diagnosis: "student.menu.diagnosis",
        comments: "student.menu.comments", changelog: "student.menu.changelog", settings: "student.menu.settings", account: "student.menu.account", privacy: "student.menu.privacy" }.each do |id, key|
        assert_selector "#menu-#{id}", text: en(key)
      end
      check_page "The menu"
      find("#student-menu-close").click
      assert_no_selector "#student-menu-dialog[open]"
    end

    section("Materie") do
      visit "/subjects"
      assert_selector "h1", text: en("subjects.title")
      assert_selector "li.subject[data-subject=math] .subject-name", text: en("subjects.display_name_it.math")
      assert_selector "li.subject[data-subject=math] .progress-text"
      check_page "Subjects"
    end

    section("A subject") do
      visit "/subjects/math"
      assert_selector "h1", text: en("subjects.display_name_it.math")
      assert_selector "#programme-title", text: en("subject.topics")
      assert_selector "#topic-filter a", text: en("progress.filter_missing")
      check_page "A subject"
      click_link en("progress.filter_missing")
      assert_selector "#topic-filter a[aria-current]", text: en("progress.filter_missing")
      check_page "A subject, only what is missing"
    end

    section("A topic") do
      visit "/topics/#{TOPIC}"
      assert_selector "h1", text: TOPIC_TITLE
      assert_selector "#step-lesson h2", text: en("topic.step_lesson")
      assert_selector "#step-practice h2", text: en("topic.step_practice")
      assert_selector "#lesson-link", text: en("topic.lesson")
      assert_selector "#close-rule", text: en("practice.close_rule")
      assert_selector "#skills .skill a.button", text: en("topic.practise")
      check_page "A topic"
    end

    section("«I didn't understand»") do
      visit "/topics/#{TOPIC}"
      click_button en("question.button")
      assert_selector "form[data-question-target=form]", visible: :visible
      check_page "The question box"
      fill_in en("question.label"), with: "What is the balance for?"
      click_button en("question.send")
      assert_text en("question.sent")
      wait_until { StudentQuestion.count == 1 }
      check_page "The question box, sent"
    end

    # «What's new» (D-375): his own comment first, then the topic approved again; the entries are English, the topic's name stays Italian.
    section("What's new") do
      comment_on(@student, "/topics/#{TOPIC}/lesson", "lesson", at: 2.days.ago, card: 1)
      revise!
      visit "/novita"
      assert_selector "html[lang=en]"
      assert_selector "h1", text: en("changelog.title")
      assert_selector "#changelog-intro", text: en("changelog.intro")
      assert_selector "#changelog-followups h2", text: en("changelog.followups.title")
      assert_selector "#changelog-followups li", text: /Lesson: #{TOPIC_TITLE}, card 1/
      assert_selector "#changelog-entries li[data-entry=my-schemas] h3", text: "My summaries"
      assert_selector "#changelog-updates h4", text: en("changelog.updates.line", topic: TOPIC_TITLE)
      assert_selector "#changelog-updates p", text: en("changelog.updates.note")
      check_page "What's new"
    end

    # «My summaries» and the summary of a topic (D-372): closed first, then open once the topic is done.
    section("My summaries and a summary, closed") do
      visit "/schemas"
      assert_selector "h1", text: en("schemas.title")
      assert_selector "#schemas-intro", text: en("schemas.intro")
      assert_selector ".schemas-locked", text: en("schemas.locked")
      assert_selector ".schemas-locked", text: en("schemas.locked_count", count: 1)
      check_page "My summaries, closed"
      visit "/topics/#{TOPIC}/schema"
      assert_selector "h1", text: en("schemas.page_title", topic: TOPIC_TITLE)
      assert_selector "#schema-locked", text: en("schemas.locked")
      assert_selector "#schema-practice", text: en("schemas.practise")
      check_page "A summary, closed"
    end

    section("My summaries and a summary, open") do
      @clock = Diagnosis::FakeClock.new(Time.current - 20.days)
      play_topic!(@topic_revision, SKILL, 3) # three right answers on three days: the topic is done
      visit "/schemas"
      assert_selector "#schemas-page .schema-link", text: TOPIC_TITLE
      check_page "My summaries, open"
      visit "/subjects/math"
      assert_selector ".schema-row-link", text: en("schemas.topic_link")
      visit "/topics/#{TOPIC}"
      assert_selector "#schema-link", text: en("schemas.topic_link")
      visit "/today"
      assert_selector "#schema-review-title", text: en("schemas.review.title")
      check_page "Today, review a summary"
      find("#schema-review-link").click
      assert_selector "h1", text: en("schemas.page_title", topic: TOPIC_TITLE)
      wait_for_lesson_ready(wait: 30)
      assert_selector "#lesson-root[data-schema] article.l2-card[data-role=summary]", wait: 15
      assert_selector "#schema-lesson", text: en("schemas.reread")
      assert_selector "#schema-practice", text: en("schemas.practise")
      assert_selector "#schema-print", text: en("schemas.print")
      check_page "A summary, open"
    end
  end

  # ---- the lesson ---------------------------------------------------------------------------------------

  def open_lesson(fragment = "")
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#{fragment}"
    wait_for_lesson_ready(wait: 30)
    assert_selector ".l2-cover, .l2-card", wait: 15
  end

  def go_to(n)
    page.execute_script("window.lessonApi.goTo(#{n}, { focus: false })")
    assert_selector "article#scheda-#{n}", wait: 10
    wait_for_lesson_ready(wait: 30)
  end

  def walk_lesson
    cards = stored_body["cards"].map { |card| card["n"] }
    section("The lesson, cover and frame") do
      open_lesson
      assert_selector ".l2-start", text: en("lesson2.start")
      assert_selector ".l2-cover .cover-h", text: en("lesson2.goals")
      assert_selector ".l2-back a", text: en("lesson2.back_to_topic"), visible: :all # folded into the lesson's Menu
      check_page "Lesson, cover"
      { ".l2-mapbtn" => "l2-mapdialog", ".l2-settingsbtn" => "l2-settingsdialog", ".l2-menubtn" => "l2-menudialog" }.each do |button, dialog|
        next unless page.has_selector?(button, wait: 0) # at 1100 px and more the map is the page's side column, not a button

        find(button).click
        assert_selector "dialog.#{dialog}[open]"
        check_page "Lesson, #{dialog}"
        find("dialog.#{dialog}[open] button", text: en("lesson2.close")).click
        assert_no_selector "dialog.#{dialog}[open]"
      end
    end

    section("The lesson, every card") do
      open_lesson
      cards.each do |n|
        go_to(n)
        check_page "Lesson, card #{n}"
      end
    end

    section("The lesson, a check") do
      card, block, check = find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
      open_lesson
      go_to(card)
      shown = ->(stored) { shown_id(@student, card, block, stored) }
      within("article#scheda-#{card} .block-check") do
        find("input[type=radio][value='#{shown.call('a')}']").click
        click_button en("lesson2.check_button")
        assert_selector ".verdict-wrong", text: en("lesson2.wrong")
      end
      check_page "Lesson, a wrong answer"
      within("article#scheda-#{card} .block-check") do
        find("input[type=radio][value='#{shown.call(check['answer'])}']").click
        click_button en("lesson2.check_button")
        assert_selector ".verdict-right", text: en("lesson2.right")
      end
      check_page "Lesson, a right answer"
    end

    section("The lesson, a worked example") do
      ex_card, = find_block { |_, b| b["type"] == "example" }
      _, _, example = find_block { |_, b| b["type"] == "example" }
      blank = example["steps"].find { |s| s["blank"] }["blank"]
      open_lesson
      go_to(ex_card)
      within("article#scheda-#{ex_card} .example") do
        click_button en("lesson2.all_steps")
        assert_selector ".example-note", text: en("lesson2.answer_first")
      end
      check_page "Lesson, a worked example"
      within("article#scheda-#{ex_card} .example") do
        find(".step-blank input.answer-input").set(blank["answer"])
        click_button en("lesson2.check_button")
        assert_selector ".verdict-right"
        assert_selector ".example-result"
      end
      check_page "Lesson, a worked example, answered"
    end

    section("The lesson, «Prova tu»") do
      try_card, = find_block { |_, b| b["type"] == "try" }
      open_lesson
      go_to(try_card)
      assert_selector "article#scheda-#{try_card} li.exercise.is-current"
      check_page "Lesson, the exercises"
      within("article#scheda-#{try_card} li.exercise.is-current") do
        find("input.answer-input").set("5")
        click_button en("lesson2.check_button")
        assert_selector ".verdict-wrong", text: en("lesson2.wrong")
        find("input.answer-input").set("3")
        click_button en("lesson2.check_button")
        assert_selector ".verdict-right", text: en("lesson2.right")
        click_button en("lesson2.show_solution")
        assert_selector ".solution .solution-steps li", count: 3
      end
      check_page "Lesson, the solution of an exercise"
    end

    section("The lesson, the links in the text") do
      open_lesson("#scheda-1")
      assert_selector "article#scheda-1 .unavailable", text: "#{CLOSED_LINK_TEXT} (#{en('lesson2.topic_unavailable')})"
      check_page "Lesson, a link to a topic that is not open"
    end

    section("The lesson, the end box, all the cards, resume") do
      summary = stored_body["cards"].find { |c| c["role"] == "summary" }
      open_lesson
      if summary
        go_to(summary["n"])
        assert_selector "article#scheda-#{summary['n']} .l2-end h3", text: en("lesson2.end_title")
        assert_selector "article#scheda-#{summary['n']} .l2-end a.button", text: en("lesson2.practice")
        check_page "Lesson, the end of the lesson"
      end
      find(".l2-settingsbtn").click
      find("dialog.l2-settingsdialog[open] input[name='s-view'][value='scroll']").click
      find("dialog.l2-settingsdialog[open] button", text: en("lesson2.close")).click
      assert_selector "#lesson-root[data-view=scroll]", wait: 10
      wait_for_lesson_ready(wait: 30)
      check_page "Lesson, all the cards in one column"
      find(".l2-settingsbtn").click
      find("dialog.l2-settingsdialog[open] input[name='s-view'][value='cards']").click
      find("dialog.l2-settingsdialog[open] button", text: en("lesson2.close")).click
      assert_selector "#lesson-root[data-view=cards]", wait: 10
      wait_until { LessonEvent.where(student: @student, kind: "card_seen").exists? }
      open_lesson
      assert_selector ".l2-start", text: en("lesson2.resume", n: "").strip, wait: 10
      check_page "Lesson, the cover with «Resume»"
    end
  end

  # ---- the practice page --------------------------------------------------------------------------------

  def served_serve
    find("[data-practice-target=itemBox]", visible: :all)["data-comment-serve-id"].then { |id| PracticeServe.find(id) }
  end

  def answer_of(serve) = JSON.parse(serve.item_instance.answer_json).to_s

  def walk_practice
    section("Practice") do
      # one exercise is already done, from an earlier day: it is in «Already done» from the start, and the page serves the other one
      done = serve!(student: @student, topic: @topic_revision, skill: SKILL)
      answer!(done, correct_raw(done), student: @student)
      other = (@revisions.map { |revision| revision.item.key } - [ instance_of(done).item_revision.item.key ]).first
      visit "/topics/#{TOPIC}/practice/#{SKILL}?item=#{other}"
      assert_selector "#check:not([disabled])", wait: 30
      assert_selector "#hint-button", text: en("practice.hint", n: 1, total: 3)
      assert_selector "#solution-button", text: en("practice.solution")
      assert_selector "#skip-button", text: en("practice.skip")
      assert_selector ".paper-note", text: en("practice.paper")
      assert_selector "#exercise-list summary", text: en("practice.exercises"), visible: :all
      check_page "Practice"
      first = served_serve
      open_list = -> { page.execute_script("document.querySelector('#exercise-list details').open = true") }
      done_summary = Regexp.new(Regexp.escape(en("practice.done_group", n: 0)).sub("0", "\\d+"))
      open_list.call
      assert_selector "#exercise-list details.exercise-done summary", text: done_summary
      find("#exercise-list details.exercise-done summary").click
      assert_selector "#exercise-list details.exercise-done[open] .exercise-link", minimum: 1
      assert_selector "#exercise-list .exercise-act", text: en("practice.redo"), minimum: 1
      check_page "Practice, the list with «Already done»"

      # a typical error: the item's message, «Try this», and «Remember» on the exercise that follows
      find("input[inputmode=decimal]").set(JSON.parse(first.item_instance.errors_json).first["value"].to_s)
      click_button en("practice.submit")
      assert_selector "#feedback", text: TYPICAL
      assert_selector "#next-actions button", text: en("practice.try_this")
      assert_selector "#next-actions button", text: en("practice.solution")
      check_page "Practice, a typical error"
      click_button en("practice.try_this")
      wait_until { find("[data-practice-target=itemBox]", visible: :all)["data-comment-serve-id"].to_i != first.id }
      assert_selector "#check:not([disabled])", wait: 30
      assert_selector "#serve-reason", text: en("practice.try_this_reason")
      assert_selector "#reminder .reminder-label", text: en("practice.reminder_label")
      assert_selector "#reminder", text: TYPICAL
      check_page "Practice, «Remember»"

      # a wrong answer, a hint, a second wrong answer: the solution, «Fai controllare»
      find("input[inputmode=decimal]").set("99999")
      click_button en("practice.submit")
      assert_selector "#feedback", text: en("practice.unrecognised")
      assert_selector "#hints li", count: 1
      check_page "Practice, a wrong answer"
      click_button en("practice.hint", n: 2, total: 3)
      assert_selector "#hints li", count: 2
      check_page "Practice, two hints"
      find("input[inputmode=decimal]").set("88888")
      click_button en("practice.submit")
      assert_selector "#feedback", text: en("practice.second_wrong")
      assert_selector "#solution h2", text: en("practice.solution_title")
      assert_selector "#next-actions button", text: en("practice.after_solution")
      assert_selector "#feedback .contest-note", text: en("practice.contest_note")
      assert_selector "#feedback #contest-button", text: en("practice.contest_button")
      check_page "Practice, the solution and «Ask for a check»"
      find("#contest-button").click
      assert_selector "#feedback", text: en("practice.contested")
      assert_selector "#next-actions button", text: en("practice.next")
      assert_selector "#next-actions a", text: en("practice.back")
      check_page "Practice, the answer sent to the teacher"

      # another exercise, or the line that the exercises are used up; a right answer if there is one
      click_button en("practice.next")
      wait_until { page.has_selector?("#check:not([disabled])", wait: 0) || page.has_text?(en("practice.exhausted"), wait: 0) }
      if page.has_selector?("#check:not([disabled])", wait: 0)
        check_page "Practice, an exercise again"
        find("input[inputmode=decimal]").set(answer_of(served_serve))
        click_button en("practice.submit")
        assert_selector "#feedback", text: /#{Regexp.escape(en('practice.correct'))}|#{Regexp.escape(en('practice.correct_aided'))}/
        check_page "Practice, a right answer"
      else
        assert_selector "#feedback", text: en("practice.exhausted_note")
        check_page "Practice, the exercises are used up"
      end
    end


    section("Practice, the line that the exercises are used up, and the way back") do
      visit "/topics/#{TOPIC}/practice/#{SKILL}"
      wait_until { page.has_selector?("#check:not([disabled])", wait: 0) || page.has_text?(en("practice.exhausted"), wait: 0) }
      check_page "Practice, on coming back"
    end
  end

  # ---- the end of a topic (D-366) -----------------------------------------------------------------------

  # Three exercises right without help demonstrate the skill: the practice page then says the topic is finished, in English, with the way back to Today.
  # The world has one topic, so there is no next topic to offer; the offer and its button are in the integration and the system test of D-366.
  def walk_topic_done
    section("End of a topic") do
      3.times do
        choice = serve!(student: @student, topic: @topic_revision, skill: SKILL)
        answer!(choice, correct_raw(choice), student: @student)
      end
      visit "/topics/#{TOPIC}/practice/#{SKILL}"
      assert_selector "#topic-done h2", text: en("practice.topic_done.title"), wait: 30
      assert_selector "#topic-done-actions a.button", text: en("practice.topic_done.today")
      assert_selector "#topic-done-extra a.button.secondary[href='/topics/#{TOPIC}/schema']", text: en("practice.topic_done.schema") # D-373
      assert_no_selector "#check", visible: :visible
      check_page "End of a topic"
    end
  end

  # ---- the entry test: the list, a sitting, the results -------------------------------------------------

  def run_row = DiagnosisRun.where(student: @student).order(:sequence).last

  def order_rows(texts)
    texts.each_with_index do |text, target|
      loop do
        shown = all("ol.ordering .row-text").map(&:text)
        position = shown.index(text)
        break if position <= target

        all("ol.ordering li")[position].click_button(en("items.ordering_up"))
      end
    end
  end

  def component_of(event)
    served = ItemServed.find_by!(diagnosis_event_id: event.id)
    JSON.parse(served.item_instance.item_revision.body_json)["component"]
  end

  def answer_in_english
    event = current_event
    served = ItemServed.find_by!(diagnosis_event_id: event.id)
    instance = served.item_instance
    component = JSON.parse(instance.item_revision.body_json)["component"]
    fill_component(component, JSON.parse(instance.display_json), JSON.parse(instance.answer_json))
    click_button en("sitting.send")
    component
  end

  def wait_for_next(count)
    heading = /#{Regexp.escape(en('sitting.header_count', number: 0)).sub('0', (count + 1).to_s)}\z/
    results = -> { page.current_path.to_s.match?(%r{/results\z}) }
    over = -> { page.has_selector?("h1", text: /\A(#{Regexp.escape(en('sitting.sitting_over'))}|#{Regexp.escape(en('sitting.more_to_do'))})\z/, wait: 0) }
    wait_until(60) { results.call || over.call || page.has_selector?("[data-sitting-target=heading]", text: heading, wait: 0.2) }
    results.call ? :results : (over.call ? :over : :item)
  rescue Minitest::Assertion
    status = page.all("[data-sitting-target=status], #leave-confirm", visible: :all).map { |node| node.text(:all) }.join(" | ")
    raise Minitest::Assertion, "after question #{count} no next question and no results: the page is #{page.current_path}, its status lines: #{status.inspect}; visible headings: #{page.all("h1", visible: :visible).map(&:text).inspect}"
  end

  def walk_entry_test
    section("Entry test, the list") do
      visit "/diagnosis"
      assert_selector "h1", text: en("diagnosis.title")
      assert_selector "p", text: en("diagnosis.order_line")
      assert_selector "li.subject[data-subject=italian] .subject-name", text: italian_subject
      assert_selector "li.subject[data-subject=italian] .subject-state", text: en("diagnosis.states.to_do")
      assert_selector "a", text: en("diagnosis.warmup_link")
      check_page "Entry test, the list"
    end

    section("A sitting") do
      visit "/diagnosis"
      click_button en("diagnosis.actions.start")
      assert_selector "h1", text: en("sitting.title", subject: italian_subject)
      assert_selector "#how-it-works h2", text: en("sitting.intro.title")
      assert_selector "#intro-note"
      check_page "Sitting, how it works"
      find("#student-menu #sitting-leave", text: en("student.menu.pause_to_today"))
      click_button en("diagnosis.actions.start")

      count = 0
      missing_seen = false
      state = :item
      while state == :item
        flunk "the subject did not finish" if count > 30
        assert_selector "[data-sitting-target=itemBox] .item-body .answer", wait: 30
        count += 1
        assert_selector "[data-sitting-target=heading]", text: /\A#{Regexp.escape(italian_subject)} · #{Regexp.escape(en('sitting.header_count', number: 0)).sub('0', count.to_s)}\z/
        component = component_of(current_event)
        check_page "Sitting, question #{count} (#{component})"
        if count == 1
          find("#answer-help summary").click
          assert_selector "#answer-help[open] li", minimum: 1
          assert_selector "#answer-help summary", text: en("sitting.help.title")
          check_page "Sitting, «How to answer»"
          if component == "number"
            click_button en("sitting.send")
            assert_selector "[data-sitting-target=status]", text: en("sitting.empty")
            check_page "Sitting, an empty answer"
          end
        end
        if component == "matching" && !missing_seen
          # one row answered, the others not: «Missing» is drawn by the page's CSS from the locale, in the language of the page
          all(".match-row").first.find("select").all("option").find { |o| o.value.present? }.select_option
          click_button en("sitting.send")
          assert_selector ".match-row.missing", minimum: 1
          assert_equal en("items.missing"), page.evaluate_script("getComputedStyle(document.querySelector('.match-row.missing'), '::after').content").to_s.delete('"')
          check_page "Sitting, a matching with rows left empty"
          all(".match-row select").each { |select| select.find("option[value='']").select_option } # an answer taken by a row is greyed out in the others
          missing_seen = true
        end
        if count == 2
          find("[data-sitting-target=unknownButton]").click
        else
          answer_in_english
        end
        state = wait_for_next(count)
      end

      if state == :over
        # the sitting's time is used up: the rest is for another day (the engine's rule), and the results wait for it
        assert_selector "[data-sitting-target=wait] p, [data-sitting-target=over] p", text: /#{Regexp.escape(en('sitting.wait_tomorrow'))}|#{Regexp.escape(en('sitting.more_to_do_text', subject: italian_subject))}/
        assert_selector "a.button", text: en("sitting.back_to_list")
        check_page "Sitting, enough for today"
        next
      end
      @results_reached = true
      assert_current_path %r{/diagnosis/runs/\d+/results}
      assert_selector "h1", text: en("summary.title", subject: italian_subject)
      assert_selector ".closing", text: en("summary.not_a_grade")
      assert_selector "[data-group=known] h2", text: en("summary.known")
      assert_selector "a.button", text: en("summary.see")
      check_page "Results"
      click_link en("summary.see")
      assert_selector "#soluzioni h2", text: en("summary.solutions")
      assert_selector "article.solution", minimum: 1
      assert_selector "article.solution .solution-outcome", text: en("summary.outcome.dont_know")
      check_page "Results, the solutions"
      if page.has_selector?("button[data-action='results#flag']", wait: 2)
        first("button[data-action='results#flag']").click
        assert_selector ".flagged", text: en("summary.flagged"), visible: :visible
        check_page "Results, a flagged answer"
      end
    end

    section("Entry test, the list when done") do
      next unless @results_reached

      visit "/diagnosis"
      assert_selector "li.subject[data-subject=italian] a", text: en("diagnosis.actions.results")
      check_page "Entry test, done"
      visit "/today"
      assert_selector "#entry-all-done, #entry-done", wait: 10
      check_page "Today, the entry test done"
    end
  end

  # ---- the warm-up --------------------------------------------------------------------------------------

  def walk_warmup
    section("Warm-up") do
      visit "/diagnosis/warmup"
      assert_selector "h1", text: en("warmup.title")
      assert_selector "p", text: en("warmup.intro")
      tasks = Diagnosis::Warmup.tasks
      english = I18n.with_locale(:en) { Diagnosis::Warmup.public_tasks }
      assert_text en("warmup.step", n: 1, total: tasks.size)
      assert_selector "[data-warmup-target=itemBox] .prompt p", wait: 20
      check_page "Warm-up, the first task"
      click_button en("warmup.send") # nothing chosen
      assert_text en("warmup.retry")
      find(".option-text", text: "3", exact_text: true).click # wrong: 2 + 2 is 4
      click_button en("warmup.send")
      assert_text en("warmup.retry")
      check_page "Warm-up, a wrong answer"

      tasks.each_with_index do |task, index|
        shown = english.find { |t| t["id"] == task["id"] }
        assert_selector "[data-warmup-target=itemBox] .prompt p", text: shown["prompt_it"], wait: 20
        assert_text en("warmup.step", n: index + 1, total: tasks.size)
        check_page "Warm-up, task #{index + 1} (#{task['id']})"
        warmup_task(task, shown)
        assert_text en("warmup.right"), wait: 20
        assert_no_selector "[data-warmup-target=itemBox] .prompt p", text: shown["prompt_it"], wait: 20 unless index == tasks.size - 1
      end
      assert_text en("warmup.done_title")
      assert_selector "[data-warmup-target=done] a.button", text: en("sitting.back_to_list")
      check_page "Warm-up, done"
    end
  end

  def option_text(shown, id) = %w[options elements left right].flat_map { |k| Array(shown.dig("display", k)) }.find { |e| e["id"] == id }["text"]

  def warmup_task(task, shown)
    case task["component"]
    when "choice" then find(".option-text", text: option_text(shown, task["answer"]), exact_text: true).click
    when "number" then find("input[inputmode=decimal]").set(task["answer"])
    when "fraction"
      all(".fraction input")[0].set(task["answer"]["n"].to_s)
      all(".fraction input")[1].set(task["answer"]["d"].to_s)
    when "ordering" then order_rows(task["answer"].map { |id| option_text(shown, id) })
    when "matching"
      all(".match-row").each do |row|
        left_id = task["display"]["left"].find { |l| l["text"] == row.find("label").text }["id"]
        row.find("select").select(option_text(shown, task["answer"][left_id]))
      end
    when "normalized_text"
      find("input[type=text][lang]").set("pi")
      click_button "ù"
    when "dont_know" then click_button en("warmup.dont_know")
    when "pause"
      click_button en("sitting.pause")
      assert_text en("warmup.paused")
      check_page "Warm-up, paused"
      click_button en("sitting.resume")
    when "expression"
      assert_selector "math-field"
      find("math-field").click
      type_keys(*EDITOR_KEYS.fetch(task["id"]))
      assert_selector ".echo .katex"
    end
    click_button en("warmup.send") unless %w[dont_know pause].include?(task["component"])
  end

  # ---- comments, search, privacy, account ---------------------------------------------------------------

  def walk_comments_and_info
    written = "The second step is unclear."
    section("The comment box") do
      visit "/today"
      find("#comment-open-menu").click
      assert_selector "#comment-banner", visible: :visible
      assert_text en("comments.banner_title")
      assert_selector "#comment-whole", text: en("comments.whole_page")
      assert_selector "#comment-list", text: en("comments.pick_list")
      check_page "Comment mode"
      find("#comment-list").click
      assert_selector "#comment-box[open]", wait: 10
      check_page "The comment box, from a list"
      find("#comment-cancel").click
      assert_no_selector "#comment-box[open]"

      find("#comment-open-menu").click
      find("#comment-whole").click
      assert_selector "#comment-box[open]", wait: 10
      assert_equal en("comments.whole_page"), page.evaluate_script("document.getElementById('comment-where').selectedOptions[0].textContent")
      assert_selector "#comment-box-title", text: en("comments.box_title")
      assert_selector ".comment-chip", count: 5
      find("#comment-send").click
      assert_text en("comments.reason_required")
      check_page "The comment box, no reason"
      choose en("comments.reasons.not_understood")
      fill_in "comment-text", with: written
      assert_text en("comments.chars", n: written.length, max: Comment::TEXT_MAX)
      check_page "The comment box, filled in"
      find("#comment-send").click
      assert_no_selector "#comment-box[open]", wait: 10
      assert_selector "#comment-toast.show", text: en("comments.sent"), wait: 10
      check_page "The comment, sent"
      wait_until { Comment.where(student: @student).count == 1 }
    end

    section("My comments") do
      comment = Comment.where(student: @student).order(:id).last
      CommentEvent.create!(comment: comment, kind: "reply", origin: "web", actor: "nik", request_id: nil, remote_addr: "", payload_json: "{}",
                           text_it: "Guarda la scheda due.", created_at: Time.current)
      visit "/today"
      assert_selector "#comment-replies", text: en("comments.today_line")
      check_page "Today, with a reply"
      find("#student-menu-open").click
      assert_selector "#comments-badge[aria-label='#{en('comments.menu_new', n: 1)}']"
      check_page "The menu, with a reply"
      find("#student-menu-close").click

      visit "/comments"
      assert_selector "h1", text: en("comments.title")
      assert_selector "#reply-window", text: en("comments.reply_within", count: Comments::ReplyWindow.hours)
      Comments::StudentInbox::TABS.each { |tab| assert_selector "#comment-tabs [data-tab=#{tab}]", text: en("comments.inbox.tabs.#{tab}") }
      assert_selector "#comment-#{comment.id} .cm-row-link"
      check_page "My comments"
      visit "/comments?tab=closed"
      assert_selector "#comments-empty", text: en("comments.inbox.empty.closed")
      check_page "My comments, an empty tab"

      visit "/comments"
      find("#comment-#{comment.id} .cm-row-link").click
      assert_selector "#conversation", wait: 10
      assert_selector "#cm-thread-title", text: en("comments.place.today")
      assert_selector "#conversation .comment-state", text: en("comments.state.answered")
      assert_selector ".cm-msg[data-from=teacher] .cm-bubble", text: "Guarda la scheda due."
      assert_selector ".cm-msg[data-from=teacher] .cm-time", text: en("comments.inbox.teacher_name")
      assert_selector ".cm-msg[data-from=student] .comment-reason", text: en("comments.reason.not_understood")
      assert_selector "#comment-place-link", text: en("comments.thread.open_place")
      check_page "A conversation"
      find("#reply-#{comment.id}").send_keys("Thank you, it is clear now.", :enter)
      assert_selector ".cm-msg[data-from=student] .cm-bubble", text: "Thank you, it is clear now.", wait: 10
      assert_no_selector ".cm-msg[data-pending]", wait: 10
      wait_until { comment.events.reload.where(kind: "student_reply").count == 1 }
      check_page "A conversation, a reply sent"
    end

    section("Search") do
      visit "/search"
      assert_selector "h1", text: en("search.title")
      assert_selector "#search-hint", text: en("search.hint")
      assert_selector "#search-q[placeholder='#{en('search.placeholder')}']"
      check_page "Search"
      begin
        Search::Indexer.rebuild!
      rescue StandardError => e
        finding("Search", "the index could not be built for the walk: #{e.class}: #{e.message.lines.first}")
      end
      fill_in "q", with: "equazioni"
      click_button en("search.submit")
      assert_selector "#search-count", text: /\A#{Regexp.escape(en('search.count', count: 1).split.first(2).join(' '))}/
      assert_selector ".search-group h2", minimum: 1
      assert_selector "#search-clear", text: en("search.clear")
      check_page "Search, the results"
      visit "/search?q=zzzzqqqq"
      assert_selector "#search-empty", text: en("search.empty")
      check_page "Search, nothing found"
      visit "/search?q=equazoni"
      check_page "Search, a typo"
      if page.has_selector?("#search-did-you-mean", wait: 2)
        assert_selector "#search-did-you-mean", text: en("search.did_you_mean_html", term: "", options: "").split("«").first.strip
        check_page "Search, «Did you mean»"
      end
    end

    section("Privacy") do
      visit "/privacy"
      assert_selector "h1", text: en("privacy.title")
      assert_selector "#privacy-intro", text: en("privacy.intro")
      assert_selector "#privacy-page h2", minimum: 5
      check_page "Privacy"
    end

    section("Account") do
      visit "/account"
      assert_selector "h1", text: en("account.title")
      assert_selector "#account-intro", text: en("account.intro")
      assert_selector "#account-privacy-link a", text: en("account.privacy_link")
      check_page "Account"
    end
  end
end

# The text layer of the lesson page in English: «Listen» (the card's and the speaker of a word), the glossary, the listen check, the cards that turn,
# the lesson's settings with the voices. The device is the stand-in of lesson_text_system_test.rb (the voices of a Mac, accepted by the test).
class EnglishLessonTextWalkTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession
  include EnglishAudit

  DEVICE = <<~JS.freeze
    (() => {
      const voice = (name, lang, localService = true) => ({ name, lang, localService, default: false, voiceURI: name })
      const voices = [voice("Daniel", "en-GB"), voice("Alice", "it-IT"), voice("Monica", "es-ES")]
      window.__spoken = []
      class Utterance { constructor(text) { this.text = text } }
      const fake = {
        getVoices: () => voices, addEventListener() {}, removeEventListener() {},
        cancel() {}, speak(u) { window.__spoken.push({ text: u.text, voice: u.voice && u.voice.name, lang: u.lang }); window.__utterance = u }
      }
      Object.defineProperty(window, "speechSynthesis", { value: fake, configurable: true })
      window.SpeechSynthesisUtterance = Utterance
    })();
  JS

  AUDIO = <<~JS.freeze
    (() => {
      class FakeAudio {
        constructor() { this.paused = true; this.playbackRate = 1; this.src = "" }
        play() { window.__audio = this; this.paused = false; return Promise.resolve() }
        pause() { this.paused = true }
        removeAttribute(name) { if (name === "src") this.src = "" }
      }
      window.Audio = FakeAudio
    })();
  JS

  ACCEPT = "import('lesson/speech_device').then((m) => { m.configure({ accepted: { it: ['Alice'], en: ['Daniel'], es: ['Monica'] } }); arguments[0](true) })".freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_lesson2_world(name: "text", approve: true, release: true)
    @student = Student.find_by!(key: "student")
    Diagnosis::Preferences.record(@student, language: "en")
    sign_in_as :student
    audit_setup
    allow_content(served_body("text"))
    page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: DEVICE)
    page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: AUDIO)
  end

  teardown do
    audit_teardown
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  { "on a desktop" => :desktop!, "on a 390 px phone" => :phone! }.each do |where, size|
    test "English: the lesson's text layer, #{where}" do
      send(size)
      walk_text_lesson
      assert_no_findings
    end
  end

  def go(n)
    page.execute_script("window.lessonApi.goTo(#{n}, { focus: false })")
    assert_selector "article#scheda-#{n}", wait: 10
    wait_for_lesson_ready(wait: 30)
  end

  def walk_text_lesson
    cards = served_body("text")["cards"].map { |card| card["n"] }
    section("The text lesson, open") do
      visit "about:blank"
      visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
      wait_for_lesson_ready(wait: 30)
      assert_selector ".l2-cover, .l2-card", wait: 15
      page.evaluate_async_script(ACCEPT) # the operator's accepted voices: the speakers show
      check_page "Text lesson, cover"
    end

    section("The text lesson, every card") do
      cards.each do |n|
        go(n)
        check_page "Text lesson, card #{n}"
      end
    end

    section("«Listen» and the speakers") do
      go(1)
      assert_selector "#scheda-1 .card-listen .speak-card", text: en("lesson2.speech.listen")
      assert_selector "#scheda-1 .card-listen .speak-slower", text: en("lesson2.speech.slower")
      assert_selector "#scheda-1 .card-body .block .speak-inline", minimum: 1
      speaker = find("#scheda-1 .card-body .block .speak-inline", match: :first)
      prefix = en("lesson2.speech.listen_text_in", language: "X", text: "Y").split("X").first
      assert speaker["aria-label"].start_with?(prefix), "the speaker's name is #{speaker['aria-label'].inspect}, it should start with #{prefix.inspect}"
      check_page "Text lesson, the speakers"
      find("#scheda-1 .speak-card").click
      assert_selector "#scheda-1 .speak-card[aria-pressed='true']"
      check_page "Text lesson, «Listen» playing"
      page.send_keys(:escape)
      assert_selector "#scheda-1 .speak-card[aria-pressed='false']", wait: 5
    end

    section("The glossary") do
      go(1)
      assert_selector "#scheda-1 .card-glossary h3", text: en("lesson2.gloss.card_title")
      first("#scheda-1 .gloss-btn").click
      assert_selector "#scheda-1 .gloss-pop", visible: :visible
      check_page "Text lesson, a glossary word"
      page.send_keys(:escape)
      assert_no_selector "#scheda-1 .gloss-pop", visible: :visible
    end

    section("The listen check") do
      go(2)
      assert_selector "#scheda-2 .listen-play"
      check_page "Text lesson, the listen check"
      if page.has_selector?("#scheda-2 .listen-show", wait: 1)
        find("#scheda-2 .listen-show").click
        check_page "Text lesson, the text of the listen check"
      end
    end

    section("The cards that turn") do
      go(4)
      page.execute_script("document.querySelectorAll('#scheda-4 [aria-expanded]').forEach((b) => b.click())")
      check_page "Text lesson, the cards turned"
    end

    section("The lesson's settings") do
      go(1)
      find(".l2-settingsbtn").click
      assert_selector "dialog.l2-settingsdialog[open]"
      assert_selector "dialog.l2-settingsdialog label", text: en("lesson2.speech.switch")
      assert_selector "dialog.l2-settingsdialog a", text: en("lesson2.speech.try_voices")
      assert_selector "dialog.l2-settingsdialog legend", text: en("lesson2.settings_labels.view")
      check_page "Text lesson, the settings"
      find("dialog.l2-settingsdialog[open] button", text: en("lesson2.close")).click
    end
  end
end

# The first format of a lesson (lesson/1: sections, «Show the solution» of each exercise, «I didn't understand» under each section) in English.
class EnglishLessonV1WalkTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentSession
  include EnglishAudit

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_student_world(approve: true, release: true)
    @student = Student.find_by!(key: "student")
    Diagnosis::Preferences.record(@student, language: "en")
    sign_in_as :student
    audit_setup
    allow_content(lesson_body)
  end

  teardown do
    audit_teardown
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  { "on a desktop" => :desktop!, "on a 390 px phone" => :phone! }.each do |where, size|
    test "English: the first lesson format, #{where}" do
      send(size)
      section("The sections") do
        visit "/topics/#{TOPIC}/lesson"
        LessonsController::SECTIONS.each { |key| assert_selector "h2", text: en("lesson.sections.#{key}") }
        assert_selector "#section-try h2", text: en("lesson.sections.try")
        assert_selector "#section-try .hint", text: en("lesson.try")
        assert_selector "a", text: en("lesson.back"), minimum: 1
        check_page "Lesson (first format)"
      end
      section("«Show the solution»") do
        visit "/topics/#{TOPIC}/lesson"
        first("button", text: en("lesson.show_solution")).click
        assert_selector "#solution-1", text: "Primo passo"
        check_page "Lesson (first format), a solution"
      end
      section("«I didn't understand» in a section") do
        visit "/topics/#{TOPIC}/lesson"
        within("#section-idea") do
          click_button en("question.button")
          assert_selector "input[type=text]"
        end
        check_page "Lesson (first format), the question box"
      end
      assert_no_findings
    end
  end
end
