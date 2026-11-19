require "application_system_test_case"
require_relative "../support/changelog_world"
require_relative "../support/student_session"

# D-378, in Chrome on a 390 px phone: «Novità» with a crowd of revisions like the real one is short, no page scrolls sideways at the largest text size
# in either language (tags and pills wrap), the dot on «Menu» does not cover a letter, and the comment picker bar goes away when the box opens.
class StudentUxPhoneTest < ApplicationSystemTestCase
  include ChangelogWorld
  include StudentSession

  # Today's data, in small: 40 more topics, 12 comments on 5 of them, every topic revised on three of the last days, 7 of them started.
  CROWD = 40
  LIMIT_PX = 3000

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_progress_world
    page.driver.resize(390, 844)
  end

  teardown do
    if @saved_entries_path
      Changelog::Entries.path = @saved_entries_path
      Changelog::Entries.reset!
    end
    begin
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def build_crowd!
    keys = Array.new(CROWD) { |i| format("lezione.math.folla-%02d", i + 1) }
    topics = [ { key: TOPIC, kind: "ripasso", title_it: TOPIC_TITLE, skills: [ SKILL ], minutes: 30, term: 1, after: [] } ] +
             keys.each_with_index.map { |key, i| { key: key, kind: "lezione", title_it: "Argomento di prova numero #{i + 1}: un titolo lungo che va a capo", skills: [], minutes: 20, term: 1, after: [] } }
    course = build_course_map(skills: [], topics: topics)
    @crowd = keys.to_h do |key|
      lesson = Lesson.create!(subject: @subject, key: key, kind: "lezione")
      lr = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: Digest::SHA256.hexdigest(key), rules_version: Validation::Rules.version.to_s,
                                  warnings_json: "[]", body_json: JSON.generate(lesson_body.merge(key: key, kind: "lezione")))
      tr = TopicRevision.create!(lesson: lesson, seq: 1, course_revision: course, lesson_revision: lr, body_json: JSON.generate(schema: "banco.topic/1", key: key, practice: []))
      approve_topic!(tr)
      [ key, tr ]
    end
    release_course!(course)
    keys.first(7).each { |key| make_practice_event(@official, "lesson_opened", topic_revision: @crowd[key], lesson_revision: @crowd[key].lesson_revision) }
    keys.first(5).each_with_index { |key, i| (i < 2 ? 3 : 2).times { comment_on(@official, "/topics/#{key}/lesson", "lesson", at: 6.days.ago, card: 1) } }
    [ 3, 2, 1 ].each { |days| travel_to(days.days.ago) { @crowd.each_value { |tr| revise!(tr) } } }
    travel_to(30.days.ago) { @crowd.each_value { |tr| revise!(tr) } }
  end

  def height = page.evaluate_script("document.documentElement.scrollHeight")
  def no_sideways_scroll(where) = assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "#{where}: the page scrolls sideways"

  # D-379: the height of «Novità» is a measure of the crowd of revisions, not of how many entries the real changelog holds today (every entry newer than the
  # student's last visit is shown in full, so each new one made the page longer and the bound had to be raised). The file here holds as many as D-378 had.
  def use_entries!(count)
    dir = Dir.mktmpdir
    path = File.join(dir, "changelog.yml")
    lines = Array.new(count) do |i|
      day = Date.new(2026, 11, 10) + (i % 9)
      "  - {id: crowd-entry-#{i}, date: #{day.iso8601}, audience: [student], kind: software, title_it: \"Una novità numero #{i}\", body_it: \"#{'Una frase di prova abbastanza lunga per fare altezza, ' * 2}fine.\", " \
        "title_en: \"A piece of news number #{i}\", body_en: \"#{'A test sentence that is long enough to take some height, ' * 2}end.\"}"
    end
    File.write(path, "entries:\n#{lines.join("\n")}\n")
    @saved_entries_path = Changelog::Entries.path
    Changelog::Entries.path = path
    Changelog::Entries.reset!
  end

  def set_size(size, language)
    Diagnosis::Preferences.record(@official, size: size, language: language)
  end

  test "«Novità» on a phone with a crowd of revisions stays under 3000 px, with his comments one card per topic and the other topics folded" do
    build_crowd!
    use_entries!(8)
    sign_in_as :student
    visit "/novita"
    assert_selector "h1", text: "Novità", wait: 10
    assert_selector "#changelog-followups li", count: 5
    assert_selector "#changelog-followups li[data-count='3']", count: 2
    assert_text "3 commenti"
    assert_selector "details.changelog-others", count: 3
    assert_text(/Altri \d+ argomenti aggiornati/)
    assert_no_selector "details.changelog-others[open]"
    assert_selector "#changelog-older:not([open])"
    px = height
    puts "novita height at 390 px, size normal: #{px} px"
    assert_operator px, :<, 6000, "the page was about 30 000 px before D-378"
    set_size("minimum", "it")
    visit "/novita"
    assert_selector "h1", text: "Novità", wait: 10
    px = height
    puts "novita height at 390 px, his own size (minimum): #{px} px"
    assert_operator px, :<, LIMIT_PX
    no_sideways_scroll("/novita")
  end

  test "at the largest text size no page scrolls sideways at 390 px, in Italian and English: tags wrap inside their card" do
    seeds = { "math.#{PROGRESS_TODO.split('.').last}" => Practice::Seed.new(skill: "math.#{PROGRESS_TODO.split('.').last}", state: "to_recover", at: 20.days.ago, run_id: 1, implied: false) }
    Practice::Seeder.stub(:call, seeds) do
      sign_in_as :student
      %w[it en].each do |language|
        %w[larger large normal].each do |size|
          set_size(size, language)
          [ "/subjects", "/subjects/math", "/today", "/novita", "/schemas", "/topics/#{TOPIC}", "/settings" ].each do |path|
            visit path
            assert_selector "h1", wait: 10
            no_sideways_scroll("#{path} (#{language}, #{size})")
          end
        end
      end
      set_size("larger", "en")
      visit "/subjects/math"
      assert_selector "li.topic .pill", text: "From the test: to review", wait: 10
      inside = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("li.topic .pill")).every((p) => { const r = p.getBoundingClientRect(), l = p.closest("li.topic").getBoundingClientRect(); return r.left >= l.left - 1 && r.right <= l.right + 1 })
      JS
      assert inside, "every tag is inside its row"
    end
  end

  test "a long pill wraps inside its border" do
    sign_in_as :student
    visit "/today"
    assert_selector "h1", wait: 10
    page.execute_script(<<~JS)
      const host = document.createElement("div"); host.id = "probe"; host.style.cssText = "width: 12rem"
      host.innerHTML = '<span class="pill info">Ora siamo qui: x vale 20 e continua ancora un poco</span>'
      document.querySelector("main").prepend(host)
    JS
    fits = page.evaluate_script(<<~JS)
      (() => { const host = document.getElementById("probe").getBoundingClientRect(), p = document.querySelector("#probe .pill"); const r = p.getBoundingClientRect()
        return r.right <= host.right + 1 && p.scrollWidth <= p.clientWidth + 1 })()
    JS
    assert fits, "the text stays inside the pill"
  end

  test "the dot on «Menu» sits beside the word, not over a letter" do
    revise!
    sign_in_as :student
    visit "/today"
    assert_selector "#student-menu-open .menu-dot", visible: :all, wait: 10
    clear = page.evaluate_script(<<~JS)
      (() => { const dot = document.querySelector("#student-menu-open .menu-dot").getBoundingClientRect()
        const word = document.querySelector("#student-menu-open > span:not(.menu-dot)"); const range = document.createRange(); range.selectNodeContents(word); const text = range.getBoundingClientRect()
        return dot.left >= text.right - 0.5 })()
    JS
    assert clear, "the dot starts where the word ends"
  end

  test "the picker bar goes away when the comment box opens" do
    sign_in_as :student
    visit "/today"
    find("[data-comment-open]", match: :first, visible: :visible, wait: 15).click
    assert_selector "#comment-banner", visible: :visible
    find("#comment-whole", wait: 10).click
    assert_selector "#comment-box[open]", wait: 10
    assert_no_selector "#comment-banner", visible: :visible
  end
end
