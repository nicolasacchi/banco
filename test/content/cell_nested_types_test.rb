require "test_helper"

# cell (T7) and nested (T4b), D-312: the Ruby side of the vectors in test/fixtures/diagrams/types/{cell,nested}.json. The browser twin runs the same files
# (app/javascript/lesson/test/cell_nested.test.mjs): the semantic column (the first finding), the printed strings, the select targets and the layout.
class CellNestedTypesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams/types")
  TYPES = %w[cell nested].freeze
  FILES = TYPES.to_h { |t| [ t, JSON.parse(DIR.join("#{t}.json").read) ] }.freeze

  def mod(type) = Lessons::Diagrams.const_get(Lessons::Diagrams::TYPES.fetch(type))

  def vector(type, name) = FILES.fetch(type)["vectors"].find { |v| v["name"] == name }.fetch("data")

  # The findings of one check block, as [code, field] (the way test/validation/lesson_checks_wave2_test.rb runs one).
  def run_check(check, subject: "biology", path: "/cards/1/blocks/0")
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: subject, findings: findings)
    ctx.at(path, 7) { Lessons::Blocks::Check.check(check, ctx) }
    findings.map { |f| [ f.code, f.field ] }
  end

  test "the types are available from their look gate, their files say so and no column is pending" do
    FILES.each do |type, doc|
      assert Lessons::Types.available?(:diagram, type), type
      assert_equal "available", doc["status"]
      assert_equal "w2-2", doc["batch"]
      assert(doc["vectors"].none? { |v| v["semantic"] == "pending" || v["layout"] == "pending" }, type)
      assert_operator doc["vectors"].size, :>=, 12, "#{type} has its cases"
      assert_nil Lessons::Diagrams.schema_def(type)["x-banco-draft"], "#{type}: the schema is final"
    end
    assert_equal "biology", Lessons::Types.home_palette("cell")
    assert_nil Lessons::Types.home_palette("nested"), "nested draws in its lesson's palette"
  end

  test "the semantic column: the first finding of Diagrams.check is the one the file names" do
    FILES.each do |type, doc|
      doc["vectors"].each do |v|
        next unless v["schema"] == "valid"

        findings = Lessons::Diagrams.check(v["data"], subject: v["subject"])
        if v["semantic"] == "ok"
          assert_empty findings.map(&:to_h), "#{type}/#{v['name']} should be clean"
        else
          first = findings.first
          assert first, "#{type}/#{v['name']} should have a finding"
          assert_equal [ v["semantic"]["code"], v["semantic"]["path"] ], [ first.code, first.path ], "#{type}/#{v['name']}: #{first.message}"
        end
      end
    end
  end

  test "the schema column: Ruby's schema refuses what the file says it refuses" do
    FILES.each_value do |doc|
      doc["vectors"].each do |v|
        errors = Banco::Schemas.validate("diagram", v["data"])
        v["schema"] == "valid" ? assert_empty(errors.map(&:to_h), v["name"]) : assert_not_empty(errors, v["name"])
      end
    end
  end

  test "printed: the strings of the first and the last state, the same set as the browser's" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["semantic"] == "ok" && v["schema"] == "valid" }.each do |v|
        assert_equal v["printed"], mod(type).printed(v["data"], 0).sort, "#{type}/#{v['name']}"
        n = Array(v["data"]["states"]).size
        assert_equal v["printed_last"], mod(type).printed(v["data"], n - 1).sort, "#{type}/#{v['name']} (last)" if n > 1
      end
    end
  end

  test "targets: the stored ids in reading order, the same as the browser's; nothing is reachable through a control" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["targets"] }.each do |v|
        v["targets"].each { |set, ids| assert_equal ids, mod(type).targets(v["data"], set), "#{type}/#{v['name']} #{set}" }
        assert_equal [], mod(type).reachable(v["data"]), v["name"]
      end
    end
  end

  # Every string of a served figure (keys and values), the way the page source has them.
  def strings_of(x) = x.is_a?(Hash) ? x.flat_map { |k, v| [ k.to_s ] + strings_of(v) } : x.is_a?(Array) ? x.flat_map { |v| strings_of(v) } : x.is_a?(String) ? [ x ] : []

  test "L3 in the page source: no string of a served select figure is a stored id or the name of a target" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["targets"] }.each do |v|
        v["targets"].each_key do |set|
          served = Lessons::StudentBody.select_figure({ "diagram" => v["data"], "targets" => set })
          strings = strings_of(served).map { |s| s.strip.downcase }
          ids = mod(type).targets(v["data"], set).map(&:downcase)
          names = mod(type).target_names(v["data"], set).values.map { |n| n.strip.downcase }
          assert_empty strings & ids, "#{type}/#{v['name']}: the served select figure carries a stored id"
          assert_empty strings & names, "#{type}/#{v['name']}: the served select figure carries a target's name"
        end
      end
    end
  end

  # ---- cell ---------------------------------------------------------------------------------------------------------------------------

  test "cell: the kinds of the schema are the kinds of the table, the red blood cell held back" do
    enum = Lessons::Diagrams.schema_def("cell").dig("properties", "cells", "items", "properties", "kind", "enum")
    assert_equal enum.sort, (Lessons::VettedData.table("bio/cell_parts")["kinds"].keys + [ "red_blood" ]).sort
    assert_equal %w[wall membrane cytoplasm nucleoid ribosomes], mod("cell").targets(vector("cell", "cell-labels-none"), "parts").map { |id| id.delete_prefix("c1.") }
  end

  test "cell: true_scale is held back by the registry and refused by the checks; a false true_scale is fine" do
    held = Lessons::Types.held_back_uses(:diagram, "cell", { "true_scale" => true })
    assert_equal [ [ "true_scale", "true", "draft" ] ], held.map { |f, v, s| [ f, v, s["status"] ] }
    assert_empty Lessons::Types.held_back_uses(:diagram, "cell", { "true_scale" => false })
    assert_equal "/true_scale", Lessons::Diagrams.check(vector("cell", "cell-true-scale"), subject: "biology").first.path
  end

  test "cell: the select projection names, lights and notes nothing; every candidate is drawn alike; the target names are the parts' words" do
    data = vector("cell", "cell-tap-notes").merge("highlight" => [ "wall" ])
    out = mod("cell").served(data, mode: :select)
    %w[labels highlight paths fill notes states].each { |k| assert_not out.key?(k), k }
    assert_equal data["cells"], out["cells"], "the parts stay: the figure draws them, the ids never reach the page"
    signatures = mod("cell").select_signatures(data, "parts")
    assert_equal mod("cell").targets(data, "parts"), signatures.keys
    assert_equal 1, signatures.values.uniq.size
    names = mod("cell").target_names(data, "parts")
    assert_equal "DNA", names["c1.nucleoid"], "the bracket is dropped: the word an alt text must not say"
    assert_equal "parete cellulare", names["c1.wall"]
    assert_equal data, mod("cell").served(data).slice(*data.keys).merge("states" => data["states"]).compact, "the student's projection keeps the figure"
  end

  test "cell: a note on dna is the note of a bacterium's nucleoid; a eukaryotic cell's DNA gets a label of its own only when the figure names it" do
    tap = vector("cell", "cell-tap-notes")
    assert_includes mod("cell").printed(tap, 0), "Il DNA del batterio è un filo chiuso ad anello."
    assert_not_includes mod("cell").printed(tap, 0), Lessons::VettedData.table("bio/cell_parts").dig("parts", "nucleoid", "job_it")
    plain = vector("cell", "cell-compare-animal-plant")
    assert_not_includes mod("cell").printed(plain, 0), "DNA"
    named = vector("cell", "cell-highlight-dna-eukaryote")
    assert_includes mod("cell").printed(named, 0), "DNA", "named in a later state: labelled in every state, so the numbers never change"
  end

  test "cell: a select check over a cell offers its parts, grades ids, and refuses an alt text that names the answer" do
    figure = vector("cell", "cell-labels-none")
    check = { "type" => "check", "n" => 1, "component" => "select", "prompt_it" => "Tocca il DNA del batterio.", "diagram" => figure, "targets" => "parts", "pick" => "one",
              "answer" => [ "c1.nucleoid" ], "errors" => [ { "answer" => [ "c1.ribosomes" ], "message_it" => "Quelli sono i ribosomi." } ] }
    assert_equal({ "t1" => "c1.wall", "t2" => "c1.membrane", "t3" => "c1.cytoplasm", "t4" => "c1.nucleoid", "t5" => "c1.ribosomes" }, Lessons::SelectTargets.id_map(check))
    assert_empty run_check(check), "a clean select check over a cell"
    leaky = check.merge("diagram" => figure.merge("alt_it" => "Un batterio senza scritte: il DNA è il groviglio in mezzo."))
    assert_includes run_check(leaky).map(&:first), "E-CHECK-ANSWER-IN-ALT"
    wrong = check.merge("answer" => [ "c1.nucleus" ])
    assert_includes run_check(wrong), [ "E-LESSON-CHECK", "/cards/1/blocks/0/answer" ]
  end

  # ---- nested -------------------------------------------------------------------------------------------------------------------------

  test "nested: the targets are the levels from the outside in, named by their labels; the select projection has no focus, inside or states" do
    data = vector("nested", "nested-body-levels")
    assert_equal %w[organism system organ tissue cell], mod("nested").targets(data, "levels")
    assert_equal "tessuto", mod("nested").target_names(data, "levels")["tissue"]
    out = mod("nested").served(data, mode: :select)
    %w[focus inside states].each { |k| assert_not out.key?(k), k }
    assert_equal 1, mod("nested").select_signatures(data.merge("focus" => "organ"), "levels").values.uniq.size
    assert_includes mod("nested").printed(data, 0), "stanno dentro la cellula: non sono un livello del corpo"
    assert_equal "Il vivente intero", (mod("nested").printed(data, 4) - mod("nested").printed(data, 0)).first
  end

  test "nested: the served select figure has positional ids and one neutral label; the examples stay; the grading still maps tN to stored ids" do
    data = vector("nested", "nested-body-levels")
    out = mod("nested").served(data, mode: :select)
    assert_equal %w[l5 l4 l3 l2 l1], out["levels"].map { |l| l["id"] }, "stored inside out (the browser reverses), l1 the outermost: the target t1"
    assert_equal [ "·" ], out["levels"].map { |l| l["label_it"] }.uniq
    assert_equal data["levels"].map { |l| l["example_it"] }, out["levels"].map { |l| l["example_it"] }
    assert_empty Banco::Schemas.validate("diagram", out).map(&:to_h), "the served figure is a valid nested figure"
    assert_equal vector("nested", "nested-select-served"), out, "the vector the browser draws in select mode is this projection"
    # the gallery's check (card 12): the stem names the level it asks for; the figure in the page source never says "organo" nor the id "organ"
    body = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/gallery/science-biology.md").read, Validation::Findings.new).body
    check = body["cards"].flat_map { |c| c["blocks"] }.find { |b| b["type"] == "check" && b["targets"] == "levels" }
    served = Lessons::StudentBody.check(check, "biology", 1)
    assert_not served.key?("answer")
    assert_no_match(/organ/, served["diagram"].to_json)
    assert_includes served["diagram"].to_json, "il cervello"
    assert_equal "organ", Lessons::SelectTargets.id_map(check)["t3"], "the third box from the outside is the organ, as the stored check says"
  end
end
