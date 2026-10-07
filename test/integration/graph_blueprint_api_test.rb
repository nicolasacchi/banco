require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"

# The skill graph, the entry test, the coverage and the status of a subject over the API.
class GraphBlueprintApiTest < ActionDispatch::IntegrationTest
  include CourseRows
  F = ValidationFixtures

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "graph test")
    @subject = Subject.create!(key: "math", name_it: "Matematica", position: 1)
    @italian = Subject.create!(key: "italian", name_it: "Italiano", position: 2)
    @source = SyllabusSource.create!(key: "prima-test", line_count: 3, sha256: "0" * 64)
    SyllabusLine.create!(syllabus_source: @source, number: 1, text: "operazioni con i numeri relativi", origin: "pdf")
    SyllabusLine.create!(syllabus_source: @source, number: 2, text: "PAGINA 2", origin: "transcript")
    SyllabusLine.create!(syllabus_source: @source, number: 3, text: "una riga non citata", origin: "pdf")
    seconda = SyllabusSource.create!(key: "seconda-test", line_count: 1, sha256: "1" * 64)
    SyllabusLine.create!(syllabus_source: seconda, number: 1, text: "equazioni di primo grado", origin: "pdf")
  end

  def api(path, method: :get, body: nil, dry: false)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Banco-Dry-Run"] = "1" if dry
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  def graph(&edit)
    doc = JSON.parse(JSON.generate(F::GRAPH))
    edit&.call(doc)
    doc
  end

  # The test programme is the source the graph cites.
  def programme(&) = Validation::Rules.with(coverage: { prima_source: "prima-test", ranges: { math: [ 1, 3 ] } }, &)

  def submit_graph(doc, dry: false, subject: "math")
    programme { api("/api/v1/subjects/#{subject}/skill-graph", method: :post, body: { graph: doc }, dry: dry) }
  end

  def skill(doc, key) = doc["skills"].find { |s| s["key"] == key }

  # ---- the programme lines -------------------------------------------------------------

  test "syllabus lines: a range of lines with their origin, transcriber lines marked not citable" do
    api("/api/v1/syllabus/prima-test/lines?from=1&to=2")
    assert_response :ok
    record_example "syllabus lines", "range"
    assert_equal [ 1, 2 ], json["rows"].map { |r| r["line"] }
    assert_equal [ true, false ], json["rows"].map { |r| r["citable"] }
    assert_equal "operazioni con i numeri relativi", json["rows"].first["text"]
    api("/api/v1/syllabus/prima-test/lines")
    assert_equal 3, json["rows"].size
  end

  test "syllabus lines: unknown source is 404, a bad range is 422" do
    api("/api/v1/syllabus/nothing/lines")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    api("/api/v1/syllabus/prima-test/lines?from=5&to=2")
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    api("/api/v1/syllabus/prima-test/lines?from=x")
    assert_equal "E-FILES", json["code"]
    api("/api/v1/syllabus/prima-test/lines?from=1&to=900")
    assert_equal "E-FILES", json["code"]
  end

  # ---- the graph --------------------------------------------------------------------

  test "a good graph is stored; the same graph again is a replay; --dry-run stores nothing" do
    submit_graph(graph, dry: true)
    assert_response :ok
    assert_equal true, json["dry_run"]
    assert_equal 0, SkillGraphRevision.count

    submit_graph(graph)
    assert_response :created, json.inspect
    record_example "skill-graph submit", "created"
    assert_equal 1, json["seq"]
    assert_equal false, json["replayed"]
    submit_graph(graph)
    assert_response :ok
    assert_equal true, json["replayed"]
    assert_equal 1, SkillGraphRevision.count
    changed = graph { |d| skill(d, "math.percentages")["label_it"] = "Le percentuali" }
    submit_graph(changed)
    assert_equal 2, json["seq"]
  end

  test "E-SCHEMA, with nothing stored" do
    submit_graph(graph { |d| d.delete("skills") })
    assert_response :unprocessable_entity
    assert_equal "E-SCHEMA", json["code"]
    assert_equal 0, SkillGraphRevision.count
    submit_graph(graph { |d| d["subject"] = "italian" })
    assert_includes json["codes"], "E-SCHEMA"
    submit_graph(graph { |d| skill(d, "math.percentages")["key"] = "italian.percentages" })
    assert_includes json["codes"], "E-SCHEMA"
  end

  test "E-GRAPH-CYCLE comes first, with the path" do
    doc = graph { |d| skill(d, "math.integer-operations")["prerequisites"] = [ "math.percentages" ] }
    submit_graph(doc, dry: true)
    assert_response :unprocessable_entity
    assert_equal "E-GRAPH-CYCLE", json["code"]
    record_example "skill-graph submit", "cycle"
    assert_equal true, json["dry_run"]
    assert_match(/->/, json["message"])
    assert_equal 0, SkillGraphRevision.count
  end

  test "E-SOURCE: a missing line, a transcriber line, a fragment that is not a substring" do
    {
      ->(d) { skill(d, "math.percentages")["refs"][0]["line"] = 99 } => "missing_line",
      ->(d) { skill(d, "math.percentages")["refs"][0]["line"] = 2 } => "transcript",
      ->(d) { skill(d, "math.percentages")["refs"][0]["fragment"] = "una frase inventata" } => "fragment",
      ->(d) { d["excluded"] = [ { "line" => 77, "reason_it" => "Non esiste." } ] } => "missing_line"
    }.each do |edit, rule|
      submit_graph(graph(&edit))
      assert_includes json["codes"], "E-SOURCE", rule
      assert(json["findings"].any? { |f| f["code"] == "E-SOURCE" && f["detail"]["rule"] == rule }, rule)
    end
  end

  test "E-SCOPE: a middle_school skill with previous-year citations, a studied one without" do
    submit_graph(graph { |d| skill(d, "math.percentages").merge!("scope" => "middle_school", "scope_reason_it" => "Dalle medie.") })
    assert_includes json["codes"], "E-SCOPE"
    submit_graph(graph { |d| skill(d, "math.percentages")["refs"] = skill(d, "math.percentages")["refs"].reject { |r| r["source"] == "prima-test" } })
    assert_includes json["codes"], "E-SCOPE"
  end

  test "E-NEEDED-BY: a skill that nothing in the next year needs" do
    submit_graph(graph { |d| d["skills"] << F.skill_row("math.orphan", "Orfana", needed: false) })
    assert_includes json["codes"], "E-NEEDED-BY"
    assert(json["findings"].any? { |f| f["code"] == "E-NEEDED-BY" && f["detail"]["skill"] == "math.orphan" })
  end

  test "E-SKILL-UNKNOWN and E-GRAPH-EDGE-UNAPPROVED: edges to skills that are not there" do
    submit_graph(graph { |d| skill(d, "math.percentages")["prerequisites"] << "math.nothing" })
    assert_includes json["codes"], "E-SKILL-UNKNOWN"
    edge = graph { |d| skill(d, "math.percentages")["prerequisites"] << "italian.reading" }
    submit_graph(edge)
    assert_includes json["codes"], "E-GRAPH-EDGE-UNAPPROVED"
    italian = SkillGraphRevision.create!(subject: @italian, seq: 1, body_json: JSON.generate(F::GRAPH.merge("subject" => "italian",
              "skills" => [ F.skill_row("italian.reading", "Lettura") ])))
    submit_graph(edge)
    assert_includes json["codes"], "E-GRAPH-EDGE-UNAPPROVED" # a draft is not an approved graph
    approve_graph!(@italian, italian)
    submit_graph(edge)
    assert_response :created, json.inspect
  end

  test "D-093: two refused cross-subject targets in one field are two findings" do
    submit_graph(graph { |d| skill(d, "math.percentages")["prerequisites"] += [ "italian.reading", "italian.writing" ] })
    names = json["findings"].select { |f| f["code"] == "E-GRAPH-EDGE-UNAPPROVED" }.map { |f| f["detail"]["skill"] }
    assert_equal %w[italian.reading italian.writing], names.sort
  end

  test "D-091: a deferred edge to a subject without an approved graph is accepted; one to our own subject is E-SCHEMA" do
    deferred = graph { |d| skill(d, "math.percentages")["deferred_prerequisites"] = [ { "skill" => "italian.reading", "reason_it" => "Serve la lettura." } ] }
    submit_graph(deferred)
    assert_response :created, json.inspect
    own = graph { |d| skill(d, "math.percentages")["deferred_prerequisites"] = [ { "skill" => "math.number", "reason_it" => "Serve." } ] }
    submit_graph(own)
    assert_includes json["codes"], "E-SCHEMA"
    nested = graph { |d| skill(d, "math.percentages")["errors"] = [ { "code" => "x_one", "description_it" => "Sbaglia.", "implicates" => [], "deferred_implicates" => [ { "skill" => "italian.reading", "reason_it" => "Lettura." } ] } ] }
    submit_graph(nested)
    assert_response :created, json.inspect
  end

  test "open: the latest revision, the sources and the range; unknown subject is 404" do
    api("/api/v1/subjects/math/skill-graph")
    assert_nil json["revision"]
    record_example "skill-graph open", "empty"
    submit_graph(graph)
    api("/api/v1/subjects/math/skill-graph")
    assert_equal 1, json["revision"]["seq"]
    assert_equal "math.integer-operations", json["revision"]["graph"]["skills"].first["key"]
    assert_equal "skill-graph", json["brief"]["name"]
    assert_equal %w[prima-test seconda-test], json["sources"].map { |s| s["key"] }
    api("/api/v1/subjects/nothing/skill-graph")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
  end

  test "coverage: item_errors_not_in_graph lists codes of passed items that the graph lacks (D-137)" do
    submit_graph(graph)
    with_errors = graph["skills"].find { |s| s["errors"].any? }
    skill_key = with_errors["key"]
    declared = with_errors["errors"].first["code"]
    item = Item.create!(subject: @subject, key: "probe", kind: "diagnosis_item")
    body = { schema: "banco.item/1", kind: "diagnosis_item", subject: "math", skill: skill_key,
             error_catalogue: [ { code: declared }, { code: "invented_code" } ] }
    rev = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: rev, seq: 1, status: "passed", codes_json: "[]")
    programme { api("/api/v1/subjects/math/skill-graph/coverage") }
    assert_response :ok
    assert_equal [ { "item" => "probe", "item_revision_id" => rev.id, "skill" => skill_key, "code" => "invented_code" } ], json["item_errors_not_in_graph"]
  end

  test "coverage: a stored multi-skill testlet is checked on its first sub item's skill and listed in testlets_multi_skill (D-151)" do
    submit_graph(graph)
    with_errors = graph["skills"].find { |s| s["errors"].any? }
    first_skill = with_errors["key"]
    other_skill = (graph["skills"].map { |s| s["key"] } - [ first_skill ]).first
    declared = with_errors["errors"].first["code"]
    item = Item.create!(subject: @subject, key: "passage", kind: "testlet")
    body = { schema: "banco.item/1", kind: "testlet", subject: "math",
             sub_items: [ { skill: first_skill, error_catalogue: [ { code: declared } ] },
                          { skill: other_skill, error_catalogue: [ { code: declared }, { code: "only_here" } ] } ] }
    rev = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: rev, seq: 1, status: "passed", codes_json: "[]")
    programme { api("/api/v1/subjects/math/skill-graph/coverage") }
    assert_response :ok
    assert_equal [ { "item" => "passage", "item_revision_id" => rev.id, "skill" => first_skill, "code" => "only_here" } ], json["item_errors_not_in_graph"]
    assert_equal [ { "item" => "passage", "item_revision_id" => rev.id, "skills" => [ first_skill, other_skill ], "charged_to" => first_skill } ], json["testlets_multi_skill"]
  end

  test "coverage: lines of the range that no skill cites and no exclusion explains" do
    submit_graph(graph)
    programme { api("/api/v1/subjects/math/skill-graph/coverage") }
    assert_response :ok
    record_example "skill-graph coverage", "uncovered"
    assert_equal [ 3 ], json["uncovered"].map { |l| l["line"] }
    assert_equal 2, json["lines"] # the transcriber line is not content
    assert_equal 1, json["cited"]
    assert_equal 6, json["skills"]["total"]
    assert_equal 0, json["skills"]["with_items"]

    covered = graph { |d| d["excluded"] << { "line" => 3, "reason_it" => "Argomento di un'altra materia." } }
    submit_graph(covered)
    programme { api("/api/v1/subjects/math/skill-graph/coverage") }
    assert_equal [], json["uncovered"]

    api("/api/v1/subjects/italian/skill-graph/coverage")
    assert_response :not_found
  end

  # A starred header at line 4 with its body at 5, an unstarred header at 6.
  def add_marked_lines
    SyllabusLine.create!(syllabus_source: @source, number: 4, text: "★ Un blocco in più:", origin: "pdf", marker: "★")
    SyllabusLine.create!(syllabus_source: @source, number: 5, text: "Il corpo del blocco, con più parole. Altro testo qui.", origin: "pdf")
    SyllabusLine.create!(syllabus_source: @source, number: 6, text: "Un altro titolo:", origin: "pdf")
  end

  test "syllabus lines: a line under a starred header shows the block marker and its header" do
    add_marked_lines
    api("/api/v1/syllabus/prima-test/lines?from=5&to=6")
    assert_equal "★", json["rows"][0]["block_marker"]
    assert_equal 4, json["rows"][0]["block_marker_line"]
    assert_nil json["rows"][1]["block_marker"]
    api("/api/v1/syllabus/prima-test/lines?from=4&to=4")
    assert_equal "★", json["rows"][0]["marker"]
    assert_nil json["rows"][0]["block_marker"]
  end

  def add_sections
    { 10 => "## Italiano", 11 => "- il testo narrativo", 12 => "## Storia", 13 => "- la Rivoluzione francese", 14 => "### Dettaglio" }.each do |n, text|
      SyllabusLine.create!(syllabus_source: @source, number: n, text: text, origin: "pdf")
    end
  end

  test "syllabus lines: a line carries the section (## heading) it sits under" do
    add_sections
    api("/api/v1/syllabus/prima-test/lines?from=10&to=14")
    assert_equal [ "Italiano", "Italiano", "Storia", "Storia", "Storia" ], json["rows"].map { |r| r["section"] }
  end

  test "W-REF-OTHER-SUBJECT: a ref under another section than most of the citations is warned, the majority is quiet" do
    add_sections
    set = lambda do |doc, key, line, fragment|
      skill(doc, key)["refs"][0].merge!("line" => line, "fragment" => fragment)
    end
    doc = graph do |d|
      set.(d, "math.percentages", 11, "il testo")
      set.(d, "math.decimal-operations", 11, "narrativo")
      set.(d, "math.linear-equation-integer", 13, "Rivoluzione")
    end
    submit_graph(doc, dry: true)
    warnings = json["warnings"].select { |w| w["code"] == "W-REF-OTHER-SUBJECT" }
    assert_equal 1, warnings.size, json.inspect
    assert_equal "Storia", warnings.first["detail"]["section"]
    assert_equal 13, warnings.first["detail"]["line"]
    assert_equal "/skills/#{doc['skills'].index { |s| s['key'] == 'math.linear-equation-integer' }}/refs/0", warnings.first["field"]
    skill(doc, "math.linear-equation-integer")["scope_reason_it"] = "La riga 130 e di un'altra materia."
    submit_graph(doc, dry: true)
    assert_equal 1, json["warnings"].count { |w| w["code"] == "W-REF-OTHER-SUBJECT" }, "a reason naming another line does not clear it"
    skill(doc, "math.linear-equation-integer")["scope_reason_it"] = "La riga 13 e di Storia, altra materia."
    submit_graph(doc, dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-REF-OTHER-SUBJECT" }, "a reason naming the line clears it"
    skill(doc, "math.linear-equation-integer")["scope_reason_it"] = "Le righe 12-14 sono di Storia."
    submit_graph(doc, dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-REF-OTHER-SUBJECT" }, "a range N-M names every line from N to M"
    skill(doc, "math.linear-equation-integer")["scope_reason_it"] = "Le righe 14\u201316 sono di Storia."
    submit_graph(doc, dry: true)
    assert_equal 1, json["warnings"].count { |w| w["code"] == "W-REF-OTHER-SUBJECT" }, "a range that stops short of the line does not clear it"
    skill(doc, "math.linear-equation-integer").delete("scope_reason_it")
    set.(doc, "math.linear-equation-integer", 11, "testo")
    submit_graph(doc, dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-REF-OTHER-SUBJECT" }
  end

  test "W-SCOPE-MARKER: studied cites a starred block; the matching scope is quiet" do
    add_marked_lines
    set = ->(scope) { graph { |d| skill(d, "math.percentages").tap { |s| s["scope"] = scope; s["refs"][0].merge!("line" => 5, "fragment" => "corpo del blocco") } } }
    submit_graph(set.("studied"), dry: true)
    assert_response :ok
    warning = json["warnings"].find { |w| w["code"] == "W-SCOPE-MARKER" }
    assert warning, json.inspect
    assert_match(%r{\A/skills/\d+/scope\z}, warning["field"])
    assert_equal [ "integration_studied" ], warning["detail"]["expected"]
    submit_graph(set.("integration_studied"), dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-SCOPE-MARKER" }
  end

  test "W-SCOPE-MARKER: a skill spanning an unmarked line and a starred block is quiet for either scope (D-142)" do
    add_marked_lines
    set = lambda do |scope|
      graph do |d|
        skill(d, "math.percentages").tap do |s|
          s["scope"] = scope
          s["refs"][0].merge!("line" => 5, "fragment" => "corpo del blocco")
          s["refs"] << s["refs"][0].merge("line" => 6, "fragment" => "Un altro titolo")
        end
      end
    end
    %w[studied integration_studied].each do |scope|
      submit_graph(set.(scope), dry: true)
      assert_empty json["warnings"].select { |w| w["code"] == "W-SCOPE-MARKER" }, scope
    end
  end

  test "W-SCOPE-MARKER: a star inside the cited fragment decides, though the line has no marker" do
    SyllabusLine.create!(syllabus_source: @source, number: 7, text: "Il clima ☆ Il cambiamento climatico e ★ le carte tematiche", origin: "pdf")
    set = lambda do |scope, fragment|
      graph { |d| skill(d, "math.percentages").tap { |s| s["scope"] = scope; s["refs"][0].merge!("line" => 7, "fragment" => fragment) } }
    end
    submit_graph(set.("studied", "☆ Il cambiamento climatico"), dry: true)
    warning = json["warnings"].find { |w| w["code"] == "W-SCOPE-MARKER" }
    assert warning, json.inspect
    assert_equal [ "in_progress" ], warning["detail"]["expected"]
    submit_graph(set.("in_progress", "☆ Il cambiamento climatico"), dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-SCOPE-MARKER" }
    submit_graph(set.("integration_studied", "★ le carte tematiche"), dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-SCOPE-MARKER" }
    submit_graph(set.("studied", "Il clima"), dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-SCOPE-MARKER" }
  end

  test "W-SCOPE-MARKER: a star just before the cited fragment (not inside it) decides" do
    SyllabusLine.create!(syllabus_source: @source, number: 8, text: "Il geosistema. I climi. ☆ Un mondo inquinato. Le risorse naturali. ☆ Risorse scarse", origin: "pdf")
    set = lambda do |scope, fragment|
      graph { |d| skill(d, "math.percentages").tap { |s| s["scope"] = scope; s["refs"][0].merge!("line" => 8, "fragment" => fragment) } }
    end
    submit_graph(set.("in_progress", "Un mondo inquinato"), dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-SCOPE-MARKER" }
    submit_graph(set.("studied", "Un mondo inquinato"), dry: true)
    assert json["warnings"].find { |w| w["code"] == "W-SCOPE-MARKER" }, json.inspect
    submit_graph(set.("studied", "Le risorse naturali"), dry: true)
    assert_empty json["warnings"].select { |w| w["code"] == "W-SCOPE-MARKER" }
  end

  test "excluded fragment: must be a substring of the line" do
    submit_graph(graph { |d| d["excluded"] << { "line" => 3, "fragment" => "non è lì", "reason_it" => "Prova." } })
    assert(json["findings"].any? { |f| f["code"] == "E-SOURCE" && f["detail"]["rule"] == "fragment" && f["field"] == "/excluded/#{graph['excluded'].size}/fragment" }, json.inspect)
  end

  test "coverage: a partly used line is listed with its cited and excluded fragments" do
    SyllabusLine.create!(syllabus_source: @source, number: 4, text: "numeri relativi e anche organizzazioni collettive", origin: "pdf")
    doc = graph { |d| d["excluded"] << { "line" => 3, "reason_it" => "Altra materia." }; skill(d, "math.percentages")["refs"] << { "source" => "prima-test", "line" => 4, "fragment" => "numeri relativi", "role" => "taught_in" } }
    submit_graph(doc)
    programme { api("/api/v1/subjects/math/skill-graph/coverage") } # range 1..3 only
    assert_equal [ 1 ], json["partial"].map { |p| p["line"] } # cited by a short fragment
    Validation::Rules.with(coverage: { prima_source: "prima-test", ranges: { math: [ 1, 4 ] } }) { api("/api/v1/subjects/math/skill-graph/coverage") }
    part = json["partial"].find { |p| p["line"] == 4 }
    assert_equal [ "numeri relativi" ], part["cited"]
    assert_equal [ "e anche organizzazioni collettive" ], part["unaccounted"]
    assert_equal [], json["uncovered"]

    doc["excluded"] << { "line" => 4, "fragment" => "e anche organizzazioni collettive", "reason_it" => "Organizzazioni collettive: nessuna abilità." }
    submit_graph(doc)
    Validation::Rules.with(coverage: { prima_source: "prima-test", ranges: { math: [ 1, 4 ] } }) { api("/api/v1/subjects/math/skill-graph/coverage") }
    assert_equal [ 1 ], json["partial"].map { |p| p["line"] }
  end

  # ---- the blueprint -------------------------------------------------------------------------

  def make_graph_row
    @graph_rev = SkillGraphRevision.create!(subject: @subject, seq: 1, body_json: JSON.generate(F::GRAPH))
  end

  # Two items of four instances for each skill: 8 distinct instances, all low-guess.
  def pair(skill, tag)
    [ make_revision("#{tag}-a", skill), make_revision("#{tag}-b", skill) ]
  end

  def blueprint(entries: %w[math.linear-equation-integer math.percentages math.factoring math.decimal-operations])
    @revs ||= {}
    rows = entries.map do |skill|
      tag = skill.split(".").last
      @revs[skill] ||= pair(skill, tag)
      { "skill" => skill, "items" => @revs[skill].map { |r| r.id.to_s } }
    end
    @revs["math.integer-operations"] ||= pair("math.integer-operations", "intops")
    {
      "schema" => "banco.blueprint/1", "schema_version" => 1, "subject" => "math", "graph_revision_id" => @graph_rev.id.to_s,
      "entries" => rows,
      "descent" => [
        { "skill" => "math.integer-operations", "items" => @revs["math.integer-operations"].map { |r| r.id.to_s } },
        { "skill" => "math.fractions-operations", "not_assessed_reason_it" => "Argomento dei prerequisiti, non misurabile con item propri." }
      ],
      "budget" => { "sitting_minutes" => 30, "sittings" => 2 }, "depends_on_subjects" => [], "calculator" => "no",
      "intro_note_it" => "Il test dura circa mezz'ora.", "not_measured_it" => "Non misura la geometria."
    }
  end

  def submit_blueprint(doc, dry: false) = api("/api/v1/subjects/math/blueprint", method: :post, body: { blueprint: doc }, dry: dry)

  test "simulate of a bare blueprint uses the pinned graph and items (D-099)" do
    make_graph_row
    api("/api/v1/diagnosis/simulate", method: :post, body: { bundle: blueprint, script: "all-wrong" })
    assert_response :ok, json.inspect
    assert_equal [], json["warnings"]
    served = json["trace"].select { |e| e["kind"] == "item_served" }
    assert served.any? { |e| e["skill"] == "math.integer-operations" }, "the descent pool is reached"
    assert served.none? { |e| e["instance"].to_s.include?("sim_") }

    doc = blueprint
    doc["graph_revision_id"] = "999999"
    api("/api/v1/diagnosis/simulate", method: :post, body: { bundle: doc, script: "all-wrong" })
    assert_response :ok
    assert_equal "E-SIMULATE-INPUT", json["warnings"].first["code"]

    doc = blueprint
    doc["entries"][0]["items"] << "424242"
    api("/api/v1/diagnosis/simulate", method: :post, body: { bundle: doc, script: "all-wrong" })
    assert_match "424242", json["warnings"].first["message"]
  end

  test "a good blueprint is stored; replay; --dry-run stores nothing" do
    make_graph_row
    submit_blueprint(blueprint, dry: true)
    assert_response :ok, json.inspect
    assert_equal 0, BlueprintRevision.count
    submit_blueprint(blueprint)
    assert_response :created, json.inspect
    record_example "blueprint submit", "created"
    revision = BlueprintRevision.last
    assert_equal @graph_rev, revision.skill_graph_revision
    assert_equal "blueprint", Brief.find("blueprint").name
    assert_equal Brief.find("blueprint").sha256, revision.brief_sha256
    submit_blueprint(blueprint)
    assert_equal true, json["replayed"]
    assert_equal 1, BlueprintRevision.count
  end

  test "D-159: blueprint open carries the stored blueprint alone as document, ready to edit and resubmit" do
    make_graph_row
    submit_blueprint(blueprint)
    api("/api/v1/subjects/math/blueprint")
    assert_response :ok
    assert_equal json["revision"]["blueprint"], json["document"]
    doc = json["document"]
    submit_blueprint(doc, dry: true)
    assert_response :ok, json.inspect
  end

  test "D-172: blueprint open shows an item that waits for its verifier as awaiting_verifier" do
    make_graph_row
    submit_blueprint(blueprint)
    rev = @revs["math.percentages"].first
    ItemValidation.create!(item_revision: rev, seq: 9, status: "failed", codes_json: "[\"E-VERIFY-MISSING\"]")
    api("/api/v1/subjects/math/blueprint")
    row = json["items"].find { |i| i["revision_id"] == rev.id }
    assert_equal "awaiting_verifier", row["status"]
  end

  test "E-BLUEPRINT-ENTRIES: fewer than 4 or more than 10 starting skills" do
    make_graph_row
    submit_blueprint(blueprint(entries: %w[math.linear-equation-integer math.percentages math.factoring]))
    assert_response :unprocessable_entity
    assert_equal "E-BLUEPRINT-ENTRIES", json["code"]
    doc = blueprint
    doc["entries"] = doc["entries"] * 3
    submit_blueprint(doc)
    assert_equal "E-BLUEPRINT-ENTRIES", json["code"]
    assert_equal 0, BlueprintRevision.count
  end

  test "E-POOL-REDO: a pinned descent skill with no hard-to-guess instance (B-02)" do
    make_graph_row
    doc = blueprint
    guessable = [ make_revision("guess-a", "math.integer-operations", component: "choice"), make_revision("guess-b", "math.integer-operations", component: "choice") ]
    doc["descent"][0] = { "skill" => "math.integer-operations", "items" => guessable.map { |r| r.id.to_s } }
    submit_blueprint(doc)
    assert_response :unprocessable_entity
    assert_equal "E-POOL-REDO", json["code"]
    assert_equal "descent_low_guess", json["findings"].first["rule"] if json["findings"].first.key?("rule")
    assert_equal 0, BlueprintRevision.count
  end

  test "E-BLUEPRINT-UNPINNED-DESCENT: a reachable skill with no items and no reason (D-038)" do
    make_graph_row
    doc = blueprint
    doc["descent"].pop
    submit_blueprint(doc)
    assert_response :unprocessable_entity
    assert_equal "E-BLUEPRINT-UNPINNED-DESCENT", json["code"]
    record_example "blueprint submit", "unpinned-descent"
    assert_equal "math.fractions-operations", json["findings"].first["detail"]["skill"]
    doc["descent"] = []
    submit_blueprint(doc)
    assert_equal 2, json["findings"].count { |f| f["code"] == "E-BLUEPRINT-UNPINNED-DESCENT" }
    assert_equal 0, BlueprintRevision.count
  end

  test "E-ITEM-NOT-PASSED: a failed validation, no validation, an unknown revision" do
    make_graph_row
    doc = blueprint
    failed = make_revision("failed-1", "math.percentages", status: "failed")
    doc["entries"][1]["items"] = [ failed.id.to_s, doc["entries"][1]["items"].last ]
    submit_blueprint(doc)
    assert_includes json["codes"], "E-ITEM-NOT-PASSED"
    waiting = make_revision("waiting-1", "math.percentages", status: nil)
    doc["entries"][1]["items"] = [ waiting.id.to_s, doc["entries"][1]["items"].last ]
    submit_blueprint(doc)
    assert_includes json["codes"], "E-ITEM-NOT-PASSED"
    doc["entries"][1]["items"] = [ "999999", doc["entries"][1]["items"].last ]
    submit_blueprint(doc)
    assert(json["findings"].any? { |f| f["code"] == "E-ITEM-NOT-PASSED" && f["detail"]["rule"] == "unknown" })
  end

  test "E-POOL-REDO: too few instances, or redo_reserve false" do
    make_graph_row
    doc = blueprint
    doc["entries"][0]["items"] = [ make_revision("single", "math.linear-equation-integer", instances: 4).id.to_s ]
    submit_blueprint(doc)
    assert_equal "E-POOL-REDO", json["code"]
    assert_match(/item/, json["message"])
    doc["entries"][0]["redo_reserve"] = false
    submit_blueprint(doc)
    assert_response :created, json.inspect
  end

  test "E-POOL-REDO counts hard-to-guess instances unless a choice-only reason is given" do
    make_graph_row
    doc = blueprint
    skill = "math.linear-equation-integer"
    choice_revs = [ make_revision("choice-a", skill, component: "choice"), make_revision("choice-b", skill, component: "choice") ]
    doc["entries"][0]["items"] = choice_revs.map { |r| r.id.to_s }
    submit_blueprint(doc)
    assert_equal "E-POOL-REDO", json["code"]
    doc["entries"][0]["choice_only_reason_it"] = "Il concetto e nuovo."
    submit_blueprint(doc)
    assert_response :created, json.inspect
  end

  test "E-SKILL-UNKNOWN: a starting skill that is not in the graph, an item that measures another skill" do
    make_graph_row
    doc = blueprint
    doc["entries"][0]["skill"] = "math.imaginary"
    submit_blueprint(doc)
    assert_includes json["codes"], "E-SKILL-UNKNOWN"
    doc = blueprint
    doc["entries"][0]["items"] = @revs["math.percentages"].map { |r| r.id.to_s }
    submit_blueprint(doc)
    assert(json["findings"].any? { |f| f["code"] == "E-SKILL-UNKNOWN" && f["detail"]["rule"] == "item_skill" })
  end

  test "an unknown graph revision is 404; a document that is not a blueprint is E-SCHEMA" do
    make_graph_row
    doc = blueprint.merge("graph_revision_id" => "999")
    submit_blueprint(doc)
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    submit_blueprint({ "schema" => "banco.blueprint/1" })
    assert_equal "E-SCHEMA", json["code"]
  end

  test "open: the descent targets of the latest blueprint and the items that can be pinned" do
    make_graph_row
    api("/api/v1/subjects/math/blueprint")
    assert_nil json["revision"]
    assert_equal @graph_rev.id, json["graph_revision_id"]
    submit_blueprint(blueprint)
    api("/api/v1/subjects/math/blueprint")
    record_example "blueprint open", "with-targets"
    assert_equal %w[math.fractions-operations math.integer-operations], json["descent_targets"]
    assert_equal "passed", json["items"].first["status"]
    assert(json["items"].any? { |i| i["skills"] == [ "math.percentages" ] })
  end

  # ---- status ------------------------------------------------------------------------------------

  test "status: drafting, validating, in_review, approved; no command goes past awaiting_teacher" do
    api("/api/v1/status")
    row = json["subjects"].find { |s| s["key"] == "math" }
    assert_equal "drafting", row["stage"]
    record_example "status", "drafting"
    assert_equal SubjectStage::STAGES, json["stages"]

    make_graph_row
    submit_blueprint(blueprint)
    api("/api/v1/status")
    row = json["subjects"].find { |s| s["key"] == "math" }
    assert_equal "in_review", row["stage"] # every pinned item passed; the review is M6
    assert_equal false, row["graph_approved"]
    assert_equal 5 * 2, row["items"]["passed"]

    make_revision("late", "math.percentages", status: nil)
    api("/api/v1/status")
    assert_equal "validating", json["subjects"].find { |s| s["key"] == "math" }["stage"]

    approve_graph!(@subject, @graph_rev)
    approve_blueprint!(@subject, BlueprintRevision.last)
    api("/api/v1/status")
    row = json["subjects"].find { |s| s["key"] == "math" }
    assert_equal "approved", row["stage"]
    assert_equal true, row["graph_approved"]
    assert_equal true, row["blueprint_approved"]
    assert_equal false, row["pending_revision"]

    changed = blueprint.merge("intro_note_it" => "Una nuova introduzione.")
    submit_blueprint(changed)
    api("/api/v1/status")
    assert_equal true, json["subjects"].find { |s| s["key"] == "math" }["pending_revision"]
    assert_equal "approved", json["subjects"].find { |s| s["key"] == "math" }["stage"]
  end

  test "a failed pinned item keeps the stage at drafting" do
    make_graph_row
    submit_blueprint(blueprint)
    api("/api/v1/status")
    assert_equal "in_review", json["subjects"].find { |s| s["key"] == "math" }["stage"]
    ItemValidation.create!(item_revision: @revs["math.percentages"].first, seq: 2, status: "failed", codes_json: "[\"E-READ\"]")
    api("/api/v1/status")
    assert_equal "drafting", json["subjects"].find { |s| s["key"] == "math" }["stage"]
  end

  test "status counts an item that waits for its verifier apart from a failed one (D-141)" do
    make_graph_row
    submit_blueprint(blueprint)
    api("/api/v1/status")
    before = json["subjects"].find { |sub| sub["key"] == "math" }["items"]
    rev = @revs["math.percentages"].first
    ItemValidation.create!(item_revision: rev, seq: 2, status: "failed", codes_json: "[\"E-VERIFY-STALE\"]")
    api("/api/v1/status")
    items = json["subjects"].find { |sub| sub["key"] == "math" }["items"]
    assert_equal 1, items["awaiting_verifier"]
    assert_equal before["failed"], items["failed"]
    assert_equal before["passed"] - 1, items["passed"]
    ItemValidation.create!(item_revision: rev, seq: 3, status: "failed", codes_json: "[\"E-VERIFY-STALE\",\"E-READ\"]")
    api("/api/v1/status")
    items = json["subjects"].find { |sub| sub["key"] == "math" }["items"]
    assert_equal [ 0, before["failed"] + 1 ], [ items["awaiting_verifier"], items["failed"] ]
  end

  test "status counts passed items validated under older rules (D-147)" do
    make_graph_row
    submit_blueprint(blueprint)
    rev = @revs["math.percentages"].first
    ItemValidation.create!(item_revision: rev, seq: 2, status: "passed", codes_json: "[]", rules_version: "0")
    api("/api/v1/status")
    old = json["subjects"].find { |sub| sub["key"] == "math" }["items"]["older_rules"]
    assert_operator old, :>=, 1
    ItemValidation.create!(item_revision: rev, seq: 3, status: "passed", codes_json: "[]", rules_version: Validation::Rules.version.to_s)
    api("/api/v1/status")
    assert_equal old - 1, json["subjects"].find { |sub| sub["key"] == "math" }["items"]["older_rules"]
  end
end
