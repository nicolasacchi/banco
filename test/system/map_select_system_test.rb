require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"
require_relative "../support/decision_world"
require_relative "../support/topic_world"

# Select checks over a map (D-319): a tap or a click on a zone or a place selects it, at the phone (touch) and at the laptop (mouse), and
# Controlla grades the pick. The check is the history lesson's «In quale zona sta Cartagine?» (`targets: areas` with `candidates`) and the same
# question over places (`targets: places`); the pages are the student's lesson, the teacher's box on the topic page and /teacher/preview.
# The point tapped is found by asking the browser which point of the target the page really hits (elementFromPoint), then sent as real input.
module MapSelectSupport
  FIXTURE = Rails.root.join("test/fixtures/lesson2/map_select.md")
  SHOT_DIR = ENV["BANCO_SHOT_DIR"].presence
  SIZES = { "390 touch" => [ 390, 844, :touch ], "1280 mouse" => [ 1280, 900, :mouse ] }.freeze
  # card number => [set, the stored id of the right answer, a wrong one]
  CARDS = { 1 => [ "areas", "africa-proconsolare", "egitto" ], 3 => [ "places", "cartagine", "roma" ] }.freeze

  def parsed_body
    findings = Validation::Findings.new
    parsed = Lessons::Parser2.call(FIXTURE.read, findings)
    raise "does not parse: #{findings.map(&:message).first(3)}" unless parsed&.body

    parsed.body
  end

  def check_of(card)
    parsed_body["cards"][card - 1]["blocks"].find { |b| b["component"] == "select" }
  end

  def target_key(card, stored_id) = Lessons::SelectTargets.id_map(check_of(card)).key(stored_id)

  # A point of the target's own shape that the page hits: a viewport coordinate pair, or nil.
  FIND = <<~JS.freeze
    (scope, key) => {
      const node = document.querySelector(scope + ' svg [data-target="' + key + '"]')
      if (!node) return null
      node.scrollIntoView({ block: "center", inline: "center" })
      const r = node.getBoundingClientRect()
      const pads = [...document.querySelectorAll(scope + ' svg [data-hit-for="' + key + '"]')]
      const button = document.querySelector(scope + ' .dg-targets [data-target="' + key + '"]')
      let best = null
      for (let i = 1; i < 60 && !best; i++) for (let j = 1; j < 60 && !best; j++) {
        const x = r.left + (r.width * i) / 60, y = r.top + (r.height * j) / 60
        if (x < 0 || y < 0 || x > innerWidth || y > innerHeight) continue
        const hit = document.elementFromPoint(x, y)
        if (hit === node || pads.includes(hit) || (button && (hit === button || button.contains(hit)))) best = [x, y]
      }
      return best
    }
  JS

  def hit_point(scope, key)
    point = page.evaluate_script("(#{FIND})(#{scope.to_json}, #{key.to_json})")
    assert point, "#{scope}: no point of #{key} is hit by the page"
    point
  end

  def tap_at(point, mode)
    cdp = page.driver.browser.page
    x, y = point
    if mode == :touch
      cdp.command("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
      cdp.command("Input.dispatchTouchEvent", type: "touchStart", touchPoints: [ { x: x, y: y } ])
      cdp.command("Input.dispatchTouchEvent", type: "touchEnd", touchPoints: [])
    else
      cdp.command("Input.dispatchMouseEvent", type: "mouseMoved", x: x, y: y)
      cdp.command("Input.dispatchMouseEvent", type: "mousePressed", x: x, y: y, button: "left", clickCount: 1)
      cdp.command("Input.dispatchMouseEvent", type: "mouseReleased", x: x, y: y, button: "left", clickCount: 1)
    end
  end

  # A shot of the card by selector: a viewport shot of a page scrolled far down (the teacher's topic page is long) came out as bare cream.
  def shot(name, scope)
    return unless SHOT_DIR

    FileUtils.mkdir_p(SHOT_DIR)
    sleep 0.5
    r = page.evaluate_script("(() => { const r = document.querySelector(#{scope.strip.to_json}).getBoundingClientRect(); return { x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height } })()")
    data = page.driver.browser.page.command("Page.captureScreenshot", format: "png", captureBeyondViewport: true, clip: r.merge("scale" => 1))["data"]
    File.binwrite(File.join(SHOT_DIR, "#{name}.png"), Base64.decode64(data))
  end

  # Taps every target of the card's figure (each selects only itself), then a wrong and a right answer are graded.
  def exercise_card(root, card, mode, label)
    set, right, wrong = CARDS.fetch(card)
    scope = "#{root} #scheda-#{card}"
    assert_selector "#{scope} svg [data-target]", minimum: 2, wait: 20
    assert_no_selector "#{scope} .select-fallback:not([hidden])"
    keys = page.evaluate_script("[...document.querySelectorAll(#{"#{scope} svg [data-target]".to_json})].map((n) => n.dataset.target)")
    assert_equal 4, keys.size, "#{set}: the four targets are drawn"
    keys.each do |key|
      tap_at(hit_point(scope, key), mode)
      assert_selector "#{scope} .dg-target[data-target='#{key}'][aria-pressed='true']", wait: 5
      assert_equal [ key ], page.evaluate_script("[...document.querySelectorAll(#{"#{scope} [aria-pressed='true'][data-target]".to_json})].map((n) => n.dataset.target)").uniq, "#{set}: pick one keeps one"
      assert_selector "#{scope} svg .is-selected[data-target='#{key}']"
    end
    shot "#{label}-#{set}-picked", scope
    wrong_key = target_key(card, wrong)
    # pick one: a tap on the target already chosen unchooses it, so it is tapped only when the loop did not leave it chosen
    tap_at(hit_point(scope, wrong_key), mode) unless page.has_css?("#{scope} .dg-target[data-target='#{wrong_key}'][aria-pressed='true']", wait: 0)
    assert_selector "#{scope} .dg-target[data-target='#{wrong_key}'][aria-pressed='true']"
    find("#{scope} button", text: "Controlla").click
    assert_selector "#{scope} .verdict-wrong", wait: 10
    tap_at(hit_point(scope, target_key(card, right)), mode)
    find("#{scope} button", text: "Controlla").click
    assert_selector "#{scope} .verdict-right", wait: 10
    shot "#{label}-#{set}-right", scope
  end
end

class MapSelectStudentTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession
  include MapSelectSupport

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def lesson_body = parsed_body.merge("key" => TOPIC)

  SIZES.each do |name, (w, h, mode)|
    test "the student's lesson: a tap on a zone or a place selects it and Controlla grades it, #{name}" do
      build_student_world(approve: false, release: false)
      sign_in_as :student
      page.driver.headers = TRIAL_HEADERS
      page.driver.resize(w, h)
      visit "about:blank"
      visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
      wait_for_lesson_ready(wait: 20)
      CARDS.each_key do |card|
        page.execute_script("window.lessonApi.goTo(#{card}, { focus: true })")
        exercise_card("", card, mode, "student-#{name.tr(' ', '-')}")
      end
    end
  end
end

class MapSelectPreviewTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession
  include MapSelectSupport

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = ""
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def lesson_body = parsed_body.merge("key" => TOPIC)

  SIZES.each do |name, (w, h, mode)|
    test "the teacher's preview: a tap on a zone or a place selects it and Controlla grades it, #{name}" do
      build_student_world(approve: true, release: true)
      sign_in_as :teacher
      page.driver.resize(w, h)
      visit "/teacher/preview/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
      wait_for_lesson_ready(wait: 30)
      CARDS.each_key do |card|
        page.execute_script("window.lessonApi.goTo(#{card}, { focus: true })")
        exercise_card("", card, mode, "preview-#{name.tr(' ', '-')}")
      end
    end
  end
end

class MapSelectTeacherBoxTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession
  include TopicWorld
  include MapSelectSupport

  def lesson_revision_with_body!(key, skill)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: key.split(".", 3)[1]), key: key, kind: "ripasso")
    md = "---\nkey: #{key}\n---\n"
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md), body_json: JSON.generate(parsed_body.merge("key" => key, "skills" => [ skill ])),
                           rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  setup do
    @world = build_ui_subject(approve: false)
    @subject = @world[:subject]
    @graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
    build_topic_world
    sign_in_as :teacher
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setTouchEmulationEnabled", enabled: false)
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
  end

  SIZES.each do |name, (w, h, mode)|
    test "the teacher's box: a tap on a zone or a place selects it and Controlla grades it (seed preview), #{name}" do
      page.driver.resize(w, h)
      visit "/teacher/subjects/math/topics/#{TopicWorld::TOPIC_KEY}"
      assert_selector ".l2-box [data-ready='1']", wait: 20
      find(".l2-box .l2-start").click
      assert_selector ".l2-box #scheda-1", wait: 10
      exercise_card(".l2-box", 1, mode, "box-#{name.tr(' ', '-')}")
      2.times { click_button(class: "l2-next") }
      assert_selector ".l2-box #scheda-3", wait: 10
      exercise_card(".l2-box", 3, mode, "box-#{name.tr(' ', '-')}")
    end
  end
end
