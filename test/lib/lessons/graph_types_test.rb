require "test_helper"

# The graph family (WAVE2 2.1, T4b): network, chain and flow with layout line, against their vector files, in Ruby. The browser runs the
# same files (app/javascript/lesson/test/graph_types.test.mjs): the schema column, the semantic column (the first finding has the same
# code and path), the layout column and, for each good vector, what each state prints, describes and offers as select targets.
class GraphTypesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams")
  FILES = { "network" => "types/network.json", "chain" => "types/chain.json", "flow_line" => "flow_line.json" }.freeze
  DOCS = FILES.transform_values { |f| JSON.parse(DIR.join(f).read) }.freeze

  DOCS.each do |name, doc|
    doc["vectors"].each do |vec|
      test "#{name}: #{vec['name']} (schema and semantic columns)" do
        errors = Banco::Schemas.validate("diagram", vec["data"])
        if vec["schema"] == "invalid"
          assert_not_empty errors, "refused by the schema"
          next
        end
        assert_empty errors.map(&:to_h), "passes the schema"
        found = Lessons::Diagrams.check(vec["data"], subject: vec["subject"])
        if vec["semantic"] == "ok"
          assert_empty found.map(&:to_h), vec["name"]
        else
          assert found.any? { |f| f.code == vec["semantic"] && f.path == vec["path"] },
                 "#{vec['name']}: expected #{vec['semantic']} at #{vec['path']}, got #{found.map { |f| [ f.code, f.path ] }.inspect}"
        end
      end
    end
  end

  def good(name) = DOCS.fetch(name)["vectors"].select { |v| v["schema"] == "valid" && v["semantic"] == "ok" }

  def mod_for(vec) = Lessons::Diagrams.const_get(Lessons::Diagrams::TYPES.fetch(vec["data"]["type"]))

  def states_of(data) = [ 1, Array(data["states"]).size ].max

  test "printed (describe included) and targets of every good vector are the ones the file holds; the browser checks the same numbers" do
    DOCS.each_key do |name|
      good(name).each do |vec|
        mod = mod_for(vec)
        expected = vec.fetch("expect")
        assert_equal expected.fetch("printed"), (0...states_of(vec["data"])).map { |i| mod.printed(vec["data"], i) }, "#{vec['name']}: printed"
        assert_equal expected.fetch("targets"), target_sets(mod, vec), "#{vec['name']}: targets"
      end
    end
  end

  def target_sets(mod, vec)
    sets = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).dig("$defs", vec["data"]["type"], "x-banco-targets")
    sets.to_h { |s| [ s, mod.targets(vec["data"], s) ] }
  end

  def texts_of(node, out = [])
    case node
    when Hash then node.each { |k, v| v.is_a?(String) && k.end_with?("_it") ? out << v : texts_of(v, out) }
    when Array then node.each { |v| texts_of(v, out) }
    end
    out
  end

  test "the select form of a figure carries none of its texts (L3), and both forms are valid figures" do
    DOCS.each_key do |name|
      good(name).each do |vec|
        mod = mod_for(vec)
        neutral = mod.served(vec["data"], mode: :select)
        own = neutral["alt_it"]
        leaked = texts_of(vec["data"].except("alt_it", "caption_it")).uniq.select { |t| JSON.generate(neutral.except("alt_it")).include?(t) } - [ own ]
        assert_empty leaked, "#{vec['name']}: texts of the figure in its select form"
        assert_empty Banco::Schemas.validate("diagram", neutral).map(&:to_h), "#{vec['name']}: the select form is a valid figure"
        assert_empty Banco::Schemas.validate("diagram", mod.served(vec["data"])).map(&:to_h), "#{vec['name']}: the student's form is a valid figure"
      end
    end
  end

  test "network edge kinds and objects name icons that exist" do
    table = Lessons::VettedData.table("network/kinds")
    assert_empty Lessons::VettedData.errors("network/kinds")
    (table["kinds"].values + table["what"].values).each { |row| assert Lessons::Icons.known?(row["icon"]), row["icon"] }
    enum = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).dig("$defs", "network_edge", "properties")
    assert_equal enum.dig("kind", "enum").sort, table["kinds"].keys.sort
    assert_equal enum.dig("what", "enum").sort, table["what"].keys.sort
  end

  test "the second table of network/kinds, typed apart, says the same" do
    second = JSON.parse(Rails.root.join("test/fixtures/lesson2/network_kinds_expected.json").read)
    table = Lessons::VettedData.table("network/kinds")
    second["kinds"].each do |key, (label, arrow)|
      assert_equal label, table.dig("kinds", key, "label_it"), key
      assert_equal arrow, table.dig("kinds", key, "arrow"), key
    end
    assert_equal second["kinds"].keys.sort, table["kinds"].keys.sort
    second["what"].each { |key, label| assert_equal label, table.dig("what", key, "label_it"), key }
    assert_equal second["what"].keys.sort, table["what"].keys.sort
  end

  test "Togli una causa: what is left without a cause (chain)" do
    fan = good("chain").find { |v| v["name"] == "chain-fan-remove-states" }["data"]
    chain = Lessons::Diagrams::Chain
    assert_equal %w[c1 c2 c3 c4 c5 ev e1], chain.alive(fan, []).sort_by { |id| %w[c1 c2 c3 c4 c5 ev e1].index(id) }
    assert_includes chain.alive(fan, %w[c4]), "ev", "one cause left"
    assert_not_includes chain.alive(fan, %w[c4 c5]), "ev"
    assert_not_includes chain.alive(fan, %w[c4 c5]), "e1", "what the event led to loses its reason too"
    assert_includes chain.alive(fan, %w[c4 c5]), "c3", "a cause that is not taken away stays"
    assert_includes chain.describe(fan, removed: %w[c4 c5]), chain.text("hypothesis")
    assert_includes chain.describe(fan, removed: %w[c4]), chain.text("nothing_grey")
    assert_not_includes chain.describe(fan, removed: []), chain.text("hypothesis")
  end
end
