require "application_system_test_case"
require_relative "../support/decision_world"
require_relative "../support/graph_map_rows"
require_relative "../support/student_session"

# The map of the skill graph in Chrome (D-221): select by click and by Enter, the panel, the
# highlight, Esc, the filters, the second year's column, zoom. With GRAPH_MAP_SHOTS=<dir> it also
# saves screenshots of the map at a laptop and a phone size.
class GraphMapSystemTest < ApplicationSystemTestCase
  include DecisionWorld
  include GraphMapRows
  include StudentSession

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

  def press(key) = page.driver.browser.keyboard.type(key)

  test "a click selects a node: the chain is marked, the rest dimmed, the panel says everything" do
    visit "/teacher/subjects/math/graph"
    assert_selector "#graph-map.gm-ready"
    assert_selector "#graph-map .gm-panel", text: "Scegli un'abilità sulla mappa"
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
    assert_equal "0.22", page.evaluate_script("getComputedStyle(document.querySelector(\"a.gm-node[data-key='math.angles']\")).opacity")
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
    assert_selector ".gm-panel", text: "Scegli un'abilità sulla mappa"
  end

  test "the second year is a column that the toggle adds" do
    visit "/teacher/subjects/math/graph"
    width = -> { page.evaluate_script("document.querySelector('.gm-svg').getBoundingClientRect().width") }
    narrow = width.call
    assert_no_selector "a.gm-sec", visible: :visible
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

  test "zoom scales the map, fit shows it whole" do
    visit "/teacher/subjects/math/graph"
    width = -> { page.evaluate_script("document.querySelector('.gm-svg').getBoundingClientRect().width") }
    start = width.call
    find("button[aria-label=Ingrandisci]").click
    assert_operator width.call, :>, start * 1.2
    find("button[aria-label=Riduci]").click
    assert_in_delta start, width.call, 2
    click_button "Adatta"
    box = page.evaluate_script("document.querySelector('.gm-scroll').clientWidth")
    assert_operator width.call, :<=, box + 1
    assert_equal 0, page.evaluate_script("document.querySelector('.gm-scroll').scrollLeft")
  end

  test "screenshots of two graphs at two sizes" do
    dir = ENV["GRAPH_MAP_SHOTS"].to_s
    skip "GRAPH_MAP_SHOTS is not set" if dir.empty?
    FileUtils.mkdir_p(dir)
    { "school" => nil, "wide" => :wide }.each do |name, shape|
      build_wide_graph!(@world) if shape == :wide
      [ [ 1366, 900 ], [ 390, 844 ] ].each do |w, h|
        page.driver.resize(w, h)
        visit "/teacher/subjects/math/graph"
        assert_selector "#graph-map.gm-ready"
        shoot(File.join(dir, "#{name}-#{w}x#{h}.png"), w)
        node(name == "wide" ? "math.w14" : "math.polynomials").trigger("click")
        check "Mostra cosa serve in seconda" if name == "school" && w > 1000
        shoot(File.join(dir, "#{name}-#{w}x#{h}-selected.png"), w)
      end
    end
    page.driver.resize(1280, 900)
  end
end
