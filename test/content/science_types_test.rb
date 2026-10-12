require "test_helper"

# formula, molecule, periodic_table and strand (T7, WAVE2 V1, V2): the Ruby side of the vectors in test/fixtures/diagrams/types/. The browser twin runs the
# same files (app/javascript/lesson/test/science.test.mjs): the semantic column (the first finding), the printed strings, the select targets and the layout.
class ScienceTypesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams/types")
  TYPES = %w[formula molecule periodic_table].freeze
  FILES = TYPES.to_h { |t| [ t, JSON.parse(DIR.join("#{t}.json").read) ] }.freeze

  def mod(type) = Lessons::Diagrams.const_get(Lessons::Diagrams::TYPES.fetch(type))

  test "the types are available, their files say so and no column is pending" do
    FILES.each do |type, doc|
      assert Lessons::Types.available?(:diagram, type), type
      assert(doc["vectors"].none? { |v| v["semantic"] == "pending" || v["layout"] == "pending" }, type)
      assert_equal "available", doc["status"]
      assert_operator doc["vectors"].size, :>=, 12, "#{type} has its cases"
    end
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

  test "printed: the strings of the first and the last state, the same set as the browser's" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["semantic"] == "ok" && v["schema"] == "valid" }.each do |v|
        assert_equal v["printed"], mod(type).printed(v["data"], 0).sort, "#{type}/#{v['name']}"
        n = Array(v["data"]["states"]).size
        assert_equal v["printed_last"], mod(type).printed(v["data"], n - 1).sort, "#{type}/#{v['name']} (last)" if n > 1
      end
    end
  end

  test "targets: the stored ids in reading order, one per piece, cell, base or atom" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["targets"] }.each do |v|
        v["targets"].each { |set, ids| assert_equal ids, mod(type).targets(v["data"], set), "#{type}/#{v['name']} #{set}" }
      end
    end
  end

  test "reachable: Avanti is the only control of a formula, so nothing is reachable beyond the states" do
    FILES.fetch("formula")["vectors"].select { |v| v["semantic"] == "ok" }.each { |v| assert_equal [], mod("formula").reachable(v["data"]), v["name"] }
  end

  # ---- formula ------------------------------------------------------------------------------------------------------------------------

  test "formula: served in select mode drops what labels or marks a piece, and the target names say what a piece is" do
    data = FILES["formula"]["vectors"].find { |v| v["name"] == "formula-brackets-and-count" }["data"]
    out = mod("formula").served(data, mode: :select)
    %w[show focus].each { |k| assert_not out.key?(k), k }
    assert_equal [ "2 Ca(NO3)2" ], out["formulas"]
    names = mod("formula").target_names(data, "pieces")
    assert_equal "coefficiente 2 in 2 Ca(NO3)2", names["f1p1"]
    assert_equal "simbolo Ca in 2 Ca(NO3)2", names["f1p2"]
    assert_equal "pedice 3 (di O) in 2 Ca(NO3)2", names["f1p5"]
    assert_equal "pedice 2 del pacchetto in 2 Ca(NO3)2", names["f1p6"]
    served = mod("formula").served(data)
    assert_equal data["show"], served["show"]
    assert_equal "O", served["focus"]
  end

  test "formula: the count rows are computed in integers, a coefficient and a bracket multiply every atom inside" do
    parsed = Lessons::Chem.parse("2 Ca(NO3)2")
    rows = Lessons::Diagrams::ScienceSupport.count_rows(parsed).to_h { |r| [ r["symbol"], r["total"] ] }
    assert_equal({ "Ca" => 2, "N" => 4, "O" => 12 }, rows)
    assert_equal Lessons::Chem.count("2 Ca(NO3)2"), rows
    assert_equal 6, Lessons::Diagrams::ScienceSupport.pieces(parsed).size
    assert_equal 9, Lessons::Diagrams::ScienceSupport.atoms_drawn("3 H2O")
    assert_nil Lessons::Diagrams::ScienceSupport.atoms_drawn("C6H12O6")
  end

  test "formula: chem.count is a verify function of the library, usable in a check" do
    problems = Lessons::Verify.problems({ "component" => "number", "answer" => "12", "verify" => { "fn" => "chem.count", "args" => { "formula" => "2 Ca(NO3)2", "pick" => "O" } } })
    assert_empty problems.map(&:message)
    wrong = Lessons::Verify.problems({ "component" => "number", "answer" => "6", "verify" => { "fn" => "chem.count", "args" => { "formula" => "2 Ca(NO3)2", "pick" => "O" } } })
    assert_equal [ "answer" ], wrong.map(&:path)
  end
end
