require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/graph_map_rows"
require_relative "../support/finished_run"

# The map of the skill graph on the graph page and on the report page (D-221).
class TeacherGraphMapPageTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include GraphMapRows
  include FinishedRun

  setup do
    Teacher::GraphMap.reset_cache!
    @world = build_ui_subject(components: %w[number choice short_answer], approve: false)
    @subject = @world[:subject]
    @big = build_big_graph!(@world)
  end

  def page(path, headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  test "the graph page draws every skill, the edges, the legend and the list below" do
    page "/teacher/subjects/math/graph"
    assert_response :success
    assert_select "section#graph-map svg.gm-svg"
    assert_select "svg a.gm-node.gm-skill", count: GraphMapRows::SKILLS.size
    assert_select "svg a.gm-node.gm-stub[data-key='science.data']", count: 1
    assert_select "svg path.gm-edge[data-from='math.number'][data-to='math.choice']"
    assert_select "svg.gm-svg path.gm-edge-composite[data-from='math.angles'][data-to='math.geometry-algebra']", count: 1
    assert_select "#graph-map-legend", /Come si legge/
    assert_select "#graph-map-legend", /Studiata/
    assert_select "#graph-map-legend", /tratteggiato/
    assert_select "h2#graph-list", "Elenco completo"
    assert_select "article.skill", count: GraphMapRows::SKILLS.size
    assert_select "a.gm-node[data-key='math.fractions'][href='#skill-math-fractions']"
    assert_select "a.gm-node[data-key='math.number'] title", /Operazioni con i numeri interi \(math.number\)\. ★ Studiata/
  end

  test "encoding: dashed border for the inferred, a badge for the pinned, a mark for the entry, a dot for the new" do
    approve_graph_row!(@subject, SkillGraphRevision.where(subject: @subject).order(:seq).first)
    page "/teacher/subjects/math/graph"
    assert_select "a.gm-node[data-key='math.decimals'][data-inferred=true] rect.gm-inferred"
    assert_select "a.gm-node[data-key='math.number'][data-inferred=false] rect.gm-inferred", count: 0
    assert_select "a.gm-node[data-key='math.number'][data-pinned='1'][data-facet=studied] circle.gm-badge"
    assert_select "a.gm-node[data-key='math.number'] .gm-tab-text", "inizio"
    assert_select "a.gm-node[data-key='math.fractions'] rect.gm-fill-studied"
    assert_select "a.gm-node[data-key='math.decimals'] rect.gm-fill-middle_school"
    assert_select "a.gm-node[data-key='math.inequalities'] rect.gm-fill-not_in_prima"
    assert_select "a.gm-node[data-change=added] circle.gm-dot", minimum: 1
  end

  test "the panel templates carry everything about a skill" do
    page "/teacher/subjects/math/graph"
    template = css_select("template[data-key='math.fractions']").first
    html = Nokogiri::HTML.fragment(template.inner_html).to_html
    assert_includes html, "Frazioni e operazioni con le frazioni"
    assert_includes html, "Riga di prova numero 3 del programma di prima"
    assert_includes html, "Riga di prova 2 del programma di seconda"
    assert_includes html, "Errore tipico di prova"
    assert_includes html, "/teacher/refs/math.fractions"
    assert_includes html, "#skill-math-fractions"
    assert_match(/data-key="math.mcm"/, html, "prerequisites are buttons")
    assert_match(/data-key="math.proportions"/, html, "what builds on it are buttons")
    number = Nokogiri::HTML.fragment(css_select("template[data-key='math.number']").first.inner_html).to_html
    assert_includes number, "/teacher/subjects/math/test/skills/math.number"
    assert_includes number, "/teacher/subjects/math/test/all#skill-math-number"
    assert_match(%r{/teacher/refs/ui-number-}, number, "the pinned item links to its card")
    decimals = Nokogiri::HTML.fragment(css_select("template[data-key='math.decimals']").first.inner_html).to_html
    assert_includes decimals, "Nessuna riga di programma"
  end

  test "the second year is a column of lines grouped by section, hidden until asked" do
    page "/teacher/subjects/math/graph"
    assert_select "a.gm-sec.gm-seconda-part", minimum: 10
    assert_select "path.gm-edge-seconda", minimum: 10
    assert_select "input#gm-seconda"
    assert_select "template[data-key^='seconda:']", minimum: 10
  end

  test "no inline style, no handler, no script of its own in the map" do
    page "/teacher/subjects/math/graph"
    map = css_select("#graph-map").first
    assert_empty map.css("[style]")
    assert_empty map.css("script")
    assert_empty(map.xpath(".//@*[starts-with(name(), 'on')]"))
    assert_no_match(/javascript:/, map.to_html)
  end

  test "a cycle shows a visible warning and the page still answers" do
    SkillGraphRevision.create!(subject: @subject, seq: 9, author_session: AgentSession.find_by!(label: "ui-author"), body_json: {
      schema: "banco.skill_graph/1", subject: "math", skills: [
        { key: "math.a", label_it: "A", layer: "core", scope: "studied", prerequisites: [ "math.b" ], refs: [], errors: [] },
        { key: "math.b", label_it: "B", layer: "core", scope: "studied", prerequisites: [ "math.a" ], refs: [], errors: [] }
      ]
    }.to_json)
    page "/teacher/subjects/math/graph"
    assert_response :success
    assert_select "p.notice[data-map-warning=cycle]", /giro chiuso/
    assert_select "path.gm-edge-warning", count: 1
    assert_select "p.notice[data-map-warning=cycle]", text: "Il grafo ha un giro chiuso tra B e A. La freccia è tratteggiata e passa sotto: va corretto."
  end

  test "a self loop and an unknown prerequisite are visible warnings with their own text" do
    SkillGraphRevision.create!(subject: @subject, seq: 9, author_session: AgentSession.find_by!(label: "ui-author"), body_json: {
      schema: "banco.skill_graph/1", subject: "math", skills: [
        { key: "math.a", label_it: "A", layer: "core", scope: "studied", prerequisites: [ "math.a", "math.ghost" ], refs: [], errors: [] }
      ]
    }.to_json)
    page "/teacher/subjects/math/graph"
    assert_response :success
    assert_select "p.notice[data-map-warning=self_loop]", text: "L'abilità A richiede se stessa. Va corretto."
    assert_select "p.notice[data-map-warning=unknown_prerequisite]", text: "L'abilità A richiede math.ghost, che non è nel grafo. Va corretto."
  end

  test "the map has no form of its own" do
    page "/teacher/subjects/math/graph"
    assert_response :success
    assert_select "#graph-map form", count: 0
  end

  test "a guest sees the whole map read-only: no form anywhere on the page, the panel templates carry no form either" do
    saved = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS", "BANCO_GUEST_USERS")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    ENV["BANCO_TEACHER_USERS"] = "nik"
    ENV["BANCO_GUEST_USERS"] = "guest-a@example.test"
    guest = { "Remote-User" => "guest-a@example.test", "Remote-Groups" => "banco-guest" }
    page "/teacher/subjects/math/graph", headers: guest
    assert_response :success
    assert_select "svg a.gm-node.gm-skill", count: GraphMapRows::SKILLS.size
    assert_select "#graph-map-legend"
    assert_select "form", count: 0
    assert_select "template[data-key='math.fractions']", count: 1
    assert_empty css_select("template").select { |t| t.inner_html.include?("<form") }
  ensure
    %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS BANCO_GUEST_USERS].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  test "a subject without a graph has no map" do
    other = Subject.create!(key: "history", name_it: "Storia", position: 5)
    page "/teacher/subjects/#{other.key}/graph"
    assert_response :success
    assert_select "#graph-map", count: 0
  end

  test "the report map is coloured by the student's states, with its own legend and evidence" do
    Teacher::GraphMap.reset_cache!
    world = build_ui_subject(key: "lang", name: "Lingua", components: %w[number choice short_answer], position: 2)
    release_diagnosis!
    play_run(world[:student], world[:subject])
    page "/teacher/subjects/lang/report"
    assert_response :success
    report = Diagnosis::Report.call(subject: world[:subject], student: world[:student])[:subjects].first
    assert_operator report[:skills].size, :==, 3
    report[:skills].each do |row|
      state = GraphMapHelper.instance_method(:gm_state).bind_call(Object.new, row)
      assert_select "a.gm-node[data-key='#{row[:skill]}'][data-facet=#{state}] rect.gm-fill-#{state}"
    end
    assert_select "#graph-map-legend", /Dimostrata/
    assert_select "#graph-map-legend", /Da recuperare/
    assert_select "#graph-map-legend", /Non valutata/
    assert_select "#graph-map-legend", /In correzione/
    assert_select "template[data-key='lang.number'] .gm-evidence", /domande fatte|domanda fatta/
    assert_select "a.gm-node[data-key='lang.number'] title", /Da recuperare|Dimostrata|Non valutata|In correzione|Non serve/
  end

  test "the report has no map before the student has a run" do
    page "/teacher/subjects/math/report"
    assert_response :success
    assert_select "#graph-map", count: 0
  end
end
