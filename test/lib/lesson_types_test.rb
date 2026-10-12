require "test_helper"
require "open3"

# W2-0 (WAVE2-COMPONENTS 1.2, 5.1): the availability registry (config/banco/lesson_types.yml), what it generates, the stubs it points at,
# the schemas it must agree with, and how a directive is refused or let through the reserved dry run.
class LessonTypesTest < ActiveSupport::TestCase
  DATA = Lessons::Types.data
  DIAGRAMS = DATA.fetch("diagrams")
  SCHEMA = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).fetch("$defs")
  LESSON = JSON.parse(Rails.root.join("config/banco/schemas/lesson.json").read).fetch("$defs")
  FAMILIES = %w[graph time maps chart science computing words docs].freeze

  def js(path) = Rails.root.join("app/javascript/#{path}.js")

  test "every entry has a status, a batch and, apart from release 1, a track; the counts are the plan's" do
    DATA.slice("diagrams", "blocks", "checks").each do |kind, entries|
      entries.each do |name, e|
        assert_includes Lessons::Types::STATUSES, e["status"], "#{kind}.#{name}"
        assert_match(/\A(r1|r2|w2-[123])\z/, e["batch"], "#{kind}.#{name}")
        assert e["module"].present?, "#{kind}.#{name}"
        assert e["track"].present? || e["batch"] == "r1", "#{kind}.#{name}" unless kind == "blocks" && e["batch"] == "r1"
      end
    end
    assert_equal 38, DIAGRAMS.size # the 9 of release 1 and the 29 of wave 2 (26 with a schema, calendar, rgb and sheet only a name)
    assert_equal 29, DIAGRAMS.count { |_, e| e["family"] != "core" }
    assert_equal %w[calendar rgb sheet], DIAGRAMS.select { |_, e| e["schema"] == "none" }.keys.sort
    assert_equal %w[dialogue image oral reveal source], DATA["blocks"].select { |_, e| e["batch"].start_with?("w2") }.keys.sort
    assert_equal %w[amount_words cell_formula ordering select tiles trace], DATA["checks"].select { |_, e| e["batch"].start_with?("w2") }.keys.sort
  end

  test "available needs a final schema, a draft status a draft schema, and wave 2 starts with nothing available" do
    DIAGRAMS.each do |name, e|
      assert_equal "final", e["schema"], name if e["status"] == "available"
      assert_equal "draft", e["schema"], name if e["status"] == "draft"
      next if e["family"] == "core"

      assert_not_equal "available", e["status"], "#{name}: a track makes it available in the commit of its look gate"
      assert_equal "w2-2", e["batch"], name if e["status"] == "draft"
    end
  end

  test "the registry and diagram.json name the same types, the drafts are marked, the release is the batch" do
    with_schema = DIAGRAMS.reject { |_, e| e["schema"] == "none" }.keys
    assert_equal with_schema.sort, SCHEMA.select { |_, d| d.is_a?(Hash) && d.key?("x-banco-kind") }.keys.sort
    assert_equal with_schema.reject { |t| %w[concept_map table].include?(t) }.sort, SCHEMA.dig("any_diagram", "properties", "type", "enum").sort # the two schemas of release 1 are not drawings
    DIAGRAMS.each do |name, e|
      next if e["schema"] == "none"

      d = SCHEMA.fetch(name)
      assert_equal(e["family"] == "core" ? "1" : e["batch"], d["x-banco-release"], name)
      assert_equal e["status"] == "draft", d["x-banco-draft"] == true, name
      e["home_palette"] ? assert_equal(e["home_palette"], d["x-banco-home-palette"], name) : assert_nil(d["x-banco-home-palette"], name)
      assert_includes %w[diagram schema both], d["x-banco-kind"], name
      assert_equal false, d["additionalProperties"], name
    end
  end

  test "every module, stylesheet, locale and gallery the registry names exists; the families are the nine directories" do
    DIAGRAMS.each_value { |e| assert js(e["module"]).file?, e["module"] }
    DATA["blocks"].each_value { |e| assert js(e["module"]).file?, e["module"] }
    DATA["checks"].each_value { |e| assert js(e["module"]).file?, e["module"] }
    assert_equal FAMILIES.sort, DIAGRAMS.values.map { |e| e["family"] }.uniq.reject { |f| f == "core" }.sort
    FAMILIES.each do |f|
      assert Rails.root.join("app/assets/stylesheets/lesson/#{f}.css").file?, "css #{f}"
      assert Rails.root.join("test/fixtures/lesson2/gallery/#{f}.md").file?, "gallery #{f}"
      locale = YAML.safe_load_file(Rails.root.join("config/locales/lesson_#{f}.it.yml"))
      assert_equal({ "lesson_#{f}" => {} }, locale.fetch("it"), f)
    end
    assert Rails.root.join("test/fixtures/lesson2/gallery/checks.md").file?
  end

  test "the generated registries and the diagram schemas equal their build" do
    %w[bin/build-lesson-types bin/build-lesson-data bin/build-diagram-schema bin/build-palette bin/build-icons].each do |script|
      out, status = Open3.capture2e(Rails.root.join(script).to_s, "--check")
      assert status.success?, "#{script}: #{out}"
    end
  end

  test "a Ruby stub extends the contract for each type with a schema, and the contract refuses what is not built" do
    wave2 = DIAGRAMS.select { |_, e| e["family"] != "core" && e["schema"] != "none" }.keys
    wave2.each do |type|
      mod = Lessons::Diagrams.const_get(Lessons::Diagrams::TYPES.fetch(type))
      assert mod.singleton_class.include?(Lessons::Diagrams::Contract), type
      assert_nil mod.static({}, nil), type
      assert_nil mod.state({}, nil, ""), type
      assert_equal [], mod.reachable({}), type
      assert_equal({}, mod.verify_functions, type)
      assert_raises(NotImplementedError, type) { mod.served({}) }
      assert_raises(NotImplementedError, type) { mod.targets({}, "x") }
      assert_raises(NotImplementedError, type) { mod.printed({}, 0) }
    end
    assert_equal 500, Lessons::Diagrams::Contract::REACHABLE_CAP
    assert_equal Validation::Rules.get(:lesson2, :reachable_cap), Lessons::Diagrams::Contract::REACHABLE_CAP
  end

  test "lesson2.types has the caps of every type with a schema in wave 2 (flow as flow_line) and of the five new blocks" do
    caps = Validation::Rules.get(:lesson2, :types).keys
    expected = DIAGRAMS.select { |_, e| e["family"] != "core" && e["schema"] != "none" }.keys + %w[flow_line source reveal oral dialogue image]
    assert_equal expected.sort, caps.sort
    assert_equal 9, Validation::Rules.version
  end

  # Every key of lesson2.types is a diagram type, a block, or TYPE_VALUE of a view the registry lists (flow_line is flow layout: line): a cap for
  # something the registry does not know would never be read.
  test "every key under lesson2.types maps to a type or a view in lesson_types.yml" do
    views = Lessons::Types.data.slice("diagrams", "blocks").values.flat_map do |group|
      group.flat_map { |name, e| (e["views"] || {}).flat_map { |_field, values| values.keys.map { |value| "#{name}_#{value}" } } }
    end
    known = Lessons::Types.names(:diagram) + Lessons::Types.names(:block) + views
    unknown = Validation::Rules.get(:lesson2, :types).keys - known
    assert_empty unknown, "caps for names that lesson_types.yml does not list: #{unknown.join(', ')}"
  end

  test "Lessons::Types: status, usable, held-back views and options" do
    assert_equal "available", Lessons::Types.status(:diagram, "balance")
    assert_equal "reserved", Lessons::Types.status(:diagram, "network")
    assert_equal "draft", Lessons::Types.status(:diagram, "cell")
    assert_equal "available", Lessons::Types.status(:check, "choice")
    assert_nil Lessons::Types.status(:diagram, "venn")
    assert Lessons::Types.usable?(:diagram, "balance")
    assert_not Lessons::Types.usable?(:diagram, "network")
    assert Lessons::Types.usable?(:diagram, "network", allow_reserved: true)
    assert_not Lessons::Types.usable?(:diagram, "venn", allow_reserved: true)
    assert_equal "math", Lessons::Types.home_palette("balance")
    assert_equal [ [ "layout", "line", "reserved" ] ], Lessons::Types.held_back_uses(:diagram, "flow", { "layout" => "line" }).map { |f, v, s| [ f, v, s["status"] ] }
    assert_empty Lessons::Types.held_back_uses(:diagram, "flow", { "layout" => "tree" })
    assert_equal [ [ "text_en", "present" ] ], Lessons::Types.held_back_uses(:diagram, "sentence", { "states" => [ { "text_en" => "x" } ] }).map { |f, v, _| [ f, v ] }
    assert_equal [ "listen", "verify" ], Lessons::Types.held_back_options({ "component" => "choice", "listen" => {}, "verify" => {} }).map(&:first)
    assert_equal [ "input_bits" ], Lessons::Types.held_back_options({ "component" => "normalized_text", "input" => "bits" }).map(&:first)
    assert_empty Lessons::Types.held_back_options({ "component" => "number", "input" => "bits" })
  end

  def build(type, arg, body, **opts)
    Lessons::Directives.build({ type: type, arg: arg, title: nil }, body.lines.map(&:chomp), 10, **opts)
  end

  test "a directive of a type that is not available is refused with the reason, and passes the reserved dry run" do
    error = assert_raises(Lessons::Directives::Refused) { build("diagram", "network", "alt_it: x\nlayout: pair\n") }
    assert_match(/network is not available yet \(reserved; batch w2-1\)/, error.message)
    assert_equal 10, error.line
    error = assert_raises(Lessons::Directives::Refused) { build("diagram", "cell", "alt_it: x\n") }
    assert_match(/draft schema/, error.message)
    block, = build("diagram", "network", "alt_it: x\nlayout: pair\n", allow_reserved: true)
    assert_equal "network", block["diagram"]["type"]
    assert_equal "diagram", block["type"]
  end

  test "blocks, check components, layouts, views and check options held back are refused one by one" do
    assert_match(/reveal block is not available/, assert_raises(Lessons::Directives::Refused) { build("reveal", nil, "prompt_it: x\nanswer_it: y\n") }.message)
    assert_match(/page block is not available/, assert_raises(Lessons::Directives::Refused) { build("page", nil, "key: x\n") }.message)
    assert_match(/check component select/, assert_raises(Lessons::Directives::Refused) { build("check", "select", "prompt_it: x\n") }.message)
    assert_match(/flow layout: line/, assert_raises(Lessons::Directives::Refused) { build("diagram", "flow", "layout: line\nnodes: []\n") }.message)
    assert_match(/check option listen/, assert_raises(Lessons::Directives::Refused) { build("check", "choice", "prompt_it: x\nlisten: {text_en: hello}\n") }.message)
    assert_match(/unknown block type "venn"/, assert_raises(Lessons::Directives::Refused) { build("venn", nil, "a: 1\n") }.message)
    block, = build("reveal", nil, "prompt_it: x\nanswer_it: y\n", allow_reserved: true)
    assert_equal "reveal", block["type"]
    assert_equal "flow", build("diagram", "flow", "layout: tree\n")[0]["diagram"]["type"]
    assert_equal "choice", build("check", "choice", "prompt_it: x\n")[0]["component"]
  end

  test "the unknown-block message lists the blocks that are available, not the held back ones" do
    message = assert_raises(Lessons::Directives::Refused) { build("venn", nil, "a: 1\n") }.message
    assert_includes message, "callout"
    assert_includes message, "try"
    assert_not_includes message, "reveal"
  end

  BUILT_LIBS = [ Lessons::Bits ].freeze

  test "the libraries of WAVE2 1.10 have their signatures frozen, shared with their vector file, and raise until their track" do
    libs = { Lessons::Chrono => "chrono.json", Lessons::Dates => "dates.json", Lessons::NumWords => "amount_words.json", Lessons::Money => "money.json",
             Lessons::Chem => "chem_formulas.json", Lessons::Words => "spanish_words.json", Lessons::Verbs => "verbs.json", Lessons::Bits => "bits.json",
             Lessons::ProgramGrammar => "program.json", Lessons::Sheet => "sheet.json" }
    libs.each do |mod, file|
      doc = JSON.parse(Rails.root.join("test/fixtures/lesson2/#{file}").read)
      ruby = doc["functions"].select { |_, f| f["ruby"] }
      assert_equal ruby.keys.sort, mod::SIGNATURES.keys.sort, mod.name
      ruby.each do |fn, spec|
        assert_equal spec["ruby"], mod::SIGNATURES.fetch(fn)
        meth = spec["ruby"][/\A[a-z_?]+/]
        assert_respond_to mod, meth
        arity = mod.method(meth).parameters.count { |kind, _| kind == :req }
        next if BUILT_LIBS.include?(mod) # built by its track: its own test runs the vectors (test/lib/lessons/bits_test.rb)

        assert_raises(mod::NotBuilt, "#{mod.name}.#{meth}") { mod.public_send(meth, *Array.new(arity, "x")) }
      end
    end
    assert_equal %w[run listing], JSON.parse(Rails.root.join("test/fixtures/lesson2/program.json").read)["functions"].reject { |_, f| f["ruby"] }.keys, "Ruby parses a program, never runs it"
    assert_equal [ "parse" ], Lessons::ProgramGrammar::SIGNATURES.keys
  end

  test "each subject of wave 2 has its brief addendum, and every family its gallery skeleton says what to show" do
    %w[biology business chemistry computer-science english geography history law-economics spanish].each do |s|
      assert_includes Brief.names, "lesson-#{s}"
    end
    FAMILIES.each do |f|
      text = Rails.root.join("test/fixtures/lesson2/gallery/#{f}.md").read
      DIAGRAMS.select { |_, e| e["family"] == f }.each_key { |type| assert_includes text, "`#{type}`", "#{f}: #{type}" }
    end
  end

  test "the voices file and the generated list agree, and start empty: no accepted voice before the operator has listened" do
    voices = YAML.safe_load_file(Rails.root.join("config/banco/voices.yml"))
    assert_equal({ "it" => [], "en" => [], "es" => [] }, voices["accepted"])
    assert_equal "Safari", voices.dig("device", "browser")
    assert_equal %w[en es it], voices["preference"].keys.sort
  end
end
