require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# T6, the chart family in Chrome (WAVE2 5.4): the gallery lesson test/fixtures/lesson2/gallery/chart.md rendered by the student's page at 390 and
# 1366, every state of every figure (V6: no finding at all), the controls with their - and + buttons (A2), the numbers behind "Vedi i numeri"
# (P2), the live line of the sliders and the cursor (A6), and the shots for the look gate (BANCO_SHOT_DIR, chart-*.png).
class LessonChartGallerySystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  GALLERY = Rails.root.join("test/fixtures/lesson2/gallery/chart.md")
  # a gallery is not a submittable lesson (no mistakes card, no try, no checks): only the structure codes are allowed to remain
  STRUCTURE = %w[E-LESSON-CARDS E-LESSON-CHECKS W-LESSON-CHECKS-SPARSE].freeze
  CARDS = %w[pioggia arido monsone sud parti percento seggi].freeze

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

  def lesson_body
    @gallery_body ||= begin
      md = GALLERY.read
      front = YAML.safe_load(md[/\A---\n(.*?)\n---\n/m, 1])
      refs = front["refs"].to_h { |r| [ [ r["source"], r["line"] ], r["fragment"] ] }
      context = Validation::Context.new(subject: front["subject"], skill: ->(k) { { "key" => k, "errors" => [] } },
                                        source_line: ->(s, n) { (t = refs[[ s, n ]]) && { text: t, origin: "pdf" } }, topic: ->(_k) { true })
      result = Validation::LessonChecks.call(md, subject: front["subject"], context: context)
      leftovers = result.findings.reject { |f| STRUCTURE.include?(f.code) }
      raise "the gallery has findings besides its structure: #{leftovers.map { |f| [ f.code, f.field, f.message ] }.inspect}" unless leftovers.empty?

      result.body.merge("key" => TOPIC)
    end
  end

  def open_gallery(size)
    build_student_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    assert_selector "#lesson-root[data-ready='1']", wait: 30
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name, selector: nil) = page.driver.save_screenshot(File.join(SHOT_DIR, "chart-#{name}.png"), **(selector ? { selector: selector } : { full: true }))
  def figure_errors = page.evaluate_script("[...document.querySelectorAll('.dg-failed, [data-error]')].map((n) => n.dataset.error || n.textContent.slice(0, 80))")

  [ [ 390, 1500 ], [ 1366, 1100 ] ].each do |width, height|
    test "every figure of the chart gallery draws at #{width}, in every state, with no finding" do
      open_gallery([ width, height ])
      CARDS.each_with_index do |name, i|
        n = i + 1
        go(n)
        assert_selector "#scheda-#{n} .dg-stage svg", wait: 10
        assert_empty figure_errors, "card #{name}"
        states = page.evaluate_script("document.querySelector('#scheda-#{n} .dg')?.dataset.states").to_i
        (states > 1 ? states : 1).times do |s|
          assert_empty figure_errors, "card #{name}, state #{s}"
          assert_equal [], page.evaluate_script("[...document.querySelectorAll('#scheda-#{n} .dg-label')].filter((l) => { const r = l.getBoundingClientRect(); return r.width > 0 && (r.right > innerWidth + 1 || r.left < -1) }).map((l) => l.textContent)")
          assert_operator page.evaluate_script("Math.min(...[...document.querySelectorAll('#scheda-#{n} .dg-label')].map((l) => parseFloat(getComputedStyle(l).fontSize)))"), :>=, 17.9, "no text under the base size"
          sleep 0.5 # the card's own fade-in
          shot("#{name}-#{width}-s#{s + 1}", selector: "#scheda-#{n}")
          page.execute_script("document.querySelector('#scheda-#{n} .dg-next')?.click()") if states > 1
        end
      end
    end
  end

  test "the numbers open under the chart, only for the layers that show, with the source" do
    open_gallery([ 1366, 900 ])
    go(1)
    assert_selector "#scheda-1 .dg-values summary", text: "Vedi i numeri"
    page.execute_script("document.querySelector('#scheda-1 .dg-values summary').click()")
    assert_selector "#scheda-1 .dg-values table tbody tr", count: 12
    assert_equal [ "", "Pioggia (mm)" ], page.evaluate_script("[...document.querySelectorAll('#scheda-1 .dg-values thead th')].map((n) => n.textContent)")
    page.execute_script("document.querySelector('#scheda-1 .dg-next').click()")
    assert_equal [ "", "Pioggia (mm)", "Temperatura (°C)" ], page.evaluate_script("[...document.querySelectorAll('#scheda-1 .dg-values thead th')].map((n) => n.textContent)")
    assert_selector "#scheda-1 .dg-source", text: "Fonte:"
    shot("numbers-open", selector: "#scheda-1")
  end

  test "the read cursor steps through the months with the buttons and reads only what shows" do
    open_gallery([ 390, 1500 ])
    go(1)
    assert_selector "#scheda-1 .dg-ctl-value", text: "Nessuno"
    assert page.evaluate_script("document.querySelector('#scheda-1 .dgc-cursor') === null"), "no month is marked before the student asks"
    assert_selector "#scheda-1 .dg-ctl-btn[aria-label='Mese: Uno in meno'][disabled]"
    2.times { find("#scheda-1 .dg-ctl-btn[aria-label='Mese: Uno in più']").click }
    assert_selector "#scheda-1 .dg-ctl-value", text: "Febbraio"
    assert_selector "#scheda-1 .dgc-readout", text: /\AFebbraio: pioggia/
    assert_includes page.evaluate_script("document.querySelector('#scheda-1 .dg-live').textContent"), "Febbraio: pioggia"
    assert_includes page.evaluate_script("document.querySelector('#scheda-1 .dg-live').getAttribute('aria-live')"), "polite"
    assert page.evaluate_script("document.querySelector('#scheda-1 .dgc-cursor') !== null")
    assert_operator page.evaluate_script("Math.min(...[...document.querySelectorAll('#scheda-1 .dg-ctl-btn')].map((b) => b.getBoundingClientRect().width))"), :>=, 24
    shot("cursor-390", selector: "#scheda-1")
  end

  test "the sliders of the seats come with - and + buttons, move the counts and the live line, and stay inside their ranges" do
    open_gallery([ 390, 1500 ])
    go(7)
    assert_selector "#scheda-7 .dg-ctl", count: 2
    assert_selector "#scheda-7 .dg-ctl .dg-ctl-btn", count: 4
    assert_selector "#scheda-7 .dgs-line", text: /Presenti: 300/
    find("#scheda-7 .dg-ctl[aria-label='Presenti'] .dg-ctl-btn[aria-label='Presenti: Uno in più']").click
    assert_selector "#scheda-7 .dgs-line", text: /Presenti: 301/
    assert_selector "#scheda-7 .dg-ctl[aria-label='Presenti'] .dg-rangevalue", text: "301"
    page.execute_script("const r = document.querySelector('#scheda-7 .dg-ctl[aria-label=\"Presenti\"] input'); r.value = 10; r.dispatchEvent(new Event('input'))")
    assert_selector "#scheda-7 .dgs-line", text: /Presenti: 280/
    assert_selector "#scheda-7 .dg-ctl[aria-label='Presenti'] .dg-ctl-btn[aria-label='Presenti: Uno in meno'][disabled]"
    assert_includes page.evaluate_script("document.querySelector('#scheda-7 .dg-live').textContent"), "Presenti: 280"
    yes_input = "#scheda-7 .dg-ctl[aria-label='Voti sì'] input"
    page.execute_script("const r = document.querySelector(\"#{yes_input}\"); r.value = 150; r.dispatchEvent(new Event('input'))")
    assert_selector "#scheda-7 .dgs-line", text: /Voti sì: 150/
    assert_selector "#scheda-7 .dgs-line", text: /Esito: approvata/
    # the keyboard: the slider is a native range, an arrow key moves it by its step
    page.execute_script("document.querySelector(\"#{yes_input}\").focus()")
    page.driver.browser.keyboard.type(:Right)
    assert_selector "#scheda-7 .dgs-line", text: /Voti sì: 151/
    shot("seats-sliders-390", selector: "#scheda-7")
  end

  test "forced colours and reduced motion keep every figure whole, and print hides the sliders" do
    open_gallery([ 1366, 1100 ])
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "forced-colors", value: "active" }, { name: "prefers-reduced-motion", value: "reduce" } ])
    [ 2, 5, 7 ].each do |n|
      go(n)
      assert_selector "#scheda-#{n} .dg-stage svg", wait: 10
      assert_empty figure_errors
      shot("forced-colors-#{n}", selector: "#scheda-#{n}")
    end
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "print", features: [])
    go(7)
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('#scheda-7 .dg-ctl')).display")
  end

  [ [ 390, 1700, "larger", "cream" ], [ 1366, 1100, "normal", "dark" ] ].each do |width, height, size, theme|
    test "every figure keeps whole at #{width} px with the #{size} text size and the #{theme} theme" do
      open_gallery([ width, height ])
      page.execute_script("document.documentElement.dataset.theme = '#{theme}'; document.documentElement.dataset.size = '#{size}'; window.lessonApi.relayout()")
      CARDS.each_with_index do |name, i|
        n = i + 1
        go(n)
        assert_selector "#scheda-#{n} .dg-stage svg", wait: 10
        assert_empty figure_errors, "card #{name}"
        assert_operator page.evaluate_script("Math.min(...[...document.querySelectorAll('#scheda-#{n} .dg-label')].map((l) => parseFloat(getComputedStyle(l).fontSize)))"), :>=, (size == "larger" ? 27.9 : 17.9)
        assert_equal [], page.evaluate_script("[...document.querySelectorAll('#scheda-#{n} .dg-label')].filter((l) => { const r = l.getBoundingClientRect(); return r.width > 0 && (r.right > innerWidth + 1 || r.left < -1) }).map((l) => l.textContent)")
        sleep 0.4
        shot("#{name}-#{width}-#{size}-#{theme}", selector: "#scheda-#{n}") if [ 1, 3, 6, 7 ].include?(n)
      end
    end
  end
end
