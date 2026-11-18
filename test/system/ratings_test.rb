require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_course_world"
require_relative "../support/student_session"

# D-365, «Ti è piaciuto?» in Chrome, on a 390 px phone: the student clicks the stars, writes a comment and sends it, on the practice page once
# the exercise is over and at the end of a lesson (lesson/2's last card and a lesson/1's page); «Grazie!», what he sent, «Cambia». The stars are
# real radio inputs with labels, 44 px targets at every text size, and nothing scrolls sideways. Any JavaScript error or CSP violation fails.
module RatingsSystemHelpers
  SIZES = %w[minimum tiny smallest small normal large larger].freeze
  WATCH = <<~JS.freeze
    (() => {
      window.__problems = [];
      const note = (kind, text) => window.__problems.push(kind + ": " + text);
      const consoleError = console.error.bind(console);
      console.error = (...args) => { note("console.error", args.map(String).join(" ")); consoleError(...args); };
      window.addEventListener("error", (e) => note("error", (e.message || "") + " " + (e.filename || "")));
      window.addEventListener("unhandledrejection", (e) => note("unhandledrejection", String(e.reason && e.reason.stack || e.reason)));
      document.addEventListener("securitypolicyviolation", (e) => note("csp", e.violatedDirective + " " + e.blockedURI));
    })();
  JS

  def watch_for_problems
    @watch_id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: WATCH)["identifier"]
  end

  def stop_watching
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: @watch_id) if @watch_id
  rescue StandardError
    nil
  end

  def assert_clean(where)
    problems = Array(page.evaluate_script("window.__problems || []"))
    assert_empty problems, "#{where}: the browser reported problems"
  end

  # The five stars are 44 px at least each way and the box, with everything in it, stays inside the screen, at every text size of D-354.
  def assert_fits_phone(where)
    SIZES.each do |size|
      page.execute_script("document.documentElement.dataset.size = #{size.to_json}")
      boxes = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("#rating-box .rating-star")).map((e) => { const r = e.getBoundingClientRect(); return [r.width, r.height]; })
      JS
      assert_equal 5, boxes.size, "#{where} #{size}"
      assert(boxes.all? { |w, h| w >= 43.9 && h >= 43.9 }, "#{where} #{size}: a star is smaller than 44 px: #{boxes.inspect}")
      inside = page.evaluate_script(<<~JS)
        (() => {
          const box = document.getElementById("rating-box").getBoundingClientRect();
          const parts = Array.from(document.querySelectorAll("#rating-box *")).filter((e) => e.offsetParent !== null).map((e) => e.getBoundingClientRect());
          return { left: box.left, right: box.right, width: window.innerWidth, partRight: Math.max(...parts.map((r) => r.right)), partLeft: Math.min(...parts.map((r) => r.left)) };
        })()
      JS
      assert_operator inside["left"], :>=, -0.5, "#{where} #{size}: the box starts off the screen"
      assert_operator inside["right"], :<=, inside["width"] + 0.5, "#{where} #{size}: the box ends off the screen"
      assert_operator inside["partRight"], :<=, inside["right"] + 0.5, "#{where} #{size}: something sticks out of the box on the right"
      assert_operator inside["partLeft"], :>=, inside["left"] - 0.5, "#{where} #{size}: something sticks out of the box on the left"
    end
    page.execute_script("document.documentElement.dataset.size = 'normal'")
  end

  # Stars, a comment, «Invia», then «Grazie!» and what he sent, «Cambia» and a second rating. Returns the two rows.
  def rate_here(stars:, text:, then_stars:, then_text:)
    within("#rating-box") do
      (1..5).each { |n| assert_selector "label[for='rating-box-star-#{n}'] .sr-only", text: (n == 1 ? "1 stella" : "#{n} stelle"), visible: :all }
      assert_selector "input[type=radio]", count: 5, visible: :all
      find("label[for='rating-box-star-#{stars}']").click
      assert page.evaluate_script("document.getElementById('rating-box-star-#{stars}').checked"), "the star's radio input is checked"
      glyphs = page.evaluate_script("Array.from(document.querySelectorAll('#rating-box .rating-glyph')).map((g) => g.textContent)")
      assert_equal [ "★" ] * stars + [ "☆" ] * (5 - stars), glyphs
      fill_in "rating-box-text", with: text
      assert_selector ".rating-count", text: "#{text.length} di 2000"
      click_button "Invia"
      assert_selector ".rating-thanks", text: "Grazie!", wait: 10
      assert_selector ".rating-sent-stars", text: "★" * stars + "☆" * (5 - stars)
      assert_selector ".rating-sent-text", text: text
      assert_no_selector "form.rating-form", visible: :visible
    end
    first = Rating.order(:id).last
    within("#rating-box") do
      click_button "Cambia"
      assert_selector "form.rating-form", visible: :visible
      assert page.evaluate_script("document.getElementById('rating-box-star-#{stars}').checked"), "the form holds what he sent"
      assert_equal text, find("#rating-box-text").value
      find("label[for='rating-box-star-#{then_stars}']").click
      fill_in "rating-box-text", with: then_text
      click_button "Invia"
      assert_selector ".rating-sent-stars", text: "★" * then_stars + "☆" * (5 - then_stars), wait: 10
      assert_selector ".rating-sent-text", text: then_text
    end
    [ first, Rating.order(:id).last ]
  end
end

class RatingsPracticeSystemTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentSession
  include RatingsSystemHelpers

  setup do
    build_student_world(approve: true, release: true)
    sign_in_as :student
    watch_for_problems
    page.driver.resize(390, 844)
  end

  teardown do
    stop_watching
    page.driver.resize(1280, 900)
    sign_out_env
  end

  test "the box opens when the exercise is over, takes stars and a comment, shows what was sent, changes it, and goes with the exercise" do
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector "#check:not([disabled])", wait: 30
    assert_no_selector "#rating-box", wait: 1 # shut while the exercise is open
    serve = PracticeServe.order(:id).last
    find("input[inputmode=decimal]").set(JSON.parse(serve.item_instance.answer_json).to_s)
    find("#check").click
    assert_selector "#rating-box", wait: 15
    assert_selector "#rating-box h3", text: "Ti è piaciuto questo esercizio?"
    assert_selector "#rating-box button", text: "Invia"
    assert_fits_phone("practice")

    one, two = rate_here(stars: 4, text: "Mi è piaciuto.", then_stars: 2, then_text: "Un po' lungo.")
    assert_equal [ @official.id, "item", serve.item_instance.item_revision.item.key, serve.id, 4, "Mi è piaciuto.", "it", false ],
                 [ one.student_id, one.target_kind, one.target_key, one.practice_serve_id, one.stars, one.text_it, one.language, one.trial ]
    assert_equal [ 2, "Un po' lungo.", one.item_revision_id ], [ two.stars, two.text_it, two.item_revision_id ]
    assert_equal 2, Rating.count, "a change is a new row, the first one stays"

    find("#next-actions .button", text: "Un altro esercizio", match: :first).click
    assert_selector "#check:not([disabled])", wait: 30
    assert_no_selector "#rating-box", wait: 5
    assert_clean "practice"
  end

  test "stars alone, a comment alone and nothing: «Invia» without either says so and sends nothing" do
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector "#check:not([disabled])", wait: 30
    serve = PracticeServe.order(:id).last
    find("input[inputmode=decimal]").set(JSON.parse(serve.item_instance.answer_json).to_s)
    find("#check").click
    assert_selector "#rating-box", wait: 15
    within("#rating-box") do
      click_button "Invia"
      assert_selector ".rating-status", text: "Scegli le stelle o scrivi un commento."
      assert_equal 0, Rating.count
      find("label[for='rating-box-star-5']").click
      click_button "Invia"
      assert_selector ".rating-sent-stars", text: "★★★★★", wait: 10
      assert_no_selector ".rating-sent-text", visible: :visible
    end
    assert_equal [ 5, nil ], Rating.sole.then { |row| [ row.stars, row.text_it ] }
  end
end

class RatingsLessonSystemTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession
  include RatingsSystemHelpers

  setup do
    build_student_world(approve: true, release: true)
    sign_in_as :student
    watch_for_problems
    page.driver.resize(390, 844)
  end

  teardown do
    stop_watching
    page.driver.resize(1280, 900)
    sign_out_env
  end

  test "the end of a lesson/2 has the box after the last card, for the revision he reads" do
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 30)
    summary = stored_body["cards"].find { |c| c["role"] == "summary" }["n"]
    page.execute_script("window.lessonApi.goTo(#{summary}, { focus: false })")
    assert_selector "article#scheda-#{summary} .l2-end #rating-box", wait: 15
    assert_selector "#rating-box h3", text: "Ti è piaciuta questa lezione?"
    assert_no_selector "article:not(#scheda-#{summary}) .rating-box", visible: :all
    page.execute_script("document.getElementById('rating-box').scrollIntoView()")
    assert_fits_phone("lesson/2")

    one, two = rate_here(stars: 5, text: "Chiara e bella.", then_stars: 3, then_text: "Un po' lunga.")
    assert_equal [ @official.id, "lesson", TOPIC, @lesson_revision.id, 5, "Chiara e bella." ],
                 [ one.student_id, one.target_kind, one.target_key, one.lesson_revision_id, one.stars, one.text_it ]
    assert_equal [ 3, "Un po' lunga." ], [ two.stars, two.text_it ]
    assert_equal 2, Rating.count

    # a card taken off the page and put back keeps the box as he left it
    page.execute_script("window.lessonApi.goTo(1, { focus: false })")
    page.execute_script("window.lessonApi.goTo(#{summary}, { focus: false })")
    assert_selector "#rating-box .rating-sent-stars", text: "★★★☆☆"
    assert_clean "lesson/2"

    # the next visit shows his latest rating, not an empty box
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 30)
    page.execute_script("window.lessonApi.goTo(#{summary}, { focus: false })")
    assert_selector "#rating-box .rating-sent-text", text: "Un po' lunga.", wait: 15
  end
end

# A lesson of the first version: the box is at the end of the page.
class RatingsLesson1SystemTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentSession
  include RatingsSystemHelpers

  setup do
    build_student_world(approve: true, release: true)
    sign_in_as :student
    watch_for_problems
    page.driver.resize(390, 844)
  end

  teardown do
    stop_watching
    page.driver.resize(1280, 900)
    sign_out_env
  end

  test "the end of a lesson of the first version has the box" do
    visit "/topics/#{TOPIC}/lesson"
    assert_selector "#rating-box", wait: 15
    assert_selector "#rating-box h3", text: "Ti è piaciuta questa lezione?"
    page.execute_script("document.getElementById('rating-box').scrollIntoView()")
    assert_fits_phone("lesson/1")
    one, two = rate_here(stars: 3, text: "Va bene.", then_stars: 4, then_text: "Meglio di prima.")
    assert_equal [ "lesson", TOPIC, @lesson_revision.id, 3 ], [ one.target_kind, one.target_key, one.lesson_revision_id, one.stars ]
    assert_equal [ 4, "Meglio di prima." ], [ two.stars, two.text_it ]
    assert_clean "lesson/1"
  end
end
