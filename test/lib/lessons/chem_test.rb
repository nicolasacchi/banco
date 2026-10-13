require "test_helper"

# Lessons::Chem against the shared vectors of the browser twin (test/fixtures/lesson2/chem_formulas.json; app/javascript/lesson/test/chem.test.mjs).
class LessonsChemTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/lesson2/chem_formulas.json").read)
  Chem = Lessons::Chem

  def run_case(fn, args)
    case fn
    when "parse" then Chem.parse(args[0])
    when "count" then Chem.count(args[0])
    when "classify" then Chem.classify(args[0])
    when "same_composition" then Chem.same_composition(args[0], args[1])
    else flunk "unknown function #{fn}"
    end
  end

  test "the signatures are those of the vector file" do
    assert_equal VECTORS["functions"].keys.sort, Chem::SIGNATURES.keys.sort
    VECTORS["functions"].each { |name, spec| assert_equal spec["ruby"], Chem::SIGNATURES[name], name }
  end

  test "every vector case gives its result (null is a formula that does not parse)" do
    VECTORS["functions"].each do |fn, spec|
      assert_operator spec["cases"].size, :>=, 10, "#{fn} has cases"
      spec["cases"].each do |c|
        got = run_case(fn, c["args"])
        c["result"].nil? ? assert_nil(got, "#{fn} #{c['args'].inspect}") : assert_equal(c["result"], got, "#{fn} #{c['args'].inspect}")
      end
    end
  end

  test "the grammar is case-exact: all 118 symbols parse alone, a changed case never does" do
    Chem.symbols.each do |s|
      assert Chem.parse(s), s
      assert_equal "element", Chem.classify(s)
      # "SI" is sulphur and iodine, never silicon: the upper-case word never reads as the symbol itself
      assert_not_includes Array(Chem.parse(s.upcase)&.fetch("groups")).map { |g| g["symbol"] }, s, "#{s.upcase} is not #{s}" if s.size > 1
      assert_nil Chem.parse(s.downcase), s.downcase
    end
    assert_equal 118, Chem.symbols.size
  end

  test "the counts equal the product of coefficient, subscripts and group subscripts; classify and same_composition follow" do
    assert_equal({ "N" => 4, "O" => 12, "Ca" => 2 }, Chem.count("2 Ca(NO3)2"))
    assert_equal "compound", Chem.classify("NaCl")
    assert Chem.same_composition("2 H2O", "H4O2")
    assert_not Chem.same_composition("CO", "Co")
    assert_equal "Ca(NO3)2", Chem.base("2 Ca(NO3)2(aq)")
    assert_nil Chem.base("CL2")
    assert_equal "Xx", Chem.unknown_symbol("Xx2")
    assert_nil Chem.unknown_symbol("H2O")
  end

  test "the chem.count verify function answers through the library route" do
    fn = Lessons::Verify.resolve("chem.count")
    assert_equal 12, fn.call.call("formula" => "2 Ca(NO3)2", "pick" => "O")
    assert_equal 6, fn.call.call("formula" => "3 H2O", "pick" => "H")
  end

  test "chem.count reads the element argument like pick, so a check gets a number and not the whole map" do
    fn = Lessons::Verify.resolve("chem.count")
    assert_equal 8, fn.call.call("formula" => "4 H2O", "element" => "H")
    assert_equal 4, fn.call.call("formula" => "4 H2O", "element" => "O")
    assert_equal 12, fn.call.call("formula" => "4 H2O"), "no element: all the atoms"
    assert_equal 7, fn.call.call("formula" => "Al(OH)3")
    assert_empty Lessons::Verify.problems({ "component" => "number", "answer" => "8", "verify" => { "fn" => "chem.count", "args" => { "formula" => "4 H2O", "element" => "H" } } })
  end
end
