require "test_helper"
require_relative "../support/lesson_md"
require_relative "code_fixtures_test"

# Lessons: the good one passes and every lesson code has a bad fixture (A3.2).
class LessonChecksTest < ActiveSupport::TestCase
  L = LessonMd
  Validation::Findings # Zeitwerk loads lib/validation/findings.rb (which defines Validation::Codes) through this name

  def check(md, context: L.context)
    Validation::LessonChecks.call(md, subject: "math", context: context)
  end

  def codes(md, **opts) = check(md, **opts).findings.map(&:code).uniq

  test "the good lesson has no finding at all and a body of the banco.lesson/1 shape" do
    outcome = check(L.build)
    assert_empty outcome.findings.map(&:to_h).reject { |f| f[:code] == "W-ABSOLUTE" }
    assert_empty Banco::Schemas.validate("lesson", outcome.body)
    assert_equal 4, outcome.body["exercises"].size
    assert_equal "x = 3", outcome.body["exercises"][0]["final_it"]
    assert_nil outcome.body["try_intro_it"]
  end

  test "the parsed body is deterministic and carries the sections as written" do
    a = check(L.build).body
    assert_equal a, check(L.build).body
    assert_equal L::SECTIONS["mistakes_it"], a["sections"]["mistakes_it"]
  end

  test "Prova tu may start with introduction paragraphs" do
    outcome = check(L.build(sections: { "try" => "Fai in ordine.\n\n#{L::SECTIONS['try']}" }))
    assert_equal "Fai in ordine.", outcome.body["try_intro_it"]
  end

  test "an exercise with a nested list keeps it after a blank line" do
    outcome = check(L.build(sections: { "try" => "1. Risolvi:\n  - $2x = 4$\n  - $3x = 9$\n2. Risolvi: $5x = 10$.\n3. Spiega.\n4. Risolvi: $x - 4 = -1$." }))
    assert_equal "Risolvi:\n\n- $2x = 4$\n- $3x = 9$", outcome.body["exercises"][0]["text_it"]
  end

  CASES = {
    "E-LESSON-PARSE" => ->(t) { t.build.sub(/\A---\n/, "") },
    "E-LESSON-SECTIONS" => ->(t) { t.build(drop: [ "idea_it" ]) },
    "E-LESSON-MARKUP" => ->(t) { t.build(sections: { "idea_it" => "Il valore x^2 è grande." }) },
    "E-LESSON-WORDS" => ->(t) { t.build(sections: { "idea_it" => (([ "parola" ] * 12).join(" ") + ". ") * 45 }) },
    "E-LESSON-BOLD" => ->(t) { t.build(sections: { "idea_it" => "**Una bilancia in equilibrio** **un lato** **l'altro lato** **stessa cosa** **sempre uguale** **due lati**." }) },
    "E-LESSON-EXERCISES" => ->(t) { t.build(sections: { "try" => "1. Risolvi: $2x = 4$.\n2. Risolvi: $3x = 9$.", "solutions" => "1. $x = 2$.\n2. $x = 3$." }) },
    "E-LESSON-FINALS" => ->(t) { t.build(front: { "finals_it" => [ "x = 3" ] }) },
    "E-LESSON-BOOK" => ->(t) { t.build(sections: { "book_it" => "Leggi il capitolo." }) },
    "E-LESSON-PAGE" => ->(t) { t.build(sections: { "idea_it" => "Una equazione è una bilancia, come a pagina 12." }) },
    "E-LESSON-SUMMARY" => ->(t) { t.build(sections: { "summary_it" => "- Un solo punto." }) },
    "E-LESSON-REFS" => ->(t) { t.build(front: { "scope" => "seconda" }) },
    "W-LESSON-WHY" => ->(t) { t.build(sections: { "why_it" => "Le equazioni servono." }) },
    "W-LESSON-MISTAKES" => ->(t) { t.build(sections: { "mistakes_it" => "- Spostare un termine senza cambiargli il segno." }) },
    "W-LESSON-FINAL-MISSING" => ->(t) { t.build(front: { "finals_it" => [ "x = 3", "x = 7", nil, "x = 3" ] }) },
    "W-LESSON-FINAL-IN-TRY" => ->(t) { t.build(sections: { "try" => L::SECTIONS["try"].sub("$5x = 10$", "$5x = 10$, cioè $x = 2$") }) },
    "E-READ" => ->(t) { t.build(sections: { "idea_it" => ([ "parola" ] * 30).join(" ") + "." }) },
    "E-PHRASE" => ->(t) { t.build(sections: { "idea_it" => "Ti dico cosa scrivere nel compito." }) },
    "E-SCHEMA" => ->(t) { t.build(front: { "minutes" => "trenta" }) },
    "E-SKILL-UNKNOWN" => ->(t) { t.build(front: { "skills" => [ "math.demo-missing" ] }) },
    "E-SOURCE" => ->(t) { t.build(front: { "refs" => L::FRONT["refs"].map { |r| r["role"] == "taught_in" ? r.merge("fragment" => "non c'e") : r } }) }
  }.freeze

  CASES.each do |code, build|
    test "#{code} has a bad fixture" do
      assert_includes codes(build.call(L)), code
    end
  end

  test "every lesson code of the registry has a case here or in the review tests" do
    # the lesson/2 codes have their fixtures in test/fixtures/lesson2/bad until R1 runs them here (CodeFixturesTest::LESSON2)
    lesson_codes = Validation::Codes.all.keys.grep(/\A[EW]-LESSON-/) - %w[E-LESSON-REVIEW-RECOMPUTED] - CodeFixturesTest::LESSON2
    assert_empty lesson_codes - CASES.keys
  end

  test "a lesson for another subject, and a key that disagrees with its kind" do
    assert_includes codes(L.build(front: { "subject" => "italian", "key" => "ripasso.italian.demo-equations" })), "E-SCHEMA"
    parse = check(L.build(front: { "kind" => "ponte" })).findings.select { |f| f.code == "E-LESSON-PARSE" }
    assert_equal 1, parse.size
  end

  test "bare math is refused with its line, and the dollar form passes" do
    bad = check(L.build(sections: { "idea_it" => "Prima riga.\n\nIl numero 2^3 vale otto." })).findings.find { |f| f.code == "E-LESSON-MARKUP" }
    assert_match(/caret/, bad.message)
    assert_equal "/sections/idea_it", bad.field
    assert_not_includes codes(L.build(sections: { "idea_it" => "Prima riga.\n\nIl numero $2^3$ vale otto." })), "E-LESSON-MARKUP"
  end

  test "ripasso, ponte and lezione keep their ref rules" do
    ponte = L.build(front: { "kind" => "ponte", "key" => "ponte.math.demo-equations", "scope" => "not_in_prima" })
    assert_not_includes codes(ponte), "E-LESSON-REFS" # a taught_in ref on the previous year's programme is allowed
    prima_needed = L.build(front: { "kind" => "ponte", "key" => "ponte.math.demo-equations", "scope" => "not_in_prima", "refs" => [ L::FRONT["refs"][0], L::FRONT["refs"][1].merge("role" => "needed_by") ] })
    assert_includes codes(prima_needed), "E-LESSON-REFS"
    clean_ponte = L.build(front: { "kind" => "ponte", "key" => "ponte.math.demo-equations", "scope" => "middle_school", "refs" => [ L::FRONT["refs"][0] ] })
    assert_not_includes codes(clean_ponte), "E-LESSON-REFS"
    lezione = L.build(front: { "kind" => "lezione", "key" => "lezione.math.demo-equations", "scope" => "seconda", "refs" => [ L::FRONT["refs"][0].merge("role" => "taught_in") ] })
    assert_not_includes codes(lezione), "E-LESSON-REFS"
    assert_includes codes(L.build(front: { "kind" => "lezione", "key" => "lezione.math.demo-equations", "scope" => "seconda" })), "E-LESSON-REFS"
  end

  test "the word count equals the prep lint rule: a formula is one word" do
    assert_equal 4, Validation::LessonChecks.words("uno $x + y = 12$ due tre")
    assert_equal 3, Validation::LessonChecks.words("l'idea è bella")
  end

  test "a transcriber line cannot be cited" do
    refs = L::FRONT["refs"].map { |r| r["role"] == "taught_in" ? r.merge("line" => 2) : r }
    assert_includes codes(L.build(front: { "refs" => refs })), "E-SOURCE"
  end

  test "front matter YAML with an alias or a date is E-LESSON-PARSE" do
    assert_includes codes(L.build.sub("minutes: 30", "minutes: &a 30\nuses2: *a")), "E-LESSON-PARSE"
    assert_includes codes(L.build.sub("minutes: 30", "minutes: 2026-10-08")), "E-LESSON-PARSE"
  end
end
