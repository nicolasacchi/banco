require "application_system_test_case"
require_relative "../support/student_course_world"
require_relative "../support/student_session"

# The header of the exercise list on the practice page (D-379): «Esercizi» and the line next to it («Questo argomento lo sapevi già», «Argomento fatto»,
# «0 fatti su 3») never overlap and the title keeps its size, in a 215 px column at 1280 px and on a 390 px phone, in Italian and English, for a topic
# known from the entry test and for one done with the exercises (D-378's longer lines had squeezed the title to 11 px and drawn the line over it).
# And the heading the script focuses when the topic is done (tabindex -1) draws no focus ring, while a control reached with the keyboard does.
class PracticeListHeaderTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  KNOWN = PROGRESS_TODO
  KNOWN_SKILL = "math.#{KNOWN.split('.').last}".freeze
  WORDS = {
    "it" => { title: "Esercizi", known: "Questo argomento lo sapevi già", done: "Argomento fatto" },
    "en" => { title: "Exercises", known: "You already knew this topic", done: "Topic done" }
  }.freeze

  # The title, the line and the summary: their boxes and the boxes of their text; the title's width with the line taken away (what it needs on its own).
  MEASURE = <<~JS.freeze
    (() => {
      const title = document.querySelector("#exercise-list-title")
      const line = document.querySelector("#exercise-list [data-practice-target=listCount]")
      const summary = title.closest("summary")
      const box = (e) => { const r = e.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width } }
      const ink = (e) => { const range = document.createRange(); range.selectNodeContents(e); const r = range.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom } }
      const fontSize = parseFloat(getComputedStyle(title).fontSize)
      const kept = line.textContent
      const widthAlone = (line.textContent = "", title.getBoundingClientRect().width)
      line.textContent = kept
      return { fontSize, summaryFontSize: parseFloat(getComputedStyle(summary).fontSize), titleBox: box(title), titleInk: ink(title), lineBox: box(line), lineInk: ink(line), summary: box(summary), widthAlone, text: kept }
    })()
  JS

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    build_progress_world
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    @actor = Student.find_by!(key: "prova-1")
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

  def english! = Diagnosis::Preferences.record(@actor, language: "en")

  # A topic the entry test showed: its skill is seeded as demonstrated and the student never touched it.
  def with_known(&block)
    seeds = { KNOWN_SKILL => Practice::Seed.new(skill: KNOWN_SKILL, state: "demonstrated", at: Time.current - 21.days, run_id: 1, implied: false) }
    Practice::Seeder.stub(:call, seeds, &block)
  end

  # A topic done with the exercises: three right answers without help.
  def finish_topic!
    3.times do
      choice = serve!(student: @actor, topic: @topic_revision, skill: SKILL)
      answer!(choice, correct_raw(choice), student: @actor)
    end
  end

  def assert_header(width, language, kind)
    page.driver.resize(width, 900)
    words = WORDS.fetch(language)
    path = kind == :known ? "/topics/#{KNOWN}/practice/#{KNOWN_SKILL}" : "/topics/#{TOPIC}/practice/#{SKILL}"
    visit path
    assert_selector "html[lang=#{language}]"
    assert_selector "#exercise-list [data-practice-target=listCount]", text: words.fetch(kind), wait: 30
    where = "#{width} px, #{language}, #{kind}"
    m = page.evaluate_script(MEASURE)
    assert_equal words.fetch(:title), page.evaluate_script("document.querySelector('#exercise-list-title').textContent"), where
    assert_in_delta m["summaryFontSize"], m["fontSize"], 0.01, "#{where}: the title keeps the size of the page's text"
    assert_operator m["titleBox"]["width"], :>=, m["widthAlone"] - 0.5, "#{where}: the title keeps the width its words need (#{m['titleBox']['width']} of #{m['widthAlone']})"
    assert_operator m["titleInk"]["right"], :<=, m["titleBox"]["right"] + 0.5, "#{where}: the title's words end inside the title's box"
    ink_overlap = m["titleInk"]["left"] < m["lineInk"]["right"] && m["lineInk"]["left"] < m["titleInk"]["right"] &&
                  m["titleInk"]["top"] < m["lineInk"]["bottom"] && m["lineInk"]["top"] < m["titleInk"]["bottom"]
    assert_not ink_overlap, "#{where}: the title (#{m['titleInk']}) and the line (#{m['lineInk']}) do not overlap"
    box_overlap = m["titleBox"]["left"] < m["lineBox"]["right"] && m["lineBox"]["left"] < m["titleBox"]["right"] &&
                  m["titleBox"]["top"] < m["lineBox"]["bottom"] && m["lineBox"]["top"] < m["titleBox"]["bottom"]
    assert_not box_overlap, "#{where}: the boxes of the title and of the line do not intersect"
    assert_operator m["lineInk"]["right"], :<=, m["summary"]["right"] + 0.5, "#{where}: the line is not cut off by the summary"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "#{where}: no sideways scroll"
  end

  test "the header of the list of a known topic: the title and the line never overlap, at 1280 and 390 px, in Italian and in English" do
    with_known do
      [ "it", "en" ].each do |language|
        Diagnosis::Preferences.record(@actor, language: language)
        [ 1280, 390 ].each { |width| assert_header(width, language, :known) }
      end
    end
  end

  test "the header of the list of a topic done with the exercises: the title and the line never overlap, at 1280 and 390 px, in Italian and in English" do
    finish_topic!
    [ "it", "en" ].each do |language|
      Diagnosis::Preferences.record(@actor, language: language)
      [ 1280, 390 ].each { |width| assert_header(width, language, :done) }
    end
  end

  test "the heading «Hai finito questo argomento!» that the script focuses has no ring; a control reached with the keyboard has one" do
    finish_topic!
    english!
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector "#topic-done h2", text: "You have finished this topic!", wait: 30
    wait = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    sleep 0.1 until page.evaluate_script("document.activeElement && document.activeElement.id") == "topic-done-title" || Process.clock_gettime(Process::CLOCK_MONOTONIC) > wait
    assert_equal "topic-done-title", page.evaluate_script("document.activeElement.id"), "the script focused the heading"
    assert_equal "none", page.evaluate_script("getComputedStyle(document.activeElement).outlineStyle"), "no ring on a heading focused by script"
    type_keys(:Tab)
    active = page.evaluate_script("(() => { const e = document.activeElement; const s = getComputedStyle(e); return { tag: e.tagName, outline: s.outlineStyle, width: parseFloat(s.outlineWidth), focusVisible: e.matches(':focus-visible') } })()")
    assert_equal "A", active["tag"], "Tab goes to the first button of the screen"
    assert active["focusVisible"], "the keyboard focus is a focus-visible one"
    assert_not_equal "none", active["outline"], "the ring stays on a control reached with the keyboard"
    assert_operator active["width"], :>=, 2
    # The ring is drawn for a script focus that follows keyboard use (Chrome's :focus-visible): that is the case the student met.
    page.execute_script("document.getElementById('topic-done-title').focus()")
    assert page.evaluate_script("document.activeElement.id === 'topic-done-title' && document.activeElement.matches(':focus-visible')"), "the heading is focus-visible after keyboard use"
    assert_equal "none", page.evaluate_script("getComputedStyle(document.activeElement).outlineStyle"), "no ring on the heading even then"
  end
end
