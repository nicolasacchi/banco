require "application_system_test_case"
require_relative "../support/lesson2_page_world"
require_relative "../support/student_session"

# T4a, the time family in Chrome (WAVE2 5.4): the galleries test/fixtures/lesson2/gallery/time.md (years) and time-english.md (tense) rendered by
# the student's page at 390 and 1366, every state of every figure (V6: no finding at all), the note that opens on a tap, the measure tool with its
# chips, forced colours and print, and the shots of the look gate (BANCO_SHOT_DIR, time-*.png).
class LessonTimeGallerySystemTest < ApplicationSystemTestCase
  include Lesson2PageWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  # a gallery is not a submittable lesson (no mistakes card, no try, no checks): only the structure codes are allowed to remain
  STRUCTURE = %w[E-LESSON-CARDS E-LESSON-CHECKS W-LESSON-CHECKS-SPARSE].freeze
  GALLERIES = { "time" => %w[periodo ere righe lunga misura], "time-english" => %w[ordine forme] }.freeze

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
    @gallery_bodies ||= {}
    @gallery_bodies[@gallery] ||= begin
      md = Rails.root.join("test/fixtures/lesson2/gallery/#{@gallery}.md").read
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

  def open_gallery(gallery, size, theme: nil, text_size: nil)
    @gallery = gallery
    build_student_world(approve: false, release: false)
    Diagnosis::Preferences.record(@trial, theme: theme, size: text_size) if theme || text_size # the student's own choice, on the page from the first draw
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}"
    wait_for_lesson_ready(wait: 30)
    assert_selector ".l2-cover, .l2-card", wait: 10
  end

  def go(n) = page.execute_script("window.lessonApi.goTo(#{n}, { focus: true })")
  def shot(name, selector: nil) = page.driver.save_screenshot(File.join(SHOT_DIR, "#{name}.png"), **(selector ? { selector: selector } : { full: true }))
  def figure_errors = page.evaluate_script("[...document.querySelectorAll('.dg-failed, [data-error]')].map((n) => n.dataset.error || n.textContent.slice(0, 80))")

  GALLERIES.each do |gallery, cards|
    [ [ 390, 1700 ], [ 1366, 1100 ] ].each do |width, height|
      test "every figure of #{gallery} draws at #{width}, in every state, with no finding" do
        open_gallery(gallery, [ width, height ])
        cards.each_with_index do |name, i|
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
            shot("#{gallery}-#{name}-#{width}-s#{s + 1}", selector: "#scheda-#{n}")
            page.execute_script("document.querySelector('#scheda-#{n} .dg-next')?.click()") if states > 1
          end
        end
      end
    end
  end

  test "a tap on an event reads its note, and the note is on the page for a screen reader" do
    open_gallery("time", [ 1366, 1100 ])
    go(1)
    assert_selector "#scheda-1 .dg-hit", minimum: 2
    first = find("#scheda-1 .dg-hit[aria-label^='Primo fatto di prova']")
    assert_includes first["aria-label"], "Un fatto inventato, il primo."
    assert_operator page.evaluate_script("Math.min(...[...document.querySelectorAll('#scheda-1 .dg-hit')].map((b) => Math.min(b.getBoundingClientRect().width, b.getBoundingClientRect().height)))"), :>=, 24
    first.click
    assert_selector "#scheda-1 .dg-question", text: "Primo fatto di prova: Un fatto inventato, il primo."
    shot("time-note-open", selector: "#scheda-1")
  end

  test "the measure tool: two chosen facts give the years between them, a third asks to remove one" do
    open_gallery("time", [ 390, 1700 ])
    go(5)
    assert_selector "#scheda-5 .dg-chipbtn", count: 3
    assert_selector "#scheda-5 .dg-tl-readout", text: "Scegli due fatti per vedere quanti anni passano."
    find("#scheda-5 .dg-chipbtn", text: "Primo fatto").click
    find("#scheda-5 .dg-chipbtn", text: "Terzo fatto").click
    assert_selector "#scheda-5 .dg-tl-readout", text: "Tra Primo fatto e Terzo fatto passano 89 anni."
    find("#scheda-5 .dg-chipbtn", text: "Secondo fatto").click
    assert_selector "#scheda-5 .dg-tl-readout", text: "Hai scelto più di due fatti."
    shot("measure-390", selector: "#scheda-5")
  end

  { "time" => [ 2, 390 ], "time-english" => [ 1, 1366 ] }.each do |gallery, (n, width)|
    test "the select check over the #{gallery} figure: neutral targets, one chosen, graded by the server" do
      open_gallery(gallery, [ width, 1700 ])
      go(n)
      assert_selector "#scheda-#{n} .dg-target", count: 3, wait: 10
      assert_empty figure_errors
      shown = page.evaluate_script("[...document.querySelectorAll('#scheda-#{n} .dg-select .dg-label')].map((l) => l.textContent)").join(" ")
      assert_no_match(/Primo|Secondo|Terzo|I called|I arrive|I'll/, shown, "no name of the figure is drawn")
      assert_operator page.evaluate_script("Math.min(...[...document.querySelectorAll('#scheda-#{n} .dg-target')].map((b) => Math.min(b.getBoundingClientRect().width, b.getBoundingClientRect().height)))"), :>=, 24
      names = page.evaluate_script("[...document.querySelectorAll('#scheda-#{n} .dg-target')].map((b) => b.getAttribute('aria-label'))")
      assert_equal 3, names.uniq.size
      assert(names.none? { |t| t =~ /Primo|Secondo|Terzo|I called|I arrive/ }, names.inspect)
      shot("#{gallery}-select-#{width}", selector: "#scheda-#{n}")
      all("#scheda-#{n} .dg-target").first.click
      click_button "Controlla"
      assert_selector "#scheda-#{n} .verdict-right", wait: 5
    end
  end

  test "forced colours and reduced motion keep the figures whole" do
    open_gallery("time", [ 1366, 1100 ])
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "forced-colors", value: "active" }, { name: "prefers-reduced-motion", value: "reduce" } ])
    [ 1, 3 ].each do |n|
      go(n)
      assert_selector "#scheda-#{n} .dg-stage svg", wait: 10
      assert_empty figure_errors
      shot("forced-colors-#{n}", selector: "#scheda-#{n}")
    end
  end

  [ [ 390, 1900, "larger", "cream" ], [ 1366, 1300, "normal", "dark" ] ].each do |width, height, size, theme|
    GALLERIES.each do |gallery, cards|
      test "#{gallery} keeps whole at #{width} px with the #{size} text size and the #{theme} theme" do
        open_gallery(gallery, [ width, height ], theme: theme, text_size: size)
        cards.each_with_index do |name, i|
          n = i + 1
          go(n)
          assert_selector "#scheda-#{n} .dg-stage svg", wait: 10
          assert_empty figure_errors, "card #{name}"
          assert_operator page.evaluate_script("Math.min(...[...document.querySelectorAll('#scheda-#{n} .dg-label')].map((l) => parseFloat(getComputedStyle(l).fontSize)))"), :>=, (size == "larger" ? 27.9 : 17.9)
          sleep 0.4
          shot("#{gallery}-#{name}-#{width}-#{size}-#{theme}", selector: "#scheda-#{n}")
        end
      end
    end
  end
end
