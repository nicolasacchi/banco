require "test_helper"
require_relative "../../support/lesson2_fixtures"

# D-402: the labels of a flow's edges. `edges` is a list of [from, to, label] with the target label in the third place; the Italian labels are `edges_it`, a list
# of the same length (null for an edge without a label). Also: every state of a figure has its pairs in the figure's `tr` (a served lesson, the fixtures
# test/fixtures/lang/lesson_{es,en}_figures.md, which test/validation/lesson_render_translation_test.rb draws in Chrome).
class BilingualEdgesTest < ActiveSupport::TestCase
  B = Lessons::Bilingual
  DIR = Rails.root.join("test/fixtures/lang")
  SUBJECT = { "en" => "english", "es" => "spanish" }.freeze

  FLOW = {
    "type" => "flow", "alt_es" => "Cómo decides la tilde.", "alt_it" => "Come decidi la tilde.",
    "nodes" => [ { "id" => "s", "kind" => "step", "text_es" => "Busca", "text_it" => "Cerca" }, { "id" => "q", "kind" => "decision", "text_es" => "¿Dónde?", "text_it" => "Dove?" },
                 { "id" => "a", "kind" => "end", "text_es" => "Tilde", "text_it" => "Tilde sì" }, { "id" => "b", "kind" => "end", "text_es" => "Sin tilde", "text_it" => "Niente tilde" } ],
    "edges" => [ %w[s q], %w[q a última], %w[q b penúltima] ],
    "edges_it" => [ nil, "ultima", "penultima" ]
  }.freeze

  def deep(value) = JSON.parse(JSON.generate(value))

  def figures(lang)
    md = DIR.join("lesson_#{lang}_figures.md").read
    body = Lessons::Parser2.call(md, Validation::Findings.new).body
    Lessons::StudentBody.project(body, revision_id: 1, seed: "preview")
  end

  # Every figure of a served lesson: the hero and the diagram or schema of each block (and of a check or an example step).
  def served_figures(node, out = [])
    case node
    when Hash
      out << node if node["type"].is_a?(String) && node.key?("alt_it")
      node.each_value { |v| served_figures(v, out) }
    when Array then node.each { |v| served_figures(v, out) }
    end
    out
  end

  # The `label_it`, `parts_it` and `meaning_it` of every hash that has a `form_*` key (a word_parts word) and is not a folded pair (the fold has put the target text
  # there and made a tr entry): the Italian gloss, drawn as Italian.
  def legacy_glosses(value, tr = value.is_a?(Hash) ? value["tr"].to_h : {}, out = [])
    case value
    when Hash
      if value.keys.any? { |k| k.match?(/\Aform_(en|es|la|it)\z/) }
        %w[label_it parts_it meaning_it].each { |k| out.concat(Array(value[k]).grep(String).reject { |t| tr.key?(t) }) }
      end
      value.each_value { |v| legacy_glosses(v, tr, out) }
    when Array then value.each { |v| legacy_glosses(v, tr, out) }
    end
    out
  end

  def italian_strings(value, key = nil, top = true, out = [])
    case value
    when String then out << value if key.to_s.end_with?("_it") && !%w[pieces_it form_it].include?(key) && !(top && %w[alt_it caption_it].include?(key))
    when Array then (key == "edges" ? value.each { |e| out << e[2] if e.is_a?(Array) && e[2] } : value.each { |v| italian_strings(v, key, false, out) })
    when Hash then value.each { |k, v| italian_strings(v, k, top && key.nil?, out) }
    end
    out
  end

  # ---- the walker, the fold, the Italian layer ------------------------------------------------------------------------------

  test "pairs yields each edge label with its Italian, by index; an edge with no label is no pair" do
    found = B.pairs(deep(FLOW), "es").select { |_p, base, _t, _i| base == "edges" }.to_a
    assert_equal [ [ "/edges/1/2", "edges", "última", "ultima" ], [ "/edges/2/2", "edges", "penúltima", "penultima" ] ], found
  end

  test "a label without its Italian, an Italian without its label, and a list too long are orphans" do
    no_italian = deep(FLOW).except("edges_it")
    assert_equal [ [ "/edges/1/2", "última", nil ], [ "/edges/2/2", "penúltima", nil ] ],
                 B.pairs(no_italian, "es").select { |_p, base, _t, _i| base == "edges" }.map { |p, _b, t, i| [ p, t, i ] }
    unlabelled = deep(FLOW).merge("edges_it" => [ "da s a q", "ultima", "penultima" ])
    assert_equal [ "/edges/0/2", nil, "da s a q" ], B.pairs(unlabelled, "es").find { |p, *| p == "/edges/0/2" }.then { |p, _b, t, i| [ p, t, i ] }
    longer = deep(FLOW).merge("edges_it" => [ nil, "ultima", "penultima", "una in più" ])
    assert_equal [ "/edges/3/2", nil, "una in più" ], B.pairs(longer, "es").find { |p, *| p == "/edges/3/2" }.then { |p, _b, t, i| [ p, t, i ] }
  end

  test "a figure that is not a flow has no edge labels: network and concept_map edges are objects, untouched" do
    network = { "type" => "network", "edges" => [ { "from" => "a", "to" => "b" } ], "edges_it" => [ "x" ] }
    assert_equal [], B.pairs(network, "es").select { |_p, _b, t, _i| t.is_a?(String) && t == "x" }.to_a
    assert_equal network, B.fold(network, nil).except("lang"), "folded as served: no edge pair"
  end

  test "fold keeps the target labels in the edges, drops edges_it and puts the Italian in the figure's tr" do
    folded = B.fold(deep(FLOW), nil)
    assert_equal FLOW["edges"], folded["edges"]
    assert_not folded.key?("edges_it")
    assert_equal "ultima", folded["tr"]["última"]
    assert_equal "penultima", folded["tr"]["penúltima"]
    assert_equal "Cerca", folded["tr"]["Busca"]
  end

  test "fold of a flow without edges_it, and of a legacy flow, leaves the edges as served" do
    legacy = { "type" => "flow", "alt_it" => "Un flusso.", "nodes" => FLOW["nodes"].map { |n| { "id" => n["id"], "kind" => n["kind"], "text_it" => n["text_it"] } }, "edges" => FLOW["edges"] }
    assert_equal legacy, B.fold(legacy, nil).except("lang")
  end

  test "the Italian layer reads the Italian labels in the edges, a missing one keeps the target label" do
    layer = B.italian_layer(deep(FLOW))
    assert_equal [ %w[s q], %w[q a ultima], %w[q b penultima] ], layer["edges"]
    assert_not layer.key?("edges_it")
    partial = B.italian_layer(deep(FLOW).merge("edges_it" => [ nil, "ultima", nil ]))
    assert_equal %w[q b penúltima], partial["edges"][2]
  end

  test "the target layer drops edges_it and keeps the labels" do
    layer = Validation::Bilingual.target_layer(deep(FLOW), "es")
    assert_equal FLOW["edges"], layer["edges"]
    assert_not layer.key?("edges_it")
  end

  # ---- the schema, the parser and the checks --------------------------------------------------------------------------------

  test "the derived diagram schema takes edges_it of a flow (labels or null, as many as the edges), the plain schema and a legacy flow never" do
    derived = Banco::Schemas.read("diagram", bilingual: true).dig("$defs", "flow", "properties")
    plain = Banco::Schemas.read("diagram").dig("$defs", "flow", "properties")
    assert_equal({ "type" => "array", "minItems" => 2, "maxItems" => 14, "items" => { "oneOf" => [ { "type" => "null" }, { "type" => "string", "minLength" => 1, "maxLength" => 40 } ] } },
                 derived["edges_it"].except("description"))
    assert_not plain.key?("edges_it")
    assert_not derived["edges"].key?("edges_it")
  end

  %w[es en].each do |lang|
    test "#{lang}: the pilot fixture parses clean, with its edge labels paired" do
      md = DIR.join("lesson_#{lang}_figures.md").read
      findings = Validation::Findings.new
      body = Lessons::Parser2.call(md, findings).body
      assert_not_nil body, findings.map(&:to_h).inspect
      flow = body["cards"].flat_map { |c| c["blocks"] }.find { |b| b.dig("schema", "type") == "flow" }["schema"]
      assert_equal 3, flow["edges"].size
      assert_equal [ nil, flow["edges"][1][2] && flow["edges_it"][1], flow["edges_it"][2] ], flow["edges_it"]
      checked = Validation::LessonChecks.call(md, subject: SUBJECT[lang], context: Lesson2Fixtures.context(SUBJECT[lang])).findings
      assert_empty checked.select { |f| f.code.start_with?("E-LANG-PAIR", "E-SCHEMA") || f.field.to_s.include?("edges") }.map { |f| [ f.code, f.field, f.message ] }
    end

    test "#{lang}: a flow edge label with no Italian is E-LANG-PAIR-MISSING, an edges_it of the wrong length is refused" do
      md = DIR.join("lesson_#{lang}_figures.md").read
      missing = md.sub(/^edges_it:\n(?:  - .*\n)+/, "")
      assert_not_equal md, missing
      found = Validation::LessonChecks.call(missing, subject: SUBJECT[lang], context: Lesson2Fixtures.context(SUBJECT[lang])).findings
      assert_equal 2, found.count { |f| f.code == "E-LANG-PAIR-MISSING" && f.field.include?("/edges/") }, found.map { |f| [ f.code, f.field ] }.inspect
      assert(found.any? { |f| f.message.include?("edges_it") })
      short = md.sub(/^edges_it:\n  - ~\n/, "edges_it:\n")
      too_short = Validation::LessonChecks.call(short, subject: SUBJECT[lang], context: Lesson2Fixtures.context(SUBJECT[lang])).findings
      assert(too_short.any? { |f| f.code == "E-LANG-PAIR-MISSING" || f.code == "E-SCHEMA" || f.code == "E-LESSON-BLOCK" }, "a list shorter than edges is a finding")
    end

    test "#{lang}: every Italian-keyed text of every state of every served figure has its Italian in the figure's tr" do
      served = figures(lang)
      figs = served_figures(served)
      assert_operator figs.size, :>=, 7
      with_states = figs.select { |f| f["states"].is_a?(Array) && f["states"].size > 1 }
      assert_operator with_states.size, :>=, 3, "the sentence (hero and block) and word_parts figures have states"
      figs.each do |figure|
        next unless figure["tr"]

        missing = italian_strings(figure.except("tr", "diagram")).reject { |t| figure["tr"].key?(t) }
        # a table's cells are not folded: they hold the target text in `header` / `rows` and their own Italian in `header_it` / `rows_it`
        missing -= Array(figure["header_it"]) + Array(figure["rows_it"]).flatten
        # a word_parts word's `label_it` beside its `form_*` and no `label_<lang>` is the legacy Italian gloss, written once: no pair, no entry in tr
        missing -= legacy_glosses(figure)
        assert_empty missing, "#{figure['type']}: strings with no Italian in tr"
      end
    end

    test "#{lang}: the later states of a figure keep their op and their labels in tr (not only the first state's)" do
      served = figures(lang)
      sentence = served["hero"]
      last = sentence["states"].last
      assert last["op_it"].present?
      assert sentence["tr"].key?(last["op_it"]), "the op of the last state"
      assert(last["parts"].all? { |p| sentence["tr"].key?(p["label_it"]) }, "the labels of the parts of the last state")
      words = served_figures(served["cards"]).find { |f| f["type"] == "word_parts" && f["states"].is_a?(Array) }
      assert words["tr"].key?(words["states"].last["op_it"])
      assert(words["states"].last["words"].all? { |w| words["tr"].key?(w["label_it"]) })
      mirror = served_figures(served["cards"]).find { |f| f["type"] == "mirror" }
      notes = mirror["rows"].flat_map { |r| r["notes"].map { |n| n["note_it"] } }
      assert_operator notes.size, :>=, 2
      assert(notes.all? { |n| mirror["tr"].key?(n) }, "every note of the mirror, the last too")
    end
  end

  test "the served flow carries its edge labels in tr and no edges_it" do
    flow = served_figures(figures("es")).find { |f| f["type"] == "flow" }
    assert_equal [ nil, "última", "penúltima" ], flow["edges"].map { |e| e[2] }
    assert_not flow.key?("edges_it")
    assert_equal({ "última" => "ultima", "penúltima" => "penultima" }, flow["tr"].slice("última", "penúltima"))
    assert_equal "Siempre tilde", flow["nodes"].find { |n| n["id"] == "b" }["text_it"]
    assert_equal "Sempre la tilde", flow["tr"]["Siempre tilde"]
  end
end
