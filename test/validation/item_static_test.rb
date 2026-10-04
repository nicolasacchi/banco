require "test_helper"
require_relative "../support/validation_fixtures"

# Validation of listed (static) items: no Chrome is needed. Each case builds a
# good item and breaks one thing.
class ItemStaticTest < ActiveSupport::TestCase
  F = ValidationFixtures

  def run_item(item, files: nil, context: F.context)
    Validation::ItemRunner.new(files: files || F.files_for(item), context: context).call
  end

  def codes(result) = result.findings.map(&:code).uniq

  test "the good static item passes with its listed instances" do
    result = run_item(F.static_item)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal 3, result.instances.size
    assert(result.instances.all? { |i| i[:fingerprint].match?(/\A\h{64}\z/) })
    assert_equal [ nil, nil, nil ], result.instances.map { |i| i[:seed] }
  end

  test "the good choice item passes" do
    result = run_item(F.choice_item)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "the good short answer item passes with one instance carrying the rubric" do
    result = run_item(F.short_answer_item)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal 1, result.instances.size
    assert_equal "Spiega con parole tue come si risolve un'equazione.", result.instances.first[:display]["stem_it"]
  end

  test "E-SCHEMA: a missing member stops the run" do
    result = run_item(F.static_item.except("sources"))
    assert_equal "failed", result.status
    assert_equal [ "E-SCHEMA" ], codes(result)
    assert_empty result.instances
  end

  test "E-SKILL-UNKNOWN: a skill that is not in the graph, a foreign own skill, no graph" do
    assert_includes codes(run_item(F.static_item("skill" => "math.nonexistent-skill"))), "E-SKILL-UNKNOWN"
    item = F.static_item("error_catalogue" => [ F.static_item["error_catalogue"].first.merge("implicates" => [ "math.imaginary" ]) ])
    assert_includes codes(run_item(item)), "E-SKILL-UNKNOWN"
    no_graph = F.context(graph: nil)
    assert_includes codes(run_item(F.static_item, context: no_graph)), "E-SKILL-UNKNOWN"
  end

  test "E-SOURCE: a line that is not there, a transcriber line, a fragment that is not a substring" do
    cases = {
      "prima-test:9" => "operazioni",
      "prima-test:2" => "PAGINA",
      "prima-test:1" => "una frase che non c'e",
      "no-colon" => "x"
    }
    cases.each do |ref, fragment|
      item = F.static_item("sources" => [ { "kind" => "prima_line", "ref" => ref, "fragment" => fragment } ])
      assert_includes codes(run_item(item)), "E-SOURCE", ref
    end
    ok = F.static_item("sources" => [ { "kind" => "prima_line", "ref" => "prima-test:1", "fragment" => "numeri relativi" } ])
    assert_not_includes codes(run_item(ok)), "E-SOURCE"
  end

  test "E-ASSET: an undeclared asset, a missing one, a script in an SVG, an external href, a big file" do
    svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>ciao</text></svg>'
    assert_includes codes(run_item(F.static_item, files: F.files_for(F.static_item, "assets/a.svg" => svg))), "E-ASSET"
    item = F.static_item("assets" => [ { "file" => "assets/a.svg", "source" => "disegno originale" } ])
    assert_includes codes(run_item(item)), "E-ASSET"
    {
      "<svg><script>1</script></svg>" => "script",
      '<svg><rect onclick="x()"/></svg>' => "handler",
      "<svg><foreignObject/></svg>" => "foreignObject",
      '<svg><image href="https://example.org/x.png"/></svg>' => "external",
      "<svg>#{'a' * 210_000}</svg>" => "size"
    }.each do |bad, why|
      result = run_item(item, files: F.files_for(item, "assets/a.svg" => bad))
      assert_includes codes(result), "E-ASSET", why
    end
    ok = run_item(item, files: F.files_for(item, "assets/a.svg" => svg))
    assert_not_includes codes(ok), "E-ASSET"
  end

  test "E-COMPOSITE: two implicated prerequisites need a composite skill" do
    catalogue = [
      { "code" => "sign_error", "description_it" => "Segno.", "message_it" => "Controlla il segno.", "implicates" => [ F::PREREQ, "math.factoring" ] }
    ]
    result = run_item(F.static_item("error_catalogue" => catalogue))
    assert_includes codes(result), "E-COMPOSITE"
    composite = F.context(extra_skills: { F::SKILL => F::GRAPH["skills"].find { |s| s["key"] == F::SKILL }.merge("composite_of" => [ F::PREREQ, "math.factoring" ]) })
    assert_not_includes codes(run_item(F.static_item("error_catalogue" => catalogue), context: composite)), "E-COMPOSITE"
  end

  test "E-ACCENT-POLICY: flag contradicts a paradigm form that differs only by accents" do
    item = {
      "schema" => "banco.item/1", "schema_version" => 1, "kind" => "diagnosis_item", "subject" => "math", "skill" => F::SKILL,
      "component" => "normalized_text", "accent_policy" => "flag", "paradigm_forms" => [ "esta", "está" ],
      "prompt" => { "stem_it" => "Scrivi la forma corretta." },
      "error_catalogue" => [ { "code" => "es_accents", "description_it" => "Accento.", "message_it" => "Controlla l'accento.", "implicates" => [] } ],
      "sources" => [ { "kind" => "inferred", "ref" => "p", "fragment" => "f" } ],
      "instances" => [
        { "display" => { "stem_it" => "Completa: él ___ aquí." }, "answer" => "está", "errors" => [ { "code" => "es_accents", "value" => "esta" } ], "solution" => { "steps" => [ { "text_it" => "Verbo." } ], "final" => "está" } },
        { "display" => { "stem_it" => "Completa: ella ___ allí." }, "answer" => "está", "errors" => [ { "code" => "es_accents", "value" => "esta" } ], "solution" => { "steps" => [ { "text_it" => "Verbo." } ], "final" => "está" } }
      ],
      "tests" => { "must_accept" => [ "está" ], "must_reject" => [ "sta" ], "blank" => "invalid" }
    }
    assert_includes codes(run_item(item)), "E-ACCENT-POLICY"
    assert_not_includes codes(run_item(item.merge("accent_policy" => "strict"))), "E-ACCENT-POLICY"
    assert_includes codes(run_item(F.static_item("accent_policy" => "strict"))), "E-ACCENT-POLICY" # not a text item
  end

  test "E-PROVA-A-PARAMS: listed instances on an exam structure" do
    item = F.static_item("sources" => [ { "kind" => "prova_a_structure", "ref" => "struttura", "fragment" => "esercizio 1" } ])
    assert_includes codes(run_item(item)), "E-PROVA-A-PARAMS"
  end

  test "E-PROVA-A-PARAMS: exclude_params keeps the exam's numbers out of the instances, whole numbers only" do
    hit = run_item(F.static_item("exclude_params" => [ "13" ]))
    assert_includes codes(hit), "E-PROVA-A-PARAMS"
    assert_not_includes codes(run_item(F.static_item("exclude_params" => [ "1" ]))), "E-PROVA-A-PARAMS" # 13 and 21 are other numbers
    assert_not_includes codes(run_item(F.static_item("exclude_params" => [ "99" ]))), "E-PROVA-A-PARAMS"
  end

  test "E-QUOTE-REF: a reference that does not exist or a quotation that is not in it" do
    quote = ->(ref, text) { F.static_item("prompt" => { "stem_it" => "Leggi.", "quote" => { "ref" => ref, "text" => text } }) }
    assert_includes codes(run_item(quote.call("no-ref", "ogni cosa"))), "E-QUOTE-REF"
    assert_includes codes(run_item(quote.call("ref-test", "una frase inventata"))), "E-QUOTE-REF"
    assert_not_includes codes(run_item(quote.call("ref-test", "ogni cosa ha il suo posto"))), "E-QUOTE-REF"
  end

  test "E-DISPLAY-KEY: a display that carries a key" do
    inst = F.number_instance(2, 9)
    inst["display"]["correct"] = "7"
    result = run_item(F.static_item("instances" => [ inst, F.number_instance(4, 13) ]))
    assert_equal [ "E-DISPLAY-KEY" ], codes(result)
  end

  test "E-SOLUTION-IN-DISPLAY: the answer in a table cell, or a choice's key text in the stem" do
    inst = F.number_instance(25, 150)
    inst["display"]["table"] = { "header" => [ "Valore" ], "rows" => [ [ "125" ] ] }
    result = run_item(F.static_item("instances" => [ inst, F.number_instance(4, 13) ]))
    assert_includes codes(result), "E-SOLUTION-IN-DISPLAY"

    leaky = F.choice_instance("sette", %w[tredici nove undici])
    leaky["display"]["stem_it"] = "Il valore sette risolve l'equazione?"
    result = run_item(F.choice_item("instances" => [ leaky, F.choice_instance("otto", %w[quattro sei dieci]) ]))
    assert_includes codes(result), "E-SOLUTION-IN-DISPLAY"
  end

  test "W-ANSWER-IN-STEM: the answer in the instruction of a non-choice item" do
    inst = F.number_instance(25, 150, stem: "Risolvi $x+25=150$ sapendo che il risultato e 125.")
    result = run_item(F.static_item("instances" => [ inst, F.number_instance(4, 13) ], "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" }))
    assert_includes codes(result), "W-ANSWER-IN-STEM"
    assert_equal "passed", result.status
  end

  test "E-CHOICE-OPTIONS: two options are never allowed; E-OPTION-DUPLICATE; E-DISTRACTOR-UNCODED" do
    two = F.choice_instance("sette", %w[tredici])
    two2 = F.choice_instance("otto", %w[quattro])
    result = run_item(F.choice_item("instances" => [ two, two2 ]))
    assert_includes codes(result), "E-CHOICE-OPTIONS"

    dup = F.choice_instance("sette", %w[sette nove undici])
    assert_includes codes(run_item(F.choice_item("instances" => [ dup, F.choice_instance("otto", %w[quattro sei dieci]) ]))), "E-OPTION-DUPLICATE"

    uncoded = F.choice_instance("sette", %w[tredici nove undici])
    uncoded["errors"].pop
    assert_includes codes(run_item(F.choice_item("instances" => [ uncoded, F.choice_instance("otto", %w[quattro sei dieci]) ]))), "E-DISTRACTOR-UNCODED"
  end

  test "W-LONGEST-CORRECT: the key is the longest option in most instances" do
    long = (1..4).map { |i| F.choice_instance("una risposta molto lunga numero #{i}", %w[uno due tre]) }
    result = run_item(F.choice_item("instances" => long))
    assert_includes codes(result), "W-LONGEST-CORRECT"
    assert_equal "passed", result.status
  end

  test "E-MATCHING-SIZE: fewer than four pairs, or a right column that is not n+1" do
    item = lambda do |left, right, answer|
      inst = { "display" => { "stem_it" => "Abbina.", "left" => left.map { |i| { "id" => "l#{i}", "text" => "sinistra #{i}" } }, "right" => right.map { |i| { "id" => "r#{i}", "text" => "destra #{i}" } } },
               "answer" => answer, "errors" => [ { "code" => "swap", "value" => answer.to_a.reverse.to_h } ],
               "solution" => { "steps" => [ { "text_it" => "Abbina." } ], "final" => "fatto" } }
      F.static_item("component" => "matching", "instances" => [ inst, inst.merge("display" => inst["display"].merge("stem_it" => "Abbina ancora.")) ],
                    "error_catalogue" => [ { "code" => "swap", "description_it" => "Scambio.", "message_it" => "Controlla.", "implicates" => [] } ], "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
    end
    three = item.call([ 1, 2, 3 ], [ 1, 2, 3, 4 ], { "l1" => "r1", "l2" => "r2", "l3" => "r3" })
    assert_includes codes(run_item(three)), "E-MATCHING-SIZE"
    same = item.call([ 1, 2, 3, 4 ], [ 1, 2, 3, 4, 5 ].first(5), { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r4" })
    assert_not_includes codes(run_item(same)), "E-MATCHING-SIZE"
  end

  test "E-COMPONENT-NUMERIC and E-EXPONENT-MULTIDIGIT on expression items" do
    expr = lambda do |answers, error|
      insts = answers.map do |a|
        { "display" => { "stem_it" => "Semplifica l'espressione per #{a.hash.abs}." }, "answer" => a,
          "errors" => [ { "code" => "slip", "value" => error } ], "solution" => { "steps" => [ { "text_it" => "Semplifica." } ], "final" => a } }
      end
      F.static_item("component" => "expression", "instances" => insts,
                    "error_catalogue" => [ { "code" => "slip", "description_it" => "Errore.", "message_it" => "Controlla.", "implicates" => [] } ],
                    "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
    end
    assert_includes codes(run_item(expr.call([ "12", "15" ], "11"))), "E-COMPONENT-NUMERIC"
    assert_includes codes(run_item(expr.call([ "\\frac{3}{4}", "\\frac{1}{2}" ], "5"))), "E-COMPONENT-NUMERIC"
    assert_includes codes(run_item(expr.call([ "x^{12}+1", "x^{10}+2" ], "x^2"))), "E-EXPONENT-MULTIDIGIT"
    result = run_item(expr.call([ "2x+3", "3x+4" ], "2x-3"))
    assert_not_includes codes(result), "E-COMPONENT-NUMERIC"
    assert_not_includes codes(result), "E-EXPONENT-MULTIDIGIT"
  end

  test "E-ROUNDTRIP: an error value equal to the key comes back correct; colliding errors; a failing must_accept" do
    same = F.number_instance(2, 9)
    same["errors"] = [ { "code" => "sign_error", "value" => "7" } ]
    assert_includes codes(run_item(F.static_item("instances" => [ same, F.number_instance(4, 13) ]))), "E-ROUNDTRIP"

    two = F.number_instance(2, 9)
    two["errors"] = [ { "code" => "sign_error", "value" => "11" }, { "code" => "other_error", "value" => "11" } ]
    catalogue = F.static_item["error_catalogue"] + [ { "code" => "other_error", "description_it" => "Altro.", "message_it" => "Controlla.", "implicates" => [] } ]
    result = run_item(F.static_item("instances" => [ two, F.number_instance(4, 13) ], "error_catalogue" => catalogue))
    assert(result.findings.any? { |f| f.code == "E-ROUNDTRIP" && f.detail[:rule] == "collision" })

    result = run_item(F.static_item("tests" => { "must_accept" => [ "8" ], "must_reject" => [], "blank" => "invalid" }))
    assert(result.findings.any? { |f| f.code == "E-ROUNDTRIP" && f.detail[:rule] == "must_accept" })
  end

  test "E-ERROR-NEVER-GENERATED: a catalogue error that no instance produces" do
    catalogue = F.static_item["error_catalogue"] + [ { "code" => "never_seen", "description_it" => "Mai.", "message_it" => "Controlla.", "implicates" => [] } ]
    assert_includes codes(run_item(F.static_item("error_catalogue" => catalogue))), "E-ERROR-NEVER-GENERATED"
  end

  test "E-ACCEPTS-RANDOM: a grader that accepts everything is caught (the grader is replaced)" do
    permissive = Grading::Result.new(verdict: "correct", grader: "closed")
    Grading.stub(:grade_spec, ->(_spec, _raw, **) { permissive }) do
      result = run_item(F.static_item)
      assert_includes codes(result), "E-ACCEPTS-RANDOM"
    end
  end

  test "E-STEP-INCONSISTENT: the solution ends on another value than the key" do
    inst = F.number_instance(2, 9)
    inst["solution"]["final"] = "x = 9"
    assert_includes codes(run_item(F.static_item("instances" => [ inst, F.number_instance(4, 13) ]))), "E-STEP-INCONSISTENT"
  end

  test "E-STEP-INCONSISTENT reads a LaTeX decimal comma as one number" do
    inst = F.number_instance(2, 9)
    inst["answer"] = "0,4"
    inst["solution"]["final"] = "$0{,}4$"
    assert_not_includes codes(run_item(F.static_item("instances" => [ inst, F.number_instance(4, 13) ]))), "E-STEP-INCONSISTENT"
    inst["solution"]["final"] = "$0{,}5$"
    assert_includes codes(run_item(F.static_item("instances" => [ inst, F.number_instance(4, 13) ]))), "E-STEP-INCONSISTENT"
  end

  test "readability: E-READ rules, E-PHRASE, E-MESSAGE and the warnings come from the item's Italian text" do
    long = "Risolvi l'equazione " + ([ "molto" ] * 30).join(" ") + "."
    assert(run_item(F.static_item("prompt" => { "stem_it" => long })).findings.any? { |f| f.code == "E-READ" && f.detail[:rule] == "sentence_length" })
    assert(run_item(F.static_item("prompt" => { "stem_it" => "Risolvi con ATTENZIONE." })).findings.any? { |f| f.detail[:rule] == "all_caps" })
    assert_includes codes(run_item(F.static_item("prompt" => { "stem_it" => "Scrivi la risposta che cercano." }))), "E-PHRASE"
    catalogue = [ F.static_item["error_catalogue"].first.merge("message_it" => "Uno. Due. Tre.") ]
    assert_includes codes(run_item(F.static_item("error_catalogue" => catalogue))), "E-MESSAGE"
    assert_includes codes(run_item(F.static_item("prompt" => { "stem_it" => "Il risultato non e sempre positivo." }))), "W-ABSOLUTE"
  end

  test "W-CALCULATOR: a numeric item in a subject that allows the calculator" do
    item = F.static_item("subject" => "business", "skill" => "business.invoice")
    ctx = F.context(subject: "business", extra_skills: { "business.invoice" => { "key" => "business.invoice" } })
    result = run_item(item, context: ctx)
    assert_includes codes(result), "W-CALCULATOR"
    ok = F.static_item("subject" => "business", "skill" => "business.invoice", "prompt" => { "stem_it" => "Puoi usare la calcolatrice. Risolvi." })
    assert_not_includes codes(run_item(ok, context: ctx)), "W-CALCULATOR"
  end

  test "E-CODE-GLOBAL: a file named generator.mjs is scanned even next to a static item" do
    files = F.files_for(F.static_item, "generator.mjs" => "export function generate() { return Math.random(); }")
    assert_includes codes(run_item(F.static_item, files: files)), "E-CODE-GLOBAL"
  end

  test "a testlet with five static sub-items materializes combined instances" do
    subs = (1..5).map do |i|
      F.static_item.slice("skill", "component", "prompt", "error_catalogue", "instances", "tests").merge("id" => "q#{i}")
    end
    testlet = {
      "schema" => "banco.item/1", "schema_version" => 1, "kind" => "testlet", "subject" => "math",
      "skill" => F::SKILL, "passage_it" => "Un breve testo di prova per cinque domande.", "expected_seconds" => 300,
      "sub_items" => subs, "sources" => [ { "kind" => "inferred", "ref" => "prova", "fragment" => "x" } ]
    }
    result = run_item(testlet)
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal 3, result.instances.size
    assert_equal %w[q1 q2 q3 q4 q5], result.instances.first[:answer].keys
  end
end
