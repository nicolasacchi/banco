require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/student_session"

# cell and nested on the student's page in Chrome (D-312): the numbers and the key, Avanti lighting the four shared parts, a tap that reads a part's job
# or the author's note, "Solo le differenze", the water of the vacuole, the select checks over a cell's parts (one cell and two, never with chips) and
# the levels (the page never names a candidate), an example that moves its linked cell and asks the kind of a cell only its label names, the focus
# moving out through the levels, and reduced motion. The gallery test/fixtures/lesson2/gallery/science-biology.md is the lesson.
# Screenshots in BANCO_SHOT_DIR: the look gate, every card at 390 and 1280 px in the cream and the dark theme.
class BiologyFiguresTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  PART_NAMES = %w[wall membrane cytoplasm nucleoid nucleus dna ribosomes mitochondria chloroplasts vacuole er golgi vesicles flagellum].freeze

  def lesson_body
    @gallery_body ||= Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/science-biology.md").read, Validation::Findings.new).body.merge("key" => TOPIC)
  end

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
    build_student_world(approve: false, release: false)
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    page.driver.resize(1280, 900)
  end

  teardown do
    begin
      page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
      page.driver.resize(1280, 900)
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def shot(name) = page.driver.save_screenshot(File.join(SHOT_DIR, "biology-#{name}.png"), full: true)

  def open_card(n, size: [ 1280, 900 ])
    page.driver.resize(*size)
    visit "about:blank"
    visit "/topics/#{TOPIC}/lesson?n=#{SecureRandom.hex(3)}#scheda-#{n}"
    wait_for_lesson_ready(wait: 20)
    assert_selector "#scheda-#{n} .dg", wait: 10
  end

  test "two cells with one key; Avanti lights the four shared parts and dims the rest; a tap reads a part's job or the author's note" do
    open_card(1)
    assert_selector "#scheda-1 .dg-cell .dg-ctitle", text: "Batterio"
    assert_selector "#scheda-1 .dg-ckey", text: "DNA (nucleoide)"
    assert_selector "#scheda-1 .dg-ckey", text: "mitocondri"
    assert_no_selector "#scheda-1 .dg-cp.is-lit"
    click_button "Passo avanti"
    assert_selector "#scheda-1 .dg-op", text: "Le quattro parti di tutte e due"
    assert_selector "#scheda-1 .dg-cp-nucleoid.is-lit"
    assert_selector "#scheda-1 .dg-cp-dna.is-lit"
    assert_selector "#scheda-1 .dg-cp-mitochondria.is-dim"
    assert_selector "#scheda-1 .dg-cp-halo", minimum: 4
    find("#scheda-1 .dg-hit[aria-label^='Ribosomi']", match: :first).click
    assert_selector "#scheda-1 .dg-question", text: "Ribosomi: Costruiscono le proteine."
    find("#scheda-1 .dg-hit[aria-label^='DNA (nucleoide)']").click
    assert_selector "#scheda-1 .dg-question", text: "DNA (nucleoide): Il DNA sta nel citoplasma: intorno non c'è un nucleo."
    find("#scheda-1 .dg-desc summary").click
    assert_text "Evidenziate: membrana, citoplasma, DNA e ribosomi."
  end

  test "Solo le differenze lights the wall, the chloroplasts and the vacuole of the plant cell and says so" do
    open_card(2)
    chip = find("#scheda-2 .dg-chipbtn", text: "Solo le differenze")
    assert_equal "false", chip["aria-pressed"]
    chip.click
    assert_equal "true", chip["aria-pressed"]
    assert_selector "#scheda-2 .dg-cp-vacuole.is-lit"
    assert_selector "#scheda-2 .dg-cp-wall.is-lit"
    assert_selector "#scheda-2 .dg-cp-nucleus.is-dim", minimum: 2 # the shared parts dim in both cells
    assert_selector "#scheda-2 .dg-live", text: "Accese le parti che ha solo una delle due cellule: parete cellulare, cloroplasti e vacuolo.", visible: :all
    shot "compare-on-1280"
  end

  test "names on a tap only, with the author's note; the vacuole empties and the membrane pulls away from the wall" do
    open_card(4, size: [ 390, 844 ])
    within("#scheda-4 .dg-labels") { assert_no_text "cloroplasti" }
    assert_text "Tocca una parte per leggere il suo nome e che cosa fa."
    find("#scheda-4 .dg-hit[aria-label^='Cloroplasti']").click
    assert_selector "#scheda-4 .dg-question", text: "Cloroplasti: Nelle radici sotto terra i cloroplasti non ci sono."
    open_card(5, size: [ 390, 844 ])
    width = -> { page.evaluate_script("document.querySelector('#scheda-5 .dg-cp-vacuole').getBBox().width") }
    full = width.call
    2.times { click_button "Passo avanti" }
    assert_selector "#scheda-5 .dg-op", text: "Poca acqua"
    assert_operator width.call, :<, full * 0.7
  end

  test "select over a cell's parts: neutral zones, no part named anywhere in the figure, the answer graded" do
    open_card(7, size: [ 390, 844 ])
    assert_selector "#scheda-7 .dg-target", count: 5
    html = find("#scheda-7 .dg")["outerHTML"]
    PART_NAMES.each { |p| assert_no_match(/dg-cp-#{p}\b|:#{p}\b/, html, "the select figure names #{p}") }
    assert_no_match(/nucleoide|ribosomi|parete/i, html)
    assert_equal "zona 1 di 5, Parte 1 di 5", find("#scheda-7 .dg-target[data-target='t1']")["aria-label"]
    find("#scheda-7 .dg-target[data-target='t5']").click
    click_button "Controlla"
    assert_selector "#scheda-7 .verdict-wrong", wait: 5
    assert_text "Quelli sono i ribosomi"
    find("#scheda-7 .dg-target[data-target='t4']").click
    click_button "Controlla"
    assert_selector "#scheda-7 .verdict-right", wait: 5
    open_card(8)
    assert_selector "#scheda-8 .dg-target", count: 8
    %w[t1 t7 t8].each { |t| find("#scheda-8 .dg-target[data-target='#{t}']").click }
    click_button "Controlla"
    assert_selector "#scheda-8 .verdict-right", wait: 5
  end

  test "an example moves its linked cell step by step, its blank asks the kind of a cell the figure never names, and the answer opens the next states" do
    open_card(9, size: [ 390, 844 ])
    within("#scheda-9") do
      assert_no_button "Passo avanti" # the steps drive the figure
      click_button "Mostra il primo passo"
      assert_selector ".dg-op", text: "Il nucleo"
      assert_selector ".dg-cp-nucleus.is-lit", minimum: 2
      click_button "Mostra tutto"
      assert_selector ".step-blank", visible: :visible
      assert_selector ".dg-op", text: "Parete e cloroplasti" # the state of the blank's step waits for its answer
      find(".dg-desc summary").click
      assert_text "La seconda, Seconda cellula:"
      assert_no_match(/animale|vegetale/, find(".dg-desc p").text, "the description does not answer the blank")
      all(".dg-hit", visible: :all).each { |b| assert_no_match(/animale|vegetale/, b["aria-label"]) }
      find("label.option", text: "un batterio").click
      click_button "Controlla"
      assert_selector ".verdict-wrong", wait: 5
      assert_text "Ha il nucleo: non è un batterio."
      find("label.option", text: "animale, per esempio della guancia").click
      click_button "Controlla"
      assert_selector ".verdict-right", wait: 5
      assert_selector ".dg-op", text: "Intorno solo la membrana" # the server's figure has the states of the steps now open
      click_button "Mostra il passo successivo"
      assert_selector ".dg-op", text: "I mitocondri"
      assert_selector ".example-result", text: "La prima è di una foglia"
    end
  end

  test "select over two cells: the first cell's parts then the second's, no chips, the answer graded" do
    open_card(10, size: [ 390, 844 ])
    within("#scheda-10") do
      assert_selector ".dg-target", count: 10
      assert_no_selector ".dg-chipbtn" # two cells that differ: the comparison is never offered in a select check
      assert_no_text "Solo le differenze"
      html = find(".dg")["outerHTML"]
      PART_NAMES.each { |p| assert_no_match(/dg-cp-#{p}\b|:#{p}\b/, html, "the select figure names #{p}") }
      find(".dg-target[data-target='t8']").click # the nucleus of the cheek cell alone
      click_button "Controlla"
      assert_selector ".verdict-wrong", wait: 5
      assert_text "Anche il batterio ha il DNA"
      find(".dg-target[data-target='t4']").click # and the nucleoid of the bacterium
      click_button "Controlla"
      assert_selector ".verdict-right", wait: 5
    end
  end

  test "nested: the focus moves out level by level; select over the levels keeps the examples and hides the names" do
    open_card(11, size: [ 390, 844 ])
    assert_selector "#scheda-11 .dg-nbox", count: 5
    assert_selector "#scheda-11 .dg-nbox.is-focus", count: 1
    assert_selector "#scheda-11 .dg-nname-focus", text: "cellula"
    click_button "Passo avanti"
    assert_selector "#scheda-11 .dg-nname-focus", text: "tessuto"
    assert_selector "#scheda-11 .dg-ninside-name", text: "organuli"
    open_card(12)
    assert_selector "#scheda-12 .dg-target", count: 5
    within("#scheda-12 .dg") do
      assert_text "il cervello"
      assert_no_text "organo"
    end
    find("#scheda-12 .dg-target[data-target='t4']").click
    click_button "Controlla"
    assert_selector "#scheda-12 .verdict-wrong", wait: 5
    find("#scheda-12 .dg-target[data-target='t3']").click
    click_button "Controlla"
    assert_selector "#scheda-12 .verdict-right", wait: 5
  end

  test "reduced motion: the arrow of a state appears without the fade, the parts without a transition" do
    page.driver.browser.page.command("Emulation.setEmulatedMedia", media: "", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    open_card(3)
    assert page.evaluate_script("matchMedia('(prefers-reduced-motion: reduce)').matches")
    click_button "Passo avanti"
    assert_selector "#scheda-3 .dg-cpath", count: 1
    assert_no_selector "#scheda-3 .dg-enter"
    assert_equal "0s", page.evaluate_script("getComputedStyle(document.querySelector('#scheda-3 .dg-cp')).transitionDuration")
  end

  test "screenshots for the look gate: every card at 390 and 1280 px, cream and dark, with no overflow" do
    [ [ 390, 844 ], [ 1280, 900 ] ].each do |w, h|
      %w[cream dark].each do |theme|
        (1..12).each do |n|
          open_card(n, size: [ w, h ])
          page.execute_script("document.documentElement.dataset.theme = '#{theme}'")
          find("#scheda-9 button", text: "Mostra tutto").click if n == 9 # the example's steps up to its blank
          if [ 1, 3, 5, 11 ].include?(n) # the figures with states: the last one
            count = page.evaluate_script("Number(document.querySelector('#scheda-#{n} .dg').dataset.states)") - 1
            count.times { find("#scheda-#{n} button", text: "Passo avanti").click }
          end
          find("#scheda-2 .dg-chipbtn").click if n == 2
          overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
          assert_operator overflow, :<=, 0, "card #{n} at #{w} in #{theme} scrolls sideways"
          assert_no_selector "#scheda-#{n} .dg-failed"
          # in a full-page shot the bars stay where the window is: the top one at the top, the bottom one after the card, not over the figure
          page.execute_script("document.querySelectorAll('.l2-bar').forEach((n) => { n.style.position = 'static' }); window.scrollTo(0, 0)")
          wait_for_lesson_ready
          sleep 0.5 # the moves of a new state (250 ms) are over before the shot
          shot("#{w}-#{theme}-card#{n}")
        end
      end
    end
  end
end
