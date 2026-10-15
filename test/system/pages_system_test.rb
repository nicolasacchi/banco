require "application_system_test_case"
require_relative "../support/pages_lesson_world"
require_relative "../support/student_session"
require_relative "../support/chrome_helper"

# Free pages in Chrome (D-290, SPEC B4, B10): the page block of a lesson, loaded on a click into a sandboxed iframe on the pages origin,
# the watchdog that takes a broken page away, the switch, the refusal to be framed, and the browser matrix page. Screenshots go to
# BANCO_SHOT_DIR (pages-<name>-<width>.png) for the look gate.
class PagesSystemTest < ApplicationSystemTestCase
  include PagesLessonWorld
  include StudentSession
  include ChromeHelper

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))

  setup do
    require_chrome!
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    @shots = Dir.mktmpdir
    ENV["BANCO_PAGE_SHOTS_DIR"] = @shots
    ENV["BANCO_PAGES_DIR"] = Dir.mktmpdir
    FileUtils.mkdir_p(SHOT_DIR)
    @origin = start_pages_origin!
    page.driver.clear_network_traffic # the runner's Chrome is shared: the traffic of the tests before is not this test's
  end

  teardown do
    begin
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    stop_pages_origin!
    (page.driver.clear_network_traffic rescue nil) # so that the tests after do not see the pages origin as a foreign request
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
    FileUtils.rm_rf([ ENV.delete("BANCO_PAGE_SHOTS_DIR"), ENV.delete("BANCO_PAGES_DIR") ].compact)
  end

  def shot(name, width) = page.driver.save_screenshot(File.join(SHOT_DIR, "pages-#{name}-#{width}.png"), full: true)

  # The page, validated for real in the server's Chrome (seed 0 only: the poster and a verdict), stored and passed.
  def validated_page(files = page_files)
    revision = store_page!(files)
    result = Validation::ChromeRunner.session(wait: 900) { |session| Validation::PageRunner.new(session, revision: revision, kit: "1.0", seeds: [ 0 ]).call }
    PageValidation.create!(page_revision: revision, kit_version: "1.0", status: result.status, harness_version: "t", chrome_version: result.chrome_version, attempt: 1,
                           result_json: JSON.generate("errors" => result.errors, "warnings" => result.warnings), shots_json: JSON.generate(result.shots))
    assert_equal "passed", result.status, result.errors.inspect
    revision
  end

  def open_lesson(revision, size: [ 1366, 900 ])
    build_pages_lesson_world(revision, approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
    page.execute_script("window.lessonApi.goTo(#{PagesLessonWorld::EXTRA_CARD}, { focus: true })")
    assert_selector ".free-page", wait: 10
  end

  # A frame that is still being created has no execution context yet: look again a few times before giving up. The runner's Chrome also
  # leaves the initial main frame without any context for good (state :canceled): asking it for its url waits for one and, in two runs, never
  # came back (the 900 s watchdog stopped this test), so a frame with no context is not asked, and each answer is bounded.
  def frame_for_pages
    5.times do
      frame = page.driver.browser.page.frames.find do |f|
        next false unless f.execution_id

        Timeout.timeout(5) { f.url.to_s.start_with?(@origin) }
      rescue Timeout::Error, Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
        false
      end
      return frame if frame
    rescue Ferrum::NoExecutionContextError, Ferrum::NodeNotFoundError
      nil
    ensure
      sleep 0.5
    end
    nil
  end

  { "1366" => [ 1366, 900 ], "390" => [ 390, 844 ] }.each do |label, size|
    test "the page waits for a click, then runs in a sandboxed frame on the pages origin, at #{label} px (shots)" do
      revision = validated_page
      open_lesson(revision, size: size)
      assert_selector ".free-page[data-state='idle']"
      assert_selector "img.free-page-poster[src^='/page-posters/']"
      assert_text "Prova tu: muovi il cursore e guarda cosa cambia."
      assert_no_selector ".free-page-help", wait: 0.3 # the instructions repeat the caption, so only the caption is shown
      assert_selector "button.free-page-open", text: /\AApri la parte interattiva \(circa \d+ KB\)\z/
      assert_no_selector "iframe.free-page", wait: 0.3
      assert_equal 0, page.driver.network_traffic.count { |r| r.url.to_s.start_with?(@origin) }, "nothing of the page loads until it is asked for"
      shot("poster", label)
      click_button("Apri la parte interattiva")
      assert_selector ".free-page[data-state='running']", wait: 30
      iframe = find("iframe.free-page")
      assert_equal "allow-scripts", iframe[:sandbox]
      assert_not_nil iframe[:credentialless]
      assert_equal "no-referrer", iframe[:referrerpolicy]
      assert iframe[:src].start_with?("#{@origin}/p/#{revision.bundle_sha256}/k1.0/")
      assert_no_match(/allow-same-origin|allow-forms|allow-popups|allow-top-navigation|allow-modals|allow-downloads/, iframe[:sandbox])
      assert iframe[:allow].to_s.empty?, "no allow attribute: no device permission"
      assert_button "Schermo intero"
      sleep 1.0
      shot("running", label)
      # what the page told the lesson reaches its own ledger, never a skill state
      sleep 1.2
      assert_equal 1, LessonEvent.where(kind: "page_opened").count
      assert_equal({ "block" => 2 }, LessonEvent.find_by(kind: "page_opened").payload.slice("block").transform_values { |v| v.is_a?(Integer) ? 2 : v })
    end
  end

  test "the slider inside the frame moves the lines and tells the lesson, and the lesson's text size reaches the frame" do
    revision = validated_page
    open_lesson(revision)
    click_button("Apri la parte interattiva")
    assert_selector ".free-page[data-state='running']", wait: 30
    sleep 0.8
    frame = frame_for_pages
    skip "the Chrome of this machine does not expose the sandboxed frame to the driver" unless frame
    before = frame.evaluate("document.querySelector('.banco-readout').textContent")
    frame.evaluate("(() => { const s = document.getElementById('slope'); s.value = s.value === '2' ? '-2' : '2'; s.dispatchEvent(new Event('input', { bubbles: true })) })()")
    after = frame.evaluate("document.querySelector('.banco-readout').textContent")
    assert_not_equal before, after
    sleep 1.4
    assert LessonEvent.where(kind: "page_event").exists?
    assert_equal "interacted", LessonEvent.where(kind: "page_event").last.payload["kind"]
  end

  test "a page that never starts is taken away after the ready limit, the poster and the fallback come back, and the failure is recorded" do
    stuck = page_files { |f| f["main.mjs"] = %(import { banco } from "banco"\nawait new Promise(() => {})\n) }
    revision = store_page!(stuck, scan: false)
    pass_page!(revision, shots: [])
    open_lesson(revision)
    click_button("Apri la parte interattiva")
    assert_selector ".free-page[data-state='failed']", wait: 25
    assert_no_selector "iframe.free-page"
    assert_text "La parte interattiva non si è avviata."
    assert_text "Il disegno non parte su questo dispositivo."
    assert_button "Riprova"
    sleep 1.2
    assert_equal "ready", LessonEvent.find_by(kind: "page_failed").payload["limit"]
    shot("failed", page.driver.evaluate_script("window.innerWidth"))
  end

  test "switched off, the card keeps its poster, caption and fallback and has no button, and nothing loads from the pages origin" do
    revision = validated_page
    ENV["BANCO_PAGES_ENABLED"] = "0"
    open_lesson(revision)
    assert_selector ".free-page[data-state='off']"
    assert_no_button("Apri la parte interattiva")
    assert_text "Il disegno non parte su questo dispositivo."
    assert_equal 0, page.driver.network_traffic.count { |r| r.url.to_s.start_with?(@origin) }
    assert_equal 404, Net::HTTP.get_response(URI("#{@origin}/p/#{revision.bundle_sha256}/k1.0/")).code.to_i
  end

  test "an app page cannot be framed: /today answers frame-ancestors none and X-Frame-Options DENY, and Chrome refuses the frame" do
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    visit "/today"
    assert_selector "body"
    # a page on another origin tries to frame it
    host = Puma::Server.new(->(_env) { [ 200, { "content-type" => "text/html" }, [ %(<!doctype html><iframe id="f" src="#{origin}/today"></iframe>) ] ] }, nil, { min_threads: 0, max_threads: 2, log_writer: Puma::LogWriter.strings })
    host.add_tcp_listener("127.0.0.1", 0)
    host.run
    begin
      page.driver.headers = {}
      visit "http://127.0.0.1:#{host.connected_ports.first}/"
      sleep 2
      frames = page.driver.browser.page.frames.reject { |f| f.main? }
      assert_equal 1, frames.size
      assert_match(/chrome-error:|\Aabout:blank\z/, frames.first.url.to_s, "the frame must not show the app")
      assert_no_match(%r{/today}, frames.first.url.to_s)
    ensure
      host.stop(true)
    end
  end

  test "the browser matrix page runs inside the real iframe and reports its table" do
    dir = PageWorld::FIXTURES.join("math.pages-selftest")
    files = Dir.glob("**/*", base: dir.to_s).select { |f| File.file?(dir.join(f)) }.to_h { |f| [ f, File.binread(dir.join(f)) ] }
    subject = page_subject!
    outcome = Validation::PageChecks.call(files, key: "math.pages-selftest", subject: "math", scan: false, operator: true)
    assert_empty outcome.findings.errors.map(&:message)
    Pages::Submit.store(key: "math.pages-selftest", subject: subject, outcome: outcome, warnings: [], author: nil, operator: true)
    sign_in_as :teacher
    visit "/teacher/pages/selftest"
    assert_selector ".free-page[data-state='idle']", wait: 15
    click_button("Apri la parte interattiva")
    assert_selector "[data-selftest-target='table']:not([hidden]) tbody tr", count: 15, wait: 40
    rows = all("[data-selftest-target='table'] tbody tr").to_h { |tr| cells = tr.all("td").map(&:text); [ cells[0], cells[2] ] }
    %w[module kit three texture font bridge].each { |id| assert_equal "funziona", rows[id], "#{id}: #{rows.inspect}" }
    %w[fetch_own fetch_app cookie top storage frame rtc].each { |id| assert_equal "bloccato", rows[id], "#{id}: #{rows.inspect}" }
    assert_includes [ "funziona", "senza 3D (testo)" ], rows["webgl"]
    shot("selftest", 1280)
  end
end
