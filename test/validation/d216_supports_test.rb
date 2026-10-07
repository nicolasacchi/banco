require "test_helper"
require_relative "../support/validation_fixtures"

# D-216: answer_format_it and steps_it (item, sub item, instance display): readability lint,
# E-SUPPORT-LEAK on the key and the declared error values, W-STEPS-METHOD.
class D216SupportsTest < ActiveSupport::TestCase
  F = ValidationFixtures

  def run_item(item) = Validation::ItemRunner.new(files: F.files_for(item), context: F.context).call
  def codes(result) = result.findings.map(&:code).uniq
  def finding(result, code) = result.findings.find { |f| f.code == code }

  def big_item(extra = {})
    F.static_item({ "instances" => [ F.number_instance(5, 130), F.number_instance(4, 213), F.number_instance(7, 305) ],
                    "tests" => { "must_accept" => [ "125" ], "must_reject" => [ "135" ], "blank" => "invalid" } }.merge(extra))
  end

  test "good supports pass with no support finding" do
    result = run_item(big_item("answer_format_it" => "Scrivi un numero intero, per esempio 42.",
                               "steps_it" => [ "Leggi la consegna.", "Scrivi il valore di $x$.", "Controlla il segno." ]))
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_empty codes(result) & %w[E-SUPPORT-LEAK W-STEPS-METHOD E-READ]
  end

  test "a key in a step is E-SUPPORT-LEAK, at the step" do
    result = run_item(big_item("steps_it" => [ "Leggi la consegna.", "Il risultato e 125, controllalo." ]))
    assert_includes codes(result), "E-SUPPORT-LEAK"
    assert_equal "/steps_it/1", finding(result, "E-SUPPORT-LEAK").field
    assert_equal "failed", result.status
  end

  test "a declared error value in the answer format is E-SUPPORT-LEAK" do
    result = run_item(big_item("answer_format_it" => "Scrivi un numero, per esempio 135."))
    assert_equal "/answer_format_it", finding(result, "E-SUPPORT-LEAK").field
  end

  test "the check is per instance: the item text is refused for the instance whose key it states" do
    item = big_item("answer_format_it" => "Scrivi un numero, per esempio 209.")
    result = run_item(item)
    # 209 = 213 - 4 is the key of the second instance only.
    assert_equal "/answer_format_it", finding(result, "E-SUPPORT-LEAK").field
    assert_equal 1, result.findings.count { |f| f.code == "E-SUPPORT-LEAK" }
  end

  test "an instance display text is checked against its own instance" do
    item = big_item
    item["instances"][1]["display"]["answer_format_it"] = "Per esempio 209."
    item["instances"][0]["display"]["answer_format_it"] = "Per esempio 209."
    result = run_item(item)
    hits = result.findings.select { |f| f.code == "E-SUPPORT-LEAK" }
    assert_equal [ "/instances/1/display/answer_format_it" ], hits.map(&:field)
    assert_not_includes codes(result), "E-SOLUTION-IN-DISPLAY"
  end

  test "a choice item: an option text of the key or of a distractor in a step is refused" do
    item = F.choice_item("steps_it" => [ "Leggi le opzioni.", "Scegli quella che dice tredici." ])
    assert_equal "/steps_it/1", finding(run_item(item), "E-SUPPORT-LEAK").field
    ok = F.choice_item("steps_it" => [ "Leggi le opzioni.", "Scegli quella giusta." ])
    assert_not_includes codes(run_item(ok)), "E-SUPPORT-LEAK"
  end

  test "a testlet sub item is checked with its own text" do
    subs = (1..5).map do |n|
      F.static_item.slice("skill", "component", "prompt", "error_catalogue", "instances", "tests").merge("id" => "q#{n}")
    end
    subs[2]["instances"] = [ F.number_instance(2, 129), F.number_instance(4, 213), F.number_instance(5, 305) ]
    subs[2]["steps_it"] = [ "Leggi.", "Il risultato e 127 ma controlla." ]
    subs[2]["answer_format_it"] = "Scrivi un numero."
    testlet = { "schema" => "banco.item/1", "schema_version" => 1, "kind" => "testlet", "subject" => "math", "skill" => F::SKILL,
                "passage_it" => "Un breve testo di prova per cinque domande.", "expected_seconds" => 300, "sub_items" => subs,
                "sources" => [ { "kind" => "inferred", "ref" => "prova", "fragment" => "x" } ] }
    result = run_item(testlet)
    assert_equal "/sub_items/2/steps_it/1", finding(result, "E-SUPPORT-LEAK").field
  end

  test "supports are linted as Italian text, each step on its own" do
    result = run_item(big_item("steps_it" => [ "Leggi con ATTENZIONE.", "Scrivi _il valore_." ]))
    fields = result.findings.select { |f| f.code == "E-READ" }.map(&:field)
    assert_includes fields, "/steps_it/0"
    assert_includes fields, "/steps_it/1"
    result = run_item(big_item("answer_format_it" => "Scrivi il numero. " + ("parola " * 30)))
    assert_equal "/answer_format_it", finding(result, "E-READ").field
  end

  test "W-STEPS-METHOD: a method word of the subject is a warning, not an error" do
    result = run_item(big_item("steps_it" => [ "Leggi la consegna.", "Scomponi i termini." ]))
    assert_equal "W-STEPS-METHOD", finding(result, "W-STEPS-METHOD").code
    assert_equal "/steps_it", finding(result, "W-STEPS-METHOD").field
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    clean = run_item(big_item("steps_it" => [ "Leggi la consegna.", "Scrivi il risultato." ]))
    assert_not_includes codes(clean), "W-STEPS-METHOD"
  end

  test "schema: a steps_it of one step or of seven is E-SCHEMA" do
    assert_includes codes(run_item(big_item("steps_it" => [ "Solo uno." ]))), "E-SCHEMA"
    assert_includes codes(run_item(big_item("steps_it" => %w[a b c d e f g]))), "E-SCHEMA"
  end

  test "the registry knows both codes" do
    registry = YAML.load_file(Rails.root.join("config/banco/error_codes.yml"))["validation"]
    assert_equal "error", registry["E-SUPPORT-LEAK"]["severity"]
    assert_equal "warning", registry["W-STEPS-METHOD"]["severity"]
  end
end
