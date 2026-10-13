require "test_helper"
require "open3"

# chem/elements, chem/molecules and chem/terms (T7, WAVE2 1.9, D-270): the vetted tables of chemistry and their second tables. The first tables come from
# the primary sources (CIAAW, the IUPAC Italian table, PubChem for state and category, CCCBDB for geometry); the second tables are separate extractions
# (PubChem, Zanichelli, PubChem's 2D records) and the unit test compares the two and checks the internal consistency.
class ChemDataTest < ActiveSupport::TestCase
  V = Lessons::VettedData
  ELEMENTS = V.table("chem/elements").fetch("elements")
  EXPECTED = V.table("chem/elements_expected").fetch("expected")
  MOLECULES = V.table("chem/molecules").fetch("molecules")
  MOLECULES_EXPECTED = V.table("chem/molecules_expected").fetch("expected")
  TERMS = V.table("chem/terms")

  def num(text) = Lessons::Num.parse(text)

  test "all the tables are valid against their schemas, and each second table covers exactly the rows of the first" do
    %w[chem/elements chem/elements_expected chem/molecules chem/molecules_expected chem/terms].each { |t| assert_empty V.errors(t), t }
    assert_equal ELEMENTS.map { |e| e["symbol"] }.sort, EXPECTED.keys.sort
    assert_equal MOLECULES.keys.sort, MOLECULES_EXPECTED.keys.sort
  end

  test "the 118 elements: Z runs from 1 to 118, symbols are unique and case-exact, periods and groups sit where the layout puts them" do
    assert_equal (1..118).to_a, ELEMENTS.map { |e| e["z"] }
    symbols = ELEMENTS.map { |e| e["symbol"] }
    assert_equal symbols.uniq, symbols
    assert_equal symbols.map(&:downcase).uniq.size, symbols.size, "no two symbols differ only by case"
    symbols.each { |s| assert_match(/\A[A-Z][a-z]?\z/, s) }
    edges = [ 2, 10, 18, 36, 54, 86, 118 ]
    ELEMENTS.each do |e|
      assert_equal edges.index { |last| e["z"] <= last } + 1, e["period"], e["symbol"]
      f_block = (57..71).cover?(e["z"]) || (89..103).cover?(e["z"])
      f_block ? assert_nil(e["group"], e["symbol"]) : assert_includes(1..18, e["group"], e["symbol"])
      assert_equal "lanthanide", e["category"], e["symbol"] if (57..71).cover?(e["z"])
      assert_equal "actinide", e["category"], e["symbol"] if (89..103).cover?(e["z"])
    end
    by = ELEMENTS.to_h { |e| [ e["symbol"], e ] }
    { "H" => [ 1, 1 ], "He" => [ 18, 1 ], "Na" => [ 1, 3 ], "Cl" => [ 17, 3 ], "Ca" => [ 2, 4 ], "Fe" => [ 8, 4 ], "Br" => [ 17, 4 ], "Xe" => [ 18, 5 ], "Pb" => [ 14, 6 ], "Og" => [ 18, 7 ] }.each do |s, (g, p)|
      assert_equal [ g, p ], [ by[s]["group"], by[s]["period"] ], s
    end
    assert_equal %w[He Ne Ar Kr Xe Rn Og], ELEMENTS.select { |e| e["category"] == "noble_gas" }.map { |e| e["symbol"] }
    assert_equal %w[Br Hg], ELEMENTS.select { |e| e["state_25c"] == "liquid" }.map { |e| e["symbol"] }.sort
  end

  test "the Latin names are the ten of the books, and the masses are exact decimal numbers" do
    assert_equal %w[Ag Au Cu Fe Hg K Na Pb Sb Sn], ELEMENTS.select { |e| e["latin"] }.map { |e| e["symbol"] }.sort
    assert_equal "natrium", ELEMENTS.find { |e| e["symbol"] == "Na" }["latin"]
    ELEMENTS.each do |e|
      m = num(e["mass"])
      assert_operator m, :>, 0, e["symbol"]
      assert_operator m, :>=, e["z"], "#{e['symbol']}: a mass is at least Z" unless e["z"] == 1
      assert_operator m, :<=, 3 * e["z"] + 1, e["symbol"] if e["z"] > 1
    end
    assert_equal Rational(1, 1), num("1,0") / num("1,0")
    masses = ELEMENTS.map { |e| num(e["mass"]) }
    assert_equal masses.sort.size, masses.size
    assert_operator ELEMENTS.count { |e| e["mass"].match?(/\A\d+\z/) }, :>=, 30, "the elements with no standard weight carry a mass number"
  end

  test "the second table agrees: symbols, states, masses and names, except the rows whose difference is known and explained" do
    zanichelli_names = { "Kr" => "cripton", "Ho" => "olmio", "Hf" => "afnio", "Ds" => "darmstadio" } # the IUPAC Italian table (2024) spells them differently
    lr_isotope = "Lr" # IUPAC prints [262], the longest-lived isotope; PubChem lists the isotope 266
    ELEMENTS.each do |e|
      s = e["symbol"]
      x = EXPECTED.fetch(s)
      assert_equal s, x["symbol"], s
      assert_equal zanichelli_names.fetch(s, e["name_it"]), x["name_it"], "#{s}: name"
      known = x["state"].start_with?("expected_") || e["z"] >= 100 # never made in a weighable amount: unknown here, a solid or a gas there
      known ? assert_equal("unknown", e["state_25c"], "#{s}: state") : assert_equal(x["state"], e["state_25c"], "#{s}: state")
      band = e["mass"].match?(/\A\d+\z/) ? Rational(3, 2) : Rational(1, 2)
      next if s == lr_isotope

      assert_operator (num(e["mass"]) - num(x["mass"])).abs, :<=, band, "#{s}: mass #{e['mass']} against #{x['mass']}"
    end
  end

  # ---- molecules ------------------------------------------------------------------------------------------------------------------------

  def components(row)
    parent = (0...row["atoms"].size).to_a
    find = ->(i) { parent[i] == i ? i : (parent[i] = find.call(parent[i])) }
    row["bonds"].to_a.each { |a, b, _| parent[find.call(a)] = find.call(b) }
    (0...parent.size).group_by { |i| find.call(i) }.values
  end

  def tally(row) = row["atoms"].map { |a| a["symbol"] }.tally

  test "every molecule row: element symbols, bonds inside the atoms, the atoms of its formula, one piece when molecular" do
    MOLECULES.each do |key, row|
      row["atoms"].each { |a| assert Lessons::Chem.symbol?(a["symbol"]), "#{key}: #{a['symbol']}" }
      row["bonds"].to_a.each { |a, b, o| assert a < row["atoms"].size && b < row["atoms"].size && a != b && (1..3).cover?(o), "#{key}: bond #{[ a, b, o ]}" }
      case row["kind"]
      when "metal" then assert_equal [ { key => 1 } ], [ tally(row) ], key
      else assert_equal Lessons::Chem.count(key), tally(row), "#{key}: the atoms add up to the formula"
      end
      assert_equal 1, components(row).size, "#{key}: a molecule is one piece" if row["kind"] == "molecular"
      assert_nil row["angle"], key unless row["kind"] == "molecular"
      row["atoms"].each { |a| assert_equal 3, a["xyz"].size, key } if row["kind"] == "molecular"
    end
    assert_equal %w[CH4 CO CO2 Cl2 H2 H2O H2O2 N2 NH3 O2 O3], MOLECULES.select { |_, r| r["kind"] == "molecular" }.keys.sort
    assert_equal %w[Ca(NO3)2 Ca(OH)2 NaCl NaHCO3], MOLECULES.select { |_, r| r["kind"] == "ionic" }.keys.sort
    assert_equal %w[Co Fe], MOLECULES.select { |_, r| r["kind"] == "metal" }.keys.sort
  end

  test "the bond angle is the one the Cartesians give, rounded half up to 0,1" do
    MOLECULES.each do |key, row|
      next unless row["angle"]

      centre = row["atoms"].each_index.find { |i| row["bonds"].count { |a, b, _| a == i || b == i } == 2 }
      ends = row["bonds"].filter_map { |a, b, _| a == centre ? b : (b == centre ? a : nil) }
      v = ends.map { |i| row["atoms"][i]["xyz"].zip(row["atoms"][centre]["xyz"]).map { |p, c| num(p) - num(c) } }
      dot = v[0].zip(v[1]).sum { |p, q| p * q }
      cos = dot.to_f / (Math.sqrt(v[0].sum { |p| p * p }.to_f) * Math.sqrt(v[1].sum { |p| p * p }.to_f))
      degrees = (Math.acos([ [ cos, 1.0 ].min, -1.0 ].max) * 180 / Math::PI)
      assert_in_delta degrees, num(row["angle"]).to_f, 0.06, "#{key}: #{degrees}"
    end
    assert_equal %w[CO2 H2O O3], MOLECULES.select { |_, r| r["angle"] }.keys.sort
  end

  test "the sign of a partial charge follows the electronegativity of the bond, and a molecule's charges add up to zero" do
    pauling = { "H" => 2.20, "C" => 2.55, "N" => 3.04, "O" => 3.44, "Cl" => 3.16 }
    MOLECULES.each do |key, row|
      next unless row["partial_charges"]

      charges = row["partial_charges"].map { |c| num(c) }
      assert_equal row["atoms"].size, charges.size, key
      assert_equal 0, charges.sum, key
      row["bonds"].each do |a, b, _|
        ea = pauling.fetch(row["atoms"][a]["symbol"])
        eb = pauling.fetch(row["atoms"][b]["symbol"])
        next if (ea - eb).abs < 0.4

        assert_operator charges[ea > eb ? a : b], :<, charges[ea > eb ? b : a], "#{key}: the more electronegative atom of #{[ a, b ]} is the negative one"
      end
    end
    assert_nil MOLECULES["CO"]["partial_charges"], "CO has none on purpose"
    assert_nil MOLECULES["CH4"]["partial_charges"], "C-H differs by 0,35"
  end

  test "the drawing positions keep every atom apart and every bond long enough to be seen" do
    MOLECULES.each do |key, row|
      next unless row["kind"] == "molecular"

      pts = row["atoms"].map { |a| a["xy"].map { |c| num(c).to_f } }
      pts.combination(2) { |p, q| assert_operator Math.hypot(p[0] - q[0], p[1] - q[1]), :>=, 0.5, "#{key}: two atoms nearly on each other" }
    end
  end

  test "the second table of molecules agrees: bonds as multisets, the 3D angle within 6 degrees, the ions of a salt" do
    MOLECULES.each do |key, row|
      x = MOLECULES_EXPECTED.fetch(key)
      if row["kind"] == "molecular"
        ours = row["bonds"].map { |a, b, o| [ [ row["atoms"][a]["symbol"], row["atoms"][b]["symbol"] ].sort, o ] }.sort
        theirs = x["bonds"].map { |a, b, o| [ [ a, b ].sort, o ] }.sort
        assert_equal theirs, ours, "#{key}: bonds"
        assert_in_delta num(row["angle"]).to_f, num(x["angle_3d"]).to_f, 6.0, key if row["angle"] && x["angle_3d"]
      elsif row["kind"] == "ionic"
        assert_equal x["covalent_units"], components(row).size, "#{key}: ions"
        pubchem = x["formula"].scan(/([A-Z][a-z]?)(\d*)/).to_h { |sym, n| [ sym, n.empty? ? 1 : n.to_i ] }
        assert_equal Lessons::Chem.count(key), pubchem, "#{key}: PubChem's formula has the same atoms"
        assert_match(/\+/, x["smiles"], "#{key}: a cation")
        assert_match(/-/, x["smiles"], "#{key}: an anion")
        first = row["atoms"].first["symbol"]
        assert_includes %w[Na Ca], first, "#{key}: the cation comes first"
      end
    end
  end

  # ---- terms ----------------------------------------------------------------------------------------------------------------------------

  test "the changes of state: seven names, the heat goes in when the substance goes up the ladder solid, liquid, gas" do
    ladder = { "solid" => 0, "liquid" => 1, "gas" => 2 }
    changes = TERMS.fetch("changes")
    assert_equal %w[boiling condensation deposition freezing melting sublimation vaporization], changes.keys.sort
    changes.each do |id, c|
      up = ladder[c["to"]] > ladder[c["from"]]
      assert_equal up ? "heat_in" : "heat_out", c["energy"], id
    end
    # the second source, it.wikipedia 'Transizione di fase' (rev 151801031, 2026-10-12): fusione, solidificazione, sublimazione, brinamento, vaporizzazione, condensazione
    %w[melting freezing sublimation deposition vaporization condensation].zip(%w[fusione solidificazione sublimazione brinamento vaporizzazione condensazione]).each do |id, name|
      assert_equal name, changes[id]["name_it"], id
    end
    assert_equal "ebollizione", changes["boiling"]["name_it"]
    assert_equal "liquefazione", changes["condensation"]["also_it"]
    assert(changes.values.none? { |c| c["name_it"] == "deposizione" }, "deposizione is not used")
    assert_equal({ "from" => "solid", "to" => "gas" }, changes["sublimation"].slice("from", "to"))
  end

  test "the compiled data modules are current" do
    out, status = Open3.capture2e(Rails.root.join("bin/build-lesson-data").to_s, "--check")
    assert status.success?, out
  end
end
