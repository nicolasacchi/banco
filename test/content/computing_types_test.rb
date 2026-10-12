require "test_helper"

# register and column_calc (T9, WAVE2 V1, V2): the Ruby side of the vectors in test/fixtures/diagrams/types/{register,column_calc}.json. The browser
# twin runs the same files (app/javascript/lesson/test/computing.test.mjs): the semantic column (the first finding), the printed tokens, the
# select targets, and the layout of every case at four widths and three text sizes.
class ComputingTypesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams/types")
  FILES = %w[register column_calc].to_h { |t| [ t, JSON.parse(DIR.join("#{t}.json").read) ] }.freeze

  def mod(type) = Lessons::Diagrams.const_get(Lessons::Diagrams::TYPES.fetch(type))

  test "both types are available and no column is pending" do
    FILES.each do |type, doc|
      assert Lessons::Types.available?(:diagram, type), type
      assert(doc["vectors"].none? { |v| v["semantic"] == "pending" || v["layout"] == "pending" }, type)
      assert_equal "available", doc["status"]
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

  test "printed: the value tokens of the first and the last state" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["semantic"] == "ok" && v["schema"] == "valid" }.each do |v|
        assert_equal v["printed"], mod(type).printed(v["data"], 0).sort, "#{type}/#{v['name']}"
        n = Array(v["data"]["states"]).size
        assert_equal v["printed_last"], mod(type).printed(v["data"], n - 1).sort, "#{type}/#{v['name']} (last)" if n > 1
      end
    end
  end

  test "targets: the stored ids in reading order, one per cell or code" do
    FILES.each do |type, doc|
      doc["vectors"].select { |v| v["targets"] }.each do |v|
        v["targets"].each { |set, ids| assert_equal ids, mod(type).targets(v["data"], set), "#{type}/#{v['name']} #{set}" }
      end
    end
    assert_equal 8, mod("register").targets(FILES["register"]["vectors"].first["data"], "bits").size
    assert_equal 16, mod("register").targets(FILES["register"]["vectors"][1]["data"], "codes").size
    assert_empty mod("register").targets(FILES["register"]["vectors"][1]["data"], "bits"), "a ring has no bits"
    assert_empty mod("column_calc").targets(FILES["column_calc"]["vectors"].first["data"], "bits")
  end

  test "reachable: a toggling register shows every value of its width, up to the cap" do
    lab = FILES["register"]["vectors"].find { |v| v["name"] == "row-lab-toggle" }
    out = mod("register").reachable(lab["data"])
    assert_includes out, "45"
    assert_includes out, "11111111"
    assert_includes out, "255"
    wide = lab["data"].merge("width" => 16, "value" => "0" * 16, "goals" => nil).compact
    assert_equal :over_cap, mod("register").reachable(wide)
    assert_equal [], mod("register").reachable(FILES["register"]["vectors"].first["data"]), "without toggle nothing is reachable by the student"
    ring = FILES["register"]["vectors"][1]["data"]
    assert_includes mod("register").reachable(ring), "0101", "the stepper moves the pointer to every code"
  end

  test "served: the declared fields with the states merged; the select mode drops every mark" do
    data = FILES["register"]["vectors"].first["data"]
    out = mod("register").served(data)
    assert_equal "00000101", out["states"][0]["value"]
    assert_equal "11111011", out["value"], "the top level keeps its own value"
    assert_equal "5 su 8 bit", out["states"][0]["op_it"]
    select = mod("register").served(data, mode: :select)
    %w[mark read].each { |k| assert_not select.key?(k), k }
    assert_not select["states"].any? { |s| s.key?("op_it") }
    ring = mod("register").served(FILES["register"]["vectors"][1]["data"], mode: :select)
    %w[highlight moves pointer cliff step read].each { |k| assert_not ring.key?(k), k }
    cc = mod("column_calc").served(FILES["column_calc"]["vectors"].first["data"], mode: :select)
    %w[read reveal].each { |k| assert_not cc.key?(k), k }
    assert_equal "00000101", cc["a"]
  end

  test "verify functions: bits.read, bits.write and bits.add answer in the form a check holds" do
    f = mod("register").verify_functions
    assert_equal "-5", f["bits.read"].call("digits" => "11111011", "twos" => true)
    assert_equal "11111011", f["bits.write"].call("value" => "-5", "width" => 8, "twos" => true)
    assert_equal "00000000", f["bits.add"].call("a" => "00000101", "b" => "11111011", "width" => 8)
    assert_equal f.keys, mod("column_calc").verify_functions.keys
  end

  test "the work of a column_calc: carries, borrows across zeros and the partial products are computed" do
    cc = mod("column_calc")
    add = cc.work({ "op" => "add", "base" => 2, "width" => 8, "a" => "00000101", "b" => "11111011" })
    assert_equal "00000000", add["result"]
    assert_equal 1, add["carry_out"]
    assert_equal 1, add["extra"]
    sub = cc.work({ "op" => "sub", "base" => 2, "width" => 8, "a" => "10000000", "b" => "00000001" })
    assert_equal "01111111", sub["result"]
    assert_equal [ 0, 1, 1, 1, 1, 1, 1, 1 ], sub["borrows"], "the borrow runs across the zeros"
    assert_equal [ 0, 1, 1, 1, 1, 1, 1, 2 ], sub["adjusted"], "the digits it changes: the 1 gives, each 0 gives and takes, the last takes 2"
    mul = cc.work({ "op" => "mul", "base" => 2, "width" => 8, "a" => "11111111", "b" => "10" })
    assert_equal "11111110", mul["result"]
    assert mul["overflow"]
    assert_equal 1, mul["extra"]
  end
end
