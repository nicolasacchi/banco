require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/graph_map_rows"
require_relative "../support/student_session"
require_relative "../support/finished_run"

# The map of the skill graph in Chrome (D-221): select by click and by Enter, the panel, the
# highlight, Esc, the filters, the second year's column, zoom. With GRAPH_MAP_SHOTS=<dir> it also
# saves screenshots of the map at a laptop and a phone size.
class GraphMapSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include GraphMapRows
  include StudentSession
  include FinishedRun

  setup do
    @world = build_ui_subject(components: %w[number choice], approve: false)
    @subject = @world[:subject]
    build_big_graph!(@world)
    sign_in_as :teacher
  end

  teardown { sign_out_env }

  def node(key) = find("a.gm-node[data-key='#{key}']", visible: :all)

  # The whole map section at the width asked for: the window is made as tall as the section.
  def shoot(path, width)
    height = page.evaluate_script("Math.ceil(document.getElementById('graph-map').getBoundingClientRect().bottom + window.scrollY + 20)")
    page.driver.resize(width, height)
    page.save_screenshot(path)
    page.driver.resize(width, 900)
  end

  def open_filters = find("summary", text: "Filtri").click

  def press(key) = page.driver.browser.keyboard.type(key)

  test "a click selects a node: the chain is marked, the rest dimmed, the panel says everything" do
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    assert_selector "#graph-map .gm-panel", visible: :hidden
    node("math.polynomials").click
    assert_selector "#graph-map.gm-has-selection"
    assert_selector "a.gm-node.gm-sel[data-key='math.polynomials']"
    assert_selector "a.gm-node.gm-up[data-key='math.monomials']"
    assert_selector "a.gm-node.gm-up[data-key='math.number']"
    assert_selector "a.gm-node.gm-down[data-key='math.notable']"
    assert_selector "a.gm-node.gm-down[data-key='math.word-problems']"
    assert_no_selector "a.gm-node.gm-up[data-key='math.angles']"
    assert_no_selector "a.gm-node.gm-down[data-key='math.angles']"
    assert_selector "path.gm-edge.gm-hot", minimum: 4
    assert_equal "0.38", page.evaluate_script("getComputedStyle(document.querySelector(\"a.gm-node[data-key='math.angles']\")).opacity")
    within ".gm-panel" do
      assert_selector "h3", text: "Polinomi: somma, differenza e prodotto"
      assert_text "Riga di prova numero 5 del programma di prima"
      assert_text "Riga di prova 4 del programma di seconda"
      assert_text "Errore tipico di prova"
      assert_link "Scheda nell'elenco completo", href: "#skill-math-polynomials"
      assert_link "Apri la scheda", href: "/teacher/refs/math.polynomials"
      click_button "Monomi e operazioni con i monomi"
    end
    assert_selector "a.gm-node.gm-sel[data-key='math.monomials']"
    assert_no_selector "a.gm-node.gm-sel[data-key='math.polynomials']"
    assert_selector ".gm-panel h3", text: "Monomi e operazioni con i monomi"
  end

  test "Enter selects, Esc clears" do
    visit "/teacher/subjects/math/graph"
    node("math.fractions").send_keys(:enter)
    assert_selector "a.gm-node.gm-sel[data-key='math.fractions']"
    assert_selector ".gm-panel h3", text: "Frazioni e operazioni con le frazioni"
    press :escape
    assert_no_selector "a.gm-node.gm-sel"
    assert_no_selector "#graph-map.gm-has-selection"
    assert_selector ".gm-panel", visible: :hidden
    assert_equal "math.fractions", page.evaluate_script("document.activeElement.dataset.key")
  end

  test "the panel opens over the map with focus inside; Chiudi and Esc close it and give the focus back to the node" do
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    node("math.fractions").click
    assert_selector ".gm-panel h3", text: "Frazioni e operazioni con le frazioni"
    assert page.evaluate_script("document.querySelector('.gm-panel').contains(document.activeElement)")
    map_width = page.evaluate_script("document.querySelector('.gm-scroll').getBoundingClientRect().width")
    panel = page.evaluate_script("(() => { const r = document.querySelector('.gm-panel').getBoundingClientRect(); const b = document.querySelector('.gm-scroll').getBoundingClientRect(); return [r.right, b.right, r.left, b.left] })()")
    assert_in_delta panel[0], panel[1], 3
    assert_operator panel[2], :>, panel[3] + map_width / 2
    press :tab
    assert page.evaluate_script("document.querySelector('.gm-panel').contains(document.activeElement)")
    click_button "Chiudi"
    assert_selector ".gm-panel", visible: :hidden
    assert_no_selector "#graph-map.gm-has-selection"
    assert_equal "math.fractions", page.evaluate_script("document.activeElement.dataset.key")
  end

  test "selecting a node does not move the page and does not change the zoom" do
    page.driver.resize(1366, 700)
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    page.execute_script("window.scrollTo(0, 120)")
    scroll = page.evaluate_script("window.scrollY")
    assert_operator scroll, :>, 0
    width = page.evaluate_script("document.querySelector('.gm-svg').getBoundingClientRect().width")
    node("math.polynomials").trigger("click")
    assert_selector ".gm-panel h3"
    assert_equal scroll, page.evaluate_script("window.scrollY")
    assert_in_delta width, page.evaluate_script("document.querySelector('.gm-svg').getBoundingClientRect().width"), 1
    page.execute_script("document.querySelector(\"a.gm-node[data-key='math.monomials']\").focus({preventScroll: true})")
    press :enter
    assert_selector "a.gm-node.gm-sel[data-key='math.monomials']"
    assert_equal scroll, page.evaluate_script("window.scrollY")
    press :escape
    assert_selector ".gm-panel", visible: :hidden
    assert_equal scroll, page.evaluate_script("window.scrollY")
    page.driver.resize(1280, 900)
  end

  test "a node under the panel is scrolled into the part of the map the panel leaves free" do
    visit "/teacher/subjects/math/graph"
    node("math.systems").click
    assert_selector ".gm-panel h3"
    free = page.evaluate_script("(() => { const n = document.querySelector(\"a.gm-node[data-key='math.systems'] rect\").getBoundingClientRect(); const p = document.querySelector('.gm-panel').getBoundingClientRect(); return [n.right, p.left] })()")
    assert_operator free[0], :<=, free[1] + 1
  end

  test "the map comes first: the approval box and the summary are below it; one row of controls above" do
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    tops = page.evaluate_script("['graph-map', 'graph-approve', 'graph-summary'].map(id => document.getElementById(id).getBoundingClientRect().top)")
    assert_operator tops[0], :<, tops[1]
    assert_operator tops[0], :<, tops[2]
    assert_operator page.evaluate_script("document.querySelector('.gm-scroll').getBoundingClientRect().top"), :<, 520
    rows = page.evaluate_script("Array.from(document.querySelectorAll('.gm-bar > *')).map(e => { const r = e.getBoundingClientRect(); return (r.top + r.bottom) / 2 })")
    assert_operator rows.max - rows.min, :<, 20
    assert_equal false, page.evaluate_script("document.getElementById('graph-map-howto').open")
    assert_button "Approva il grafo"
  end

  test "the second year is a column that the toggle adds" do
    visit "/teacher/subjects/math/graph"
    width = -> { page.evaluate_script("document.querySelector('.gm-svg').getBoundingClientRect().width") }
    narrow = width.call
    assert_no_selector "a.gm-sec", visible: :visible
    open_filters
    check "Mostra cosa serve in seconda"
    assert_selector "a.gm-sec", minimum: 10
    assert_operator width.call, :>, narrow + 100
    node("math.lines").click
    assert_selector "a.gm-sec.gm-down", minimum: 1
    uncheck "Mostra cosa serve in seconda"
    assert_no_selector "a.gm-sec", visible: :visible
    assert_in_delta narrow, width.call, 1
  end

  test "the filters hide nodes and their edges" do
    visit "/teacher/subjects/math/graph"
    total = GraphMapRows::SKILLS.size
    assert_selector "a.gm-skill:not(.gm-hidden)", count: total
    open_filters
    fill_in "Cerca per nome", with: "frazioni"
    assert_selector "a.gm-skill:not(.gm-hidden)", minimum: 1, maximum: 5
    assert_selector "a.gm-node.gm-hidden[data-key='math.angles']", visible: :all
    assert_selector ".gm-controls [role=status]", text: /abilit/
    fill_in "Cerca per nome", with: ""
    check "Solo quelle senza riga di programma"
    assert_selector "a.gm-skill:not(.gm-hidden)", count: GraphMapRows::SKILLS.count { |_, v| v[3].empty? }
    assert_selector "path.gm-edge.gm-hidden", minimum: 1, visible: :all
    uncheck "Solo quelle senza riga di programma"
    check "Solo quelle nel test"
    assert_selector "a.gm-skill:not(.gm-hidden)", count: 2
    uncheck "Solo quelle nel test"
    uncheck "Non in prima"
    assert_selector "a.gm-skill.gm-hidden[data-scope=not_in_prima]", minimum: 1, visible: :all
    assert_no_selector "a.gm-skill:not(.gm-hidden)[data-scope=not_in_prima]"
  end

  test "a tap after a drag on the background still selects a node" do
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    page.execute_script("document.querySelector('.gm-svg').dispatchEvent(new PointerEvent('pointerdown', {clientX: 200, button: 0, bubbles: true}));" \
                        "document.querySelector('.gm-svg').dispatchEvent(new PointerEvent('pointermove', {clientX: 230, bubbles: true}));" \
                        "document.querySelector('.gm-svg').dispatchEvent(new PointerEvent('pointerup', {bubbles: true}))")
    node("math.fractions").click
    assert_selector "a.gm-node.gm-sel[data-key='math.fractions']"
  end

  test "the report map shows the evidence of a skill on click" do
    world = build_ui_subject(key: "lang", name: "Lingua", components: %w[number choice short_answer], position: 2)
    release_diagnosis!
    play_run(world[:student], world[:subject])
    visit "/teacher/subjects/lang/report"
    assert_selector "#graph-map.gm-ready"
    node("lang.number").click
    assert_selector "a.gm-node.gm-sel[data-key='lang.number']"
    assert_selector ".gm-panel .gm-evidence", text: /domande fatte|domanda fatta/
  end

  test "zoom scales the map; the fit button says Ingrandisci while fitted and Adatta when it is not" do
    page.driver.resize(1366, 900)
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    width = -> { page.evaluate_script("document.querySelector('.gm-svg').getBoundingClientRect().width") }
    box = -> { page.evaluate_script("document.querySelector('.gm-scroll').clientWidth") }
    start = width.call
    assert_operator start, :<=, box.call + 1
    assert_selector "button.gm-fit[data-state=fitted]", text: "Ingrandisci"
    click_button "Ingrandisci"
    assert_operator width.call, :>, box.call
    assert_selector "button.gm-fit[data-state=zoomed]", text: "Adatta"
    click_button "Adatta"
    assert_in_delta start, width.call, 2
    find("button[aria-label='Zoom avanti']").click
    assert_operator width.call, :>, start * 1.2
    assert_selector "button.gm-fit", text: "Adatta"
    find("button[aria-label='Zoom indietro']").click
    assert_in_delta start, width.call, 2
    find("button[aria-label='Zoom avanti']").click
    click_button "Adatta"
    assert_operator width.call, :<=, box.call + 1
    assert_equal 0, page.evaluate_script("document.querySelector('.gm-scroll').scrollLeft")
    page.driver.resize(1280, 900)
  end

  test "Tab walks through the nodes in order and Enter selects the focused one" do
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    order = page.evaluate_script("Array.from(document.querySelectorAll('a.gm-node')).map(n => n.dataset.key)")
    page.execute_script("document.querySelectorAll('a.gm-node')[0].focus()")
    assert_equal order[0], page.evaluate_script("document.activeElement.dataset.key")
    order.first(4).drop(1).each do |expected|
      press :tab
      assert_equal expected, page.evaluate_script("document.activeElement.dataset.key")
    end
    press :enter
    assert_selector "a.gm-node.gm-sel[data-key='#{order[3]}']"
    assert_selector ".gm-panel h3"
    press :escape
    assert_no_selector "a.gm-node.gm-sel"
  end

  FIT_JS = "(() => { const b = document.querySelector('.gm-scroll'); const s = document.querySelector('.gm-svg'); " \
           "return [s.getBoundingClientRect().width, b.clientWidth, b.scrollLeft, document.querySelector('.gm-scroll-hint').hidden] })()".freeze

  test "on a desktop a map whose text stays readable opens fitted to the width, without the scroll hint" do
    build_wide_graph!(@world, levels: 5)
    page.driver.resize(1366, 900)
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    width, box, left, hint_hidden = page.evaluate_script(FIT_JS)
    assert_operator width, :<=, box + 1
    assert_operator width / box, :>, 0.9
    assert_equal 0, left
    assert_equal true, hint_hidden
    page.driver.resize(1280, 900)
  end

  test "on a desktop a map too wide to read fitted keeps natural size and the scroll hint; the inferred note is plain text" do
    build_wide_graph!(@world, levels: 12)
    page.driver.resize(1366, 900)
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    width, box, left, hint_hidden = page.evaluate_script(FIT_JS)
    assert_operator width, :>, box
    assert_equal 0, left
    assert_equal false, hint_hidden
    assert_selector "button.gm-fit", text: "Adatta"
    node("math.w9").click
    assert_selector ".gm-panel h3"
    assert_equal "400", page.evaluate_script("getComputedStyle(document.querySelector('.gm-panel .gm-note')).fontWeight")
    page.driver.resize(1280, 900)
  end

  test "on a phone the map scrolls and starts at the first entry skill, with the hint shown" do
    page.driver.resize(390, 844)
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    data = page.evaluate_script("(() => { const b = document.querySelector('.gm-scroll'); const s = document.querySelector('.gm-svg'); const tabs = Array.from(document.querySelectorAll('.gm-tab')).map(t => Number(t.getAttribute('x')) - 14); return [s.getBoundingClientRect().width, b.clientWidth, b.scrollLeft, Math.max(0, Math.min(...tabs) - 16), document.querySelector('.gm-scroll-hint').hidden] })()")
    assert_operator data[0], :>, data[1]
    assert_in_delta data[3], data[2], 1
    assert_equal false, data[4]
    page.driver.resize(1280, 900)
  end

  test "on a phone the panel opens under the map and the page scrolls to it" do
    page.driver.resize(390, 844)
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    node("math.polynomials").trigger("click")
    assert_selector ".gm-panel h3"
    data = page.evaluate_script("(() => { const p = document.querySelector('.gm-panel').getBoundingClientRect(); const b = document.querySelector('.gm-scroll').getBoundingClientRect(); return [p.top, b.bottom, window.innerHeight, p.width] })()")
    assert_operator data[0], :>=, data[1] - 1
    assert_operator data[0], :<, data[2]
    assert_operator data[3], :>, 300
    click_button "Chiudi"
    assert_selector ".gm-panel", visible: :hidden
    page.driver.resize(1280, 900)
  end

  test "screenshots of two graphs at two sizes" do
    dir = ENV["GRAPH_MAP_SHOTS"].to_s
    skip "GRAPH_MAP_SHOTS is not set" if dir.empty?
    FileUtils.mkdir_p(dir)
    { "school" => nil, "wide" => :wide }.each do |name, shape|
      build_wide_graph!(@world, levels: 5) if shape == :wide
      [ [ 1366, 900 ], [ 390, 844 ] ].each do |w, h|
        page.driver.resize(w, h)
        visit "/teacher/subjects/math/graph"
        assert_selector "#graph-map.gm-ready"
        shoot(File.join(dir, "#{name}-#{w}x#{h}.png"), w)
        node(name == "wide" ? "math.w14" : "math.polynomials").trigger("click")
        if name == "school" && w > 1000
          open_filters
          check "Mostra cosa serve in seconda"
          open_filters
        end
        page.execute_script("window.scrollTo(0, 0)")
        shoot(File.join(dir, "#{name}-#{w}x#{h}-selected.png"), w)
      end
    end
    page.driver.resize(1280, 900)
  end
end
