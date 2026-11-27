require "test_helper"
require_relative "../support/lesson2_fixtures"

# D-402, round 6 of the tooling (slice B): the plain-text fields of a figure (alt, notes and questions, in any language) refuse [[..]] markup in both layers of a
# bilingual lesson. The target layer was checked through the `_it` slots it is served in; the Italian translation was not, and passed the dry run to fail the render check.
class BilingualToolingSixTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  PLAIN = %w[E-LESSON-DIAGRAM E-LESSON-ALT].freeze

  def en = DIR.join("lesson_en_figures.md").read
  def plain(md) = Validation::LessonChecks.call(md, subject: "english", context: F.context("english")).findings.select { |f| PLAIN.include?(f.code) && f.message.include?("plain text") }.map { |f| [ f.code, f.field ] }

  test "the golden lesson has no plain-text finding" do
    assert_empty plain(en)
  end

  test "a mirror note with markup is refused in the target language (note_en) and in the Italian (note_it)" do
    target = en.sub('note_en: "has got: two words"', 'note_en: "[[en:has got]]: two words"')
    assert_equal [ [ "E-LESSON-DIAGRAM", "/cards/2/blocks/1/diagram/rows/0/notes/0/note_en" ] ], plain(target), "the target layer names the author's own field (D-403)"
    italian = en.sub('note_it: "has got: due parole"', 'note_it: "[[en:has got]]: due parole"')
    assert_equal [ [ "E-LESSON-DIAGRAM", "/cards/2/blocks/1/diagram/rows/0/notes/0/note_it" ] ], plain(italian)
  end

  test "an alt with markup is refused in both languages too" do
    assert_equal [ [ "E-LESSON-ALT", "/cards/2/blocks/1/diagram/alt_en" ] ], plain(en.sub('alt_en: "Two sentences, Italian above', 'alt_en: "[[en:Two]] sentences, Italian above'))
    assert_equal [ [ "E-LESSON-ALT", "/cards/2/blocks/1/diagram/alt_it" ] ], plain(en.sub('alt_it: "Due frasi, italiano sopra', 'alt_it: "[[en:Due]] frasi, italiano sopra'))
  end

  test "Lessons::Diagrams.plain_text walks states and rows of any figure and names the pointer" do
    figure = { "type" => "mirror", "states" => [ { "op_it" => "ok" }, { "rows" => [ { "notes" => [ { "note_es" => "mira [[es:el]]" } ] } ] } ] }
    found = Lessons::Diagrams.plain_text(figure, Lessons::Diagrams::Collector.new("spanish")).findings
    assert_equal [ [ "E-LESSON-DIAGRAM", "/states/1/rows/0/notes/0/note_es" ] ], found.map { |f| [ f.code, f.path ] }
    assert_empty Lessons::Diagrams.plain_text({ "label_it" => "a [[es:el]] label", "caption_it" => "[[es:x]]" }, Lessons::Diagrams::Collector.new("spanish")).findings, "labels and captions are rich text"
  end

  # lesson_en_more.md with the check of its «Prova tu» exercise made two checks (parts a and b); the first prompt is given
  def two_checks(first_en, first_it)
    checks = <<~Y
      checks:
        - component: choice
          prompt_en: "#{first_en}"
          prompt_it: "#{first_it}"
          options:
            - {id: a, text_en: "drinks"}
            - {id: b, text_en: "drink"}
          answer: b
        - component: choice
          prompt_en: "Which one is right?"
          prompt_it: "Quale è giusta?"
          options:
            - {id: a, text_en: "drinks"}
            - {id: b, text_en: "drink"}
          answer: b
    Y
    md = DIR.join("lesson_en_more.md").read
    replaced = md.sub(/^    check:\n(?:      .*\n)+?(?=    solution_en)/, checks.gsub(/^/, "    "))
    assert_not_equal md, replaced
    replaced
  end

  def labels(md) = Validation::LessonChecks.call(md, subject: "english", context: F.context("english")).findings.select { |f| f.code == "W-CHECK-LABEL-DOUBLED" }.map(&:field)

  test "a prompt that starts with its own label warns when the exercise has several checks: the page draws a), b) itself (round 6)" do
    assert_empty labels(two_checks("Which word fits?", "Quale parola va bene?"))
    [ "a) Which word fits?", "(a) Which word fits?", "b) Which word fits?", "A) Which word fits?" ].each do |prompt|
      assert_equal [ "/cards/1/blocks/0/exercises/0/checks/0/prompt_en" ], labels(two_checks(prompt, "Quale parola va bene?")).map { |f| f.sub("prompt_it", "prompt_en") }, prompt
    end
    # the Italian translation is drawn with the same label
    found = labels(two_checks("Which word fits?", "a) Quale parola va bene?"))
    assert_equal 1, found.size
    assert_match(%r{/exercises/0/checks/0/prompt_it}, found.first)
  end

  test "a single check has no label drawn, so a letter at the start is nothing to warn about; a word that merely starts with a letter is not a label" do
    md = DIR.join("lesson_en_more.md").read.sub('prompt_en: "Which word fits?"', 'prompt_en: "a) Which word fits?"')
    assert_empty labels(md)
    assert_empty labels(two_checks("A drink goes with which word?", "Quale parola va bene?"))
  end

  test "a concept_map that is form material is served with its marker, so the page draws its nodes without a translation (round 6)" do
    map = { "type" => "concept_map", "alt_it" => "Una mappa del verbo play con tre forme.", "root" => "r", "translate_material" => false,
            "nodes" => [ { "id" => "r", "text_it" => "play" }, { "id" => "a", "text_it" => "plays" } ], "edges" => [ { "from" => "r", "to" => "a" } ] }
    assert_equal false, Lessons::StudentBody.diagram_generic(map)["translate_material"]
    assert_not Lessons::StudentBody.diagram_generic(map.except("translate_material")).key?("translate_material")
  end
end
