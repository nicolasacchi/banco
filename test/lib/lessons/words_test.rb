require "test_helper"

# Lessons::Words against the shared vectors of the browser twin (test/fixtures/lesson2/spanish_words.json and split.json;
# app/javascript/lesson/test/words.test.mjs). `present` is the W2-2 half and still refuses to run.
class LessonsWordsTest < ActiveSupport::TestCase
  VECTORS = JSON.parse(Rails.root.join("test/fixtures/lesson2/spanish_words.json").read)
  SPLIT = JSON.parse(Rails.root.join("test/fixtures/lesson2/split.json").read)
  BUILT = %w[split syllables_es stress_es tilde_ok].freeze

  def call(fn, args)
    w = Lessons::Words
    case fn
    when "split" then w.split(*args)
    when "syllables_es" then w.syllables_es(*args)
    when "stress_es" then w.stress_es(*args)
    when "tilde_ok" then w.tilde_ok?(*args)
    else flunk "unknown function #{fn}"
    end
  end

  test "the signatures are those of the vector file" do
    assert_equal VECTORS["functions"].keys.sort, Lessons::Words::SIGNATURES.keys.sort
    VECTORS["functions"].each { |name, spec| assert_equal spec["ruby"], Lessons::Words::SIGNATURES[name], name }
  end

  test "every vector case gives its result, and a refused case raises Refused" do
    BUILT.each do |fn|
      cases = VECTORS["functions"].fetch(fn)["cases"]
      assert_operator cases.size, :>=, 10, "#{fn} has cases"
      cases.each do |c|
        if c["refused"]
          assert_raises(Lessons::Words::Refused, "#{fn} #{c['args'].inspect}") { call(fn, c["args"]) }
        else
          assert_equal c["result"], call(fn, c["args"]), "#{fn} #{c['args'].inspect}"
        end
      end
    end
  end

  test "split.json holds the same cases in the notation file's shape" do
    SPLIT["cases"].each do |c|
      if c["refused"]
        assert_raises(Lessons::Words::Refused, c["input"]) { Lessons::Words.split(c["input"]) }
      else
        got = Lessons::Words.split(c["input"])
        assert_equal c["pieces"], got["pieces"], c["input"]
        assert_equal c["word"], got["word"], c["input"]
      end
    end
    mine = VECTORS["functions"]["split"]["cases"].reject { |c| c["refused"] }.map { |c| c["args"][0] }
    assert_equal mine.sort, SPLIT["cases"].reject { |c| c["refused"] }.map { |c| c["input"] }.sort
  end

  test "the syllables of a word joined are the word, tildes and capitals kept" do
    VECTORS["functions"]["syllables_es"]["cases"].reject { |c| c["refused"] }.each { |c| assert_equal c["args"][0], c["result"].join }
  end

  test "present is the W2-2 half" do
    assert_raises(Lessons::Words::NotBuilt) { Lessons::Words.present("poder", "o-ue") }
  end
end
