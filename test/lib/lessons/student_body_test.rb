require "test_helper"
require_relative "../../support/lesson2_fixtures"
require_relative "../../support/lesson2_random"

# Lessons::StudentBody (A2): the whitelist, the cuts, the shuffle, and the sentinel property: no answer-side string of
# any random body occurs anywhere in what the student's page is told.
class LessonsStudentBodyTest < ActiveSupport::TestCase
  RUNS = Integer(ENV.fetch("PROP_RUNS", 50))
  F = Lesson2Fixtures
  WHITELIST = JSON.parse(Rails.root.join("test/fixtures/lesson2/whitelist.json").read)
  SCHEMA_DEFS = JSON.parse(Rails.root.join("config/banco/schemas/lesson.json").read).fetch("$defs")

  def body(file = "demo.md", subject = "math") = F.check(F.read(file), subject).body

  def project(body, seed: "student-key") = Lessons::StudentBody.project(body, revision_id: 41, seed: seed)

  def blocks_of(served, type) = served["cards"].flat_map { |c| c["blocks"] }.select { |b| b["type"] == type }

  # -- the sentinel property ------------------------------------------------------------------------------------

  test "no answer-side sentinel of any random body occurs in the served JSON (#{RUNS} runs)" do
    RUNS.times do |run|
      built = Lesson2Random.build(run)
      json = JSON.generate(project(built.body))
      leaked = built.sentinels.select { |s| json.include?(s) }
      assert_empty leaked, "run #{run}: #{leaked.first(3).inspect} reached the page"
      assert_includes json, "Domanda?" if json.include?("component")
    end
  end

  test "the property is not vacuous: a leak is seen when the projection serves an answer" do
    built = Lesson2Random.build(3)
    json = JSON.generate(built.body)
    assert(built.sentinels.any? { |s| json.include?(s) }, "the raw body holds its sentinels")
  end

  # -- the whitelist fixture ------------------------------------------------------------------------------------

  test "the fixture covers every declared field of every block and check def, in serve or drop" do
    WHITELIST["blocks"].each do |type, row|
      declared = SCHEMA_DEFS.fetch(row["def"]).fetch("properties").keys
      listed = row["serve"].grep(String) & declared | row["drop"]
      listed |= Array(row["serve_when_no_blank"])
      assert_empty declared - listed - row["serve"], "#{type}: fields neither served nor dropped"
    end
    WHITELIST["checks"].each do |component, row|
      next if component.start_with?("_")

      declared = SCHEMA_DEFS.fetch(row["def"]).fetch("properties").keys
      assert_empty declared - row["serve"] - row["drop"], "#{component}: fields neither served nor dropped"
    end
  end

  test "what the code serves for each block of the demos is a subset of the fixture's serve column" do
    %w[demo.md demo-italian.md].each do |file|
      served = project(body(file, file.include?("italian") ? "italian" : "math"))
      served["cards"].flat_map { |c| c["blocks"] }.each do |b|
        row = WHITELIST["blocks"][b["type"]] or next
        allowed = row["serve"] + Array(row["serve_when_no_blank"])
        assert_empty b.keys - allowed - %w[blocks], "#{file} #{b['type']}: #{(b.keys - allowed).inspect}"
      end
      served["cards"].flat_map { |c| c["blocks"] }.select { |b| b["type"] == "check" }.each do |b|
        allowed = WHITELIST["checks"].fetch(b["component"])["serve"] + %w[n type options left right spans accents]
        assert_empty b.keys - allowed, "#{file} check #{b['component']}"
      end
    end
  end

  test "the served front matter keeps the teacher's fields out" do
    served = project(body)
    assert_empty served.keys - WHITELIST["front_matter"]["serve"] - %w[cards], "front matter"
    %w[skills uses refs schema words pages].each { |k| assert_not served.key?(k), k }
  end

  # -- cuts and computed fields -----------------------------------------------------------------------------------

  test "an example is served up to its blank: the blank step has its reason and the question, nothing after" do
    ex = blocks_of(project(body), "example").find { |b| b["steps"].any? { |s| s["blank"] } }
    steps = ex["steps"]
    blank_at = steps.index { |s| s["blank"] }
    assert_equal blank_at + 1, steps.size, "nothing after the blank step"
    assert_nil steps[blank_at]["do_it"]
    assert steps[blank_at]["why_it"]
    assert_nil ex["result_it"]
    assert_equal "number", steps[blank_at]["blank"]["component"]
    assert_nil steps[blank_at]["blank"]["answer"]
  end

  test "an example without a blank is served whole, result_it included" do
    source = body
    ex = source["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "example" }
    ex["steps"].each { |s| s.delete("blank") }
    served = blocks_of(project(source), "example").first
    assert_equal ex["steps"].size, served["steps"].size
    assert_equal ex["result_it"], served["result_it"]
    assert(served["steps"].all? { |s| s["do_it"] })
  end

  test "the states of an example's diagram are cut with its steps" do
    source = body
    ex = source["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "example" }
    ex["diagram"] = { "type" => "balance", "alt_it" => "Una bilancia che cambia ad ogni passo.", "x_value" => "5", "left" => { "x" => 1 }, "right" => { "units" => 5 },
                      "states" => Array.new(ex["steps"].size) { |i| { "op_it" => "passo #{i}" } } }
    served = blocks_of(project(source), "example").first
    cut = ex["steps"].index { |s| s["blank"] }
    assert_equal cut, served["diagram"]["states"].size
  end

  test "a balance is served with a computed tilt per state and no x_value; show_value serves it" do
    d = { "type" => "balance", "alt_it" => "Bilancia in equilibrio con due scatole.", "x_value" => "2", "left" => { "x" => 2, "units" => 3 }, "right" => { "units" => 7 },
          "states" => [ { "op_it" => "uno" }, { "left" => { "x" => 2 }, "right" => { "units" => 4 }, "op_it" => "due" } ] }
    out = Lessons::StudentBody.diagram(d)
    assert_equal [ 0, 0 ], out["states"].map { |s| s["tilt"] }
    assert_not_includes JSON.generate(out), "x_value"
    assert_equal "2", Lessons::StudentBody.diagram(d.merge("show_value" => true))["x_value"]
    tilted = Lessons::StudentBody.diagram({ "type" => "balance", "alt_it" => "Bilancia sempre inclinata dalla parte sinistra.", "left" => { "x" => 2, "units" => 10 }, "right" => { "x" => 2, "units" => 3 } })
    assert_equal 1, tilted["tilt"]
  end

  test "try exercises are served without final, solution or answers; the checks are served like check blocks" do
    t = blocks_of(project(body), "try").first
    t["exercises"].each do |e|
      assert_empty e.keys - %w[n text_it diagram check checks]
      assert_nil e["check"]&.[]("answer")
    end
    assert(t["exercises"].any? { |e| e["check"] })
  end

  test "a span_select is served with spans re-keyed s1..sN" do
    check = blocks_of(project(body("demo-italian.md", "italian")), "check").find { |c| c["component"] == "span_select" }
    assert_equal %w[s1 s2 s3], check["spans"].map { |s| s["id"] }
    assert_nil check["answer"]
  end

  test "a normalized_text of an italian lesson carries the accents set" do
    check = { "type" => "check", "n" => 1, "component" => "normalized_text", "prompt_it" => "Scrivi il verbo.", "answer" => "è" }
    assert_equal "it", Lessons::StudentBody.block(check, "italian", "s")["accents"]
    assert_nil Lessons::StudentBody.block(check, "math", "s")["accents"]
  end

  # -- the shuffle ------------------------------------------------------------------------------------------------

  test "choice options are re-keyed o1..oN in shown order, per student, and the order is a function of the seed" do
    source = body
    check = source["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "check" && b["component"] == "choice" }
    a = project(source, seed: "ada")
    b = project(source, seed: "ada")
    assert_equal a, b
    shown = blocks_of(a, "check").find { |c| c["component"] == "choice" }["options"]
    assert_equal (1..check["options"].size).map { |i| "o#{i}" }, shown.map { |o| o["id"] }
    assert_equal check["options"].map { |o| o["text_it"] }.sort, shown.map { |o| o["text_it"] }.sort
  end

  test "round trip: every shown id is graded back to the stored answer, for a sample of seeds" do
    source = body
    card = source["cards"].find { |c| c["blocks"].any? { |b| b["type"] == "check" && b["component"] == "choice" } }
    check = card["blocks"].find { |b| b["type"] == "check" && b["component"] == "choice" }
    right_text = check["options"].find { |o| o["id"] == check["answer"] }["text_it"]
    rights = %w[ada bea cleo dino enzo fede gigi hugo].map do |student|
      seed = Lessons::StudentBody.seed_for(student, 41, card["n"], check["n"])
      served = Lessons::StudentBody.block(check, "math", seed)
      id_map = Lessons::Checks.id_map(check, seed)
      verdicts = served["options"].to_h { |o| [ o["text_it"], Lessons::Checks.grade(check, o["id"], id_map).verdict ] }
      assert_equal "right", verdicts.delete(right_text)
      assert_not_includes verdicts.values, "right"
      served["options"].index { |o| o["text_it"] == right_text }
    end
    assert_operator rights.uniq.size, :>, 1, "the right option is not always in the same place"
  end

  # Every property of a diagram type is served on purpose (listed here) or marked x-banco-solution. A new property fails
  # this test until someone decides which it is; declared properties are copied by Lessons::StudentBody.diagram.
  SERVED_DIAGRAM_FIELDS = {
    "equation_parts" => %w[type alt_it caption_it size parts brackets states],
    "number_line" => %w[type alt_it caption_it size min max step labels marks intervals jumps states],
    "balance" => %w[type alt_it caption_it size left right show_value try states],
    "area_model" => %w[type alt_it caption_it size rows cols cells states],
    "cartesian" => %w[type alt_it caption_it size x y grid points lines segments states],
    "sentence" => %w[type alt_it caption_it size text_it parts links layout mode states],
    "concept_map" => %w[type alt_it caption_it size root nodes edges links],
    "flow" => %w[type alt_it caption_it size nodes edges],
    "table" => %w[type alt_it caption_it size header rows]
  }.freeze

  test "every diagram property is served on purpose or marked x-banco-solution" do
    assert_equal SERVED_DIAGRAM_FIELDS.keys.sort, Lessons::Diagrams::TYPES.keys.sort
    Lessons::Diagrams::TYPES.each_key do |type|
      props = Lessons::Diagrams.schema_def(type).fetch("properties").keys
      unmarked = props - Lessons::Diagrams.solution_fields(type)
      assert_equal SERVED_DIAGRAM_FIELDS.fetch(type).sort, unmarked.sort, "#{type}: decide whether the new field is served or a solution"
    end
  end
end
