require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# The gallery of the maps family (V6, WAVE2 5.4): the lesson of test/fixtures/lesson2/gallery/maps.md (invented content) drawn by the
# student's page in Chrome, every card at the phone and at the laptop, with the figures answering no error; the shots are kept as files for
# the look gate when BANCO_SHOT_DIR is set. Needs Chrome (BROWSER_PATH).
class MapsGallerySystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery/maps.md")
  SIZES = { "phone" => [ 390, 844 ], "laptop" => [ 1366, 900 ] }.freeze

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "forced-colors", value: "none" }, { name: "prefers-reduced-motion", value: "no-preference" } ])
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  # The body of the gallery as the parser makes it; the page projects it for the student like any lesson.
  def lesson_body
    findings = Validation::Findings.new
    parsed = Lessons::Parser2.call(GALLERY.read, findings)
    raise "the gallery does not parse: #{findings.map(&:message).first(3)}" unless parsed&.body

    parsed.body.merge("key" => TOPIC)
  end

  def open_gallery(size)
    build_student_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    assert_selector "#lesson-root[data-ready='1']", wait: 20
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "maps-#{name}.png"), full: true)

  # Waits until every figure of the card has drawn (a map loads its base first) and none failed.
  def assert_figures_drawn(card)
    assert_selector "#scheda-#{card} .dg .dg-svg path, #scheda-#{card} .dg .dg-svg circle", wait: 20
    assert_no_selector "#scheda-#{card} .dg-failed"
    assert_equal [], page.evaluate_script("[...document.querySelectorAll('#scheda-#{card} .dg[data-error]')].map((f) => f.dataset.error)")
  end

  SIZES.each do |name, size|
    test "every card of the gallery draws with no error at the #{name}" do
      open_gallery(size)
      cards = page.evaluate_script("window.lessonApi.figures().length")
      assert_operator cards, :>=, 1
      (1..8).each do |n|
        go(n)
        assert_selector "#scheda-#{n}", wait: 10
        assert_figures_drawn(n)
        shot "#{name}-card#{n}"
      end
    end
  end

  # ---- select mode (L3): a figure drawn the way a select check will draw it, from the neutral projection ------------------------------

  SELECT_CTX = <<~JS.freeze
    window.__mountSelect = async (data, set, holderId) => {
      const { mountDiagram } = await import("lesson/diagrams/draw")
      const { load } = await import("lesson/diagrams/registry")
      await load(data.type)
      const holder = document.createElement("div")
      holder.id = holderId
      holder.className = "l2 l2-select-holder"
      holder.style.cssText = "max-width:44em;margin:1em auto;padding:0 1em"
      document.getElementById("lesson-page").appendChild(holder)
      const ctx = { subject: "geography", t: { description: "Descrizione", step_of: "Passo %{n} di %{total}", next_step: "Avanti", prev_step: "Indietro", restart_steps: "Da capo" },
                    fontPx: () => 20, reduced: () => false, mount: (fn) => setTimeout(fn, 0), track: () => {} }
      const api = mountDiagram(data, ctx, { mode: "select", set })
      holder.appendChild(api.element)
      window.__picked = []
      api.element.addEventListener("dg:target", (event) => window.__picked.push(event.detail.key))
      ctx.mount(api.mounted)
      return true
    }
  JS

  def select_figure(type_name, set, id)
    vector = JSON.parse(Rails.root.join("test/fixtures/diagrams/types/#{type_name}.json").read)["vectors"].select { |v| v["served_select"]&.key?(set) }.max_by { |v| v["targets"][set].size }
    served = vector["served_select"][set]
    page.execute_script(SELECT_CTX)
    page.evaluate_async_script("const done = arguments[arguments.length - 1]; window.__mountSelect(#{served.to_json}, #{set.to_json}, #{id.to_json}).then(done, (e) => done(String(e && e.stack || e)))")
    assert_selector "##{id} .dg-target", minimum: 1, wait: 20
    vector
  end

  SIZES.each do |name, size|
    test "select targets of a map, a band, a belt and a place, neutral and in reading order, at the #{name}" do
      open_gallery(size)
      go(1)
      { [ "map", "areas" ] => "s-areas", [ "map", "places" ] => "s-places", [ "map", "bands" ] => "s-bands", [ "map", "lines" ] => "s-lines", [ "cross_section", "belts" ] => "s-belts" }.each do |(type_name, set), id|
        vector = select_figure(type_name, set, id)
        ids = vector["targets"][set]
        keys = page.evaluate_script("[...document.querySelectorAll('##{id} [data-target]')].map((n) => n.dataset.target)")
        assert_equal ids.each_index.map { |i| "t#{i + 1}" }, keys, "#{set}: the targets in reading order, t1 to tN"
        # the author's alt_it is the server's business (E-CHECK-ANSWER-IN-ALT): the rest of the page names nothing
        html = page.evaluate_script("document.getElementById('#{id}').outerHTML").sub(/<span id="[^"]*-alt"[^>]*>.*?<\/span>/, "")
        ids.each { |sid| assert_nil html.gsub(/aria-label="[^"]*"/, "")[/(?<![A-Za-z0-9])#{Regexp.escape(sid)}(?![A-Za-z0-9])/], "#{set}: the id #{sid} is in the page" }
        assert_nil html[/Brasile|Argentina|Roma|Amazzoni|foresta|ghiaccio|Italia|Lazio|fascia calda/i], "#{set}: a name is in the page"
        assert_equal [], page.evaluate_script("[...document.querySelectorAll('##{id} .dg-label')].map((l) => l.textContent).filter((t) => !/^(Ovest|Est|Nord|Quota \\(m\\)|\\d+|Altezze.*|0|100|200 km)$/.test(t.trim()))"), "#{set}: no label but the compass and the axes"
        # every target is at least 24 x 24 px at both sizes: its own shape, or its invisible padded hit shape (areas and belts too)
        small = page.evaluate_script("[...document.querySelectorAll('##{id} [data-target]')].map((n) => { const rs = [n, ...document.querySelectorAll('##{id} [data-hit-for=\"' + n.dataset.target + '\"]')].map((e) => e.getBoundingClientRect()); const w = Math.max(...rs.map((r) => r.width)); const h = Math.max(...rs.map((r) => r.height)); return [n.dataset.target, Math.round(w), Math.round(h)] }).filter(([, w, h]) => w < 24 || h < 24)")
        assert_equal [], small, "#{set}: targets at least 24 px at the #{name}"
        # one tab stop; the arrows move; Enter picks and Enter again takes it back
        assert_equal 1, page.evaluate_script("document.querySelectorAll('##{id} [data-target][tabindex=\"0\"]').length")
        page.execute_script("document.querySelector('##{id} [data-target][tabindex=\"0\"]').focus()")
        first = page.evaluate_script("document.activeElement.dataset.target")
        assert_equal "t1", first
        page.driver.browser.keyboard.type(:right) if ids.size > 1
        moved = page.evaluate_script("document.activeElement.dataset.target")
        assert_not_nil moved
        page.driver.browser.keyboard.type(:enter)
        assert_equal "true", page.evaluate_script("document.activeElement.getAttribute('aria-pressed')")
        assert_equal [ moved ], page.evaluate_script("window.__picked")
        page.execute_script("window.__picked = []")
        page.evaluate_script("document.getElementById('#{id}').scrollIntoView()")
        shot "select-#{name}-#{id}"
      end
    end
  end
end
