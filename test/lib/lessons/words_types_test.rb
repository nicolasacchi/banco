require "test_helper"

# The words family (WAVE2 2.6, T3): word_parts and mirror against their vector files, in Ruby. The browser runs the same files
# (app/javascript/lesson/test/words_types.test.mjs): the schema column, the semantic column (code and path of the finding), the layout column and,
# for each good vector, what each state prints, describes and offers as select targets.
class WordsTypesTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/diagrams/types")
  FILES = { "word_parts" => "word_parts.json", "mirror" => "mirror.json" }.freeze
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
          assert_equal [ vec["semantic"], vec["path"] ], [ found.first&.code, found.first&.path ], "#{vec['name']}: the first finding (all: #{found.map { |f| [ f.code, f.path ] }.inspect})"
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
        sets = JSON.parse(Rails.root.join("config/banco/schemas/diagram.json").read).dig("$defs", vec["data"]["type"], "x-banco-targets")
        assert_equal expected.fetch("targets"), sets.to_h { |s| [ s, mod.targets(vec["data"], s) ] }, "#{vec['name']}: targets"
      end
    end
  end

  def texts_of(node, out = [])
    case node
    when Hash then node.each { |k, v| v.is_a?(String) && k.end_with?("_it") && !k.start_with?("form_") ? out << v : texts_of(v, out) }
    when Array then node.each { |v| texts_of(v, out) }
    end
    out
  end

  test "the select form of a figure is a valid figure and carries none of its marks, links, notes or meanings (L3)" do
    DOCS.each_key do |name|
      good(name).each do |vec|
        mod = mod_for(vec)
        neutral = mod.served(vec["data"], mode: :select)
        assert_empty Banco::Schemas.validate("diagram", neutral).map(&:to_h), "#{vec['name']}: the select form is a valid figure"
        assert_empty Banco::Schemas.validate("diagram", mod.served(vec["data"])).map(&:to_h), "#{vec['name']}: the student's form is a valid figure"
        json = JSON.generate(neutral.except("alt_it"))
        leaked = texts_of(vec["data"].except("alt_it", "caption_it")).uniq.select { |t| json.include?(t) }
        assert_empty leaked, "#{vec['name']}: texts of the figure in its select form"
        JSON.generate(neutral).scan(/"(?:form_\w+|pieces_\w+)":\s*(\[[^\]]*\]|"[^"]*")/).flatten.each { |v| assert_no_match(/[\[+]/, v.gsub(/\A\[|\]\z/, "")) }
      end
    end
  end

  test "the stored ids of the select targets name a piece or a syllable in reading order" do
    wp = good("word_parts").find { |v| v["name"] == "word_parts-syllables-spanish" }["data"]
    assert_equal %w[w1p1 w2p1], Lessons::Diagrams::WordParts.targets(wp, "pieces")
    assert_equal %w[w1s1 w1s2 w1s3 w2s1 w2s2], Lessons::Diagrams::WordParts.targets(wp, "syllables")
    assert_equal "re", Lessons::Diagrams::WordParts.target_names(wp, "syllables")["w1s2"]
    mr = good("mirror").find { |v| v["name"] == "mirror-pronouns" }["data"]
    assert_equal %w[r1i1 r1i2 r1t1 r1t2 r1t3], Lessons::Diagrams::Mirror.targets(mr, "pieces")
    assert_raises(ArgumentError) { Lessons::Diagrams::Mirror.targets(mr, "links") }
  end

  test "the Spanish syllables and the stressed one are computed, the others are written" do
    data = good("word_parts").find { |v| v["name"] == "word_parts-syllables-attached" }["data"]
    info = data["words"].map { |w| Lessons::Diagrams::WordParts.analyse(w) }
    assert_equal [ %w[dar lo], %w[dár se lo] ], info.map { |i| i[:syllables] }
    assert_equal [ 1, 1 ], info.map { |i| i[:stress] }
    assert_equal [ 1, 2 ], good("word_parts").find { |v| v["name"] == "word_parts-syllables-english" }["data"]["words"].map { |w| w["stress"] }
  end

  test "describe says the pieces, the meaning and where the voice falls in short Italian" do
    decode = good("word_parts").find { |v| v["name"] == "word_parts-decode-eucariote" }["data"]
    assert_equal "La parola eucariote è fatta di 2 pezzi: eu vuol dire vero, bene; cariote vuol dire nucleo. Tutto insieme: con un vero nucleo.", Lessons::Diagrams::WordParts.describe(decode)
    sy = good("word_parts").find { |v| v["name"] == "word_parts-syllables-spanish" }["data"]
    assert_includes Lessons::Diagrams::WordParts.describe(sy), "La parola queremos ha 3 sillabe: que, re, mos. La voce batte sulla sillaba numero 2: re."
  end
end
