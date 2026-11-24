require "test_helper"
require_relative "../../support/lesson2_fixtures"

# D-402, round 3 of the pilots: a lesson check on form material has a place for its sentence (`sentence_<lang>`, drawn above the options, target-only, no Italian
# twin), and a typed «Prova tu» exercise needs no `text_<lang>` when its `input_before` / `input_after` carry the sentence. Schema, pairs, validators and the
# served body, against the golden english lesson with one edit each.
class BilingualSentenceTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  SENTENCE = %(translate_material: false\nsentence_en: "She ___ the guitar very well."\noptions:\n  - {id: a, text_en: "plays"})
  PLAIN = %(translate_material: false\noptions:\n  - {id: a, text_en: "plays"})
  CHOICE_EXERCISE = <<~YAML.freeze
    text_en: "You should ___ more water."
        check:
          component: choice
          prompt_en: "Which word fits?"
          prompt_it: "Quale parola va bene?"
          options:
            - {id: a, text_en: "drinks"}
            - {id: b, text_en: "drink"}
          answer: b
  YAML
  TYPED = <<~YAML.freeze
    check:
          component: normalized_text
          prompt_en: "Write the missing word."
          prompt_it: "Scrivi la parola che manca."
          input_before: "You should"
          input_after: "more water."
          answer: "drink"
  YAML

  def source = DIR.join("lesson_en.md").read
  def check(md, subject = "english") = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))
  def parse(md) = Lessons::Parser2.call(md, Validation::Findings.new)
  def mine(outcome) = outcome.findings.select { |f| f.code.start_with?("E-LANG-", "E-SCHEMA", "E-LESSON-BLOCK", "W-LANG-") || %w[E-LESSON-CHECK E-LESSON-MARKUP].include?(f.code) }
  def with_sentence(extra = "") = source.sub(PLAIN, SENTENCE + extra)
  def served(md) = Lessons::StudentBody.project(parse(md).body, revision_id: 1, seed: "preview")
  def typed_exercise(md) = md.sub(CHOICE_EXERCISE, TYPED)

  test "the derived schema gives a check of a language subject its sentence_en and sentence_es; a lesson of another subject has none" do
    read = ->(bilingual) { Banco::Schemas.read("lesson", bilingual: bilingual) }
    props = ->(schema) { schema.dig("$defs", "check_spec", "properties").keys }
    assert_includes props.call(read.call(true)), "sentence_en"
    assert_includes props.call(read.call(true)), "sentence_es"
    assert_not_includes props.call(read.call(false)), "sentence_en"
    assert_not_includes read.call(true).dig("$defs", "exercise", "required"), "text_it"
    assert_includes read.call(false).dig("$defs", "exercise", "required"), "text_it"
  end

  test "a check choice with a sentence_en is clean: no pair, no level word, no schema or block finding" do
    outcome = check(with_sentence)
    assert_empty mine(outcome).map { |f| [ f.code, f.field, f.message ] }
    assert_equal "She ___ the guitar very well.", parse(with_sentence).body.dig("cards", 0, "blocks", 1, "sentence_en")
  end

  test "the sentence is target-only: sentence_it beside it is E-LANG-PAIR-ORPHAN, naming the field" do
    md = with_sentence.sub(%(sentence_en: "She ___ the guitar very well."), %(sentence_en: "She ___ the guitar very well."\nsentence_it: "Lei ___ la chitarra."))
    orphan = check(md).findings.select { |f| f.code == "E-LANG-PAIR-ORPHAN" }
    assert_equal [ "/cards/0/blocks/1/sentence_it" ], orphan.map(&:field)
    assert_match(/target-only|form material/, orphan.first.message)
  end

  test "the words of the sentence are not read for the level" do
    md = with_sentence.sub("She ___ the guitar very well.", "She ___ the brujúla very well.")
    assert_empty check(md).findings.select { |f| f.code == "W-LANG-LEVEL" && f.detail[:words].to_a.include?("brujúla") }
  end

  test "a typed gap and a span_select hold their sentence elsewhere: sentence_en on them is E-LESSON-CHECK" do
    md = typed_exercise(source).sub(%(      answer: "drink"\n), %(      answer: "drink"\n      sentence_en: "You should ___ more water."\n))
    found = check(md).findings.select { |f| f.code == "E-LESSON-CHECK" && f.field.end_with?("/sentence_it") }
    assert_equal 1, found.size
    assert_match(/input_before \/ input_after/, found.first.message)
  end

  test "sentence_en in a lesson without the flag, or in the other language, is E-LANG-BILINGUAL-FLAG" do
    cards = parse(with_sentence).body.slice("cards")
    flagged = ->(lang, target) { [].tap { |found| Validation::Lesson2Checks.flag_pairs(cards, "", lang, target) { |field, why| found << [ field, why ] if field.end_with?("/sentence_en") } } }
    assert_empty flagged.call("en", "en")
    assert_equal [ [ "/cards/0/blocks/1/sentence_en", "sentence_en belongs to a bilingual lesson (bilingual: true in the front matter)" ] ], flagged.call(nil, "en")
    assert_equal [ [ "/cards/0/blocks/1/sentence_en", "sentence_en is in English and the subject teaches Spanish" ] ], flagged.call("es", "es")
  end

  test "the served check has the sentence in the sentence_it slot, with no tr entry and no sentence_en" do
    body = served(with_sentence)
    check = body.dig("cards", 0, "blocks", 1)
    assert_equal "She ___ the guitar very well.", check["sentence_it"]
    assert_not check.key?("sentence_en")
    assert_not_includes JSON.generate(check["tr"] || {}), "guitar"
    assert_not_includes JSON.generate(body["tr"] || {}), "guitar"
  end

  test "the Italian layer of a check has no sentence, the target layer reads it as its own text" do
    doc = parse(with_sentence).body.dig("cards", 0, "blocks", 1)
    assert_not Lessons::Bilingual.italian_layer(doc).key?("sentence_en")
    assert_empty Lessons::Bilingual.pairs(doc, "en").select { |_p, base, _t, _i| base == "sentence" }.to_a
    assert_equal [ [ "", "sentence", "sentence_en", nil ] ], Lessons::Bilingual.material_fields(doc, "en").select { |_p, base, _t, _i| base == "sentence" }.to_a
  end

  test "a typed exercise whose input_before and input_after carry the sentence needs no text_en" do
    md = typed_exercise(source)
    assert_not_includes md, "You should ___ more water."
    assert_empty mine(check(md)).select { |f| f.code == "E-LESSON-BLOCK" || f.code == "E-SCHEMA" }.map { |f| [ f.code, f.field, f.message ] }
    exercise = served(md).dig("cards", 1, "blocks", 0, "exercises", 0)
    assert_not exercise.key?("text_it")
    assert_equal "You should", exercise.dig("check", "input_before")
  end

  test "an exercise with no text and no typed gap around a box is E-LESSON-BLOCK; a typed gap with no input_before or input_after is too" do
    none = source.sub(CHOICE_EXERCISE, CHOICE_EXERCISE.sub(/\Atext_en:.*\n\s*/, ""))
    found = check(none).findings.select { |f| f.code == "E-LESSON-BLOCK" }
    assert_equal [ "/cards/1/blocks/0/exercises/0/text_en" ], found.map(&:field)
    assert_match(/input_before \/ input_after/, found.first.message)
    bare = typed_exercise(source).sub(%(      input_before: "You should"\n), "").sub(%(      input_after: "more water."\n), "")
    assert_equal [ "/cards/1/blocks/0/exercises/0/text_en" ], check(bare).findings.select { |f| f.code == "E-LESSON-BLOCK" }.map(&:field)
  end

  test "input_before and input_after are inline: «14.» and «- 5 cm» at their start are text, not list items (E-LESSON-MARKUP); a prompt that is only «14.» still is" do
    md = typed_exercise(source).sub(%(input_after: "more water."), %(input_after: "14."))
    assert_empty check(md).findings.select { |f| f.code == "E-LESSON-MARKUP" }.map { |f| [ f.field, f.message ] }
    dash = typed_exercise(source).sub(%(input_after: "more water."), %(input_after: "- 5 cm"))
    assert_empty check(dash).findings.select { |f| f.code == "E-LESSON-MARKUP" }.map { |f| [ f.field, f.message ] }
    prompt = typed_exercise(source).sub(%(prompt_en: "Write the missing word."), %(prompt_en: "14."))
    assert_includes check(prompt).findings.select { |f| f.code == "E-LESSON-MARKUP" }.map(&:message).join, "list item without text"
  end

  test "Markup.raw_blocks with inline: true is one paragraph, whatever its first characters" do
    assert_equal [ [ :p, "14." ] ], Lessons::Markup.raw_blocks("14.", inline: true).map { |b| [ b.type, b.text ] }
    assert_equal [ [ :p, "1. a - b" ] ], Lessons::Markup.raw_blocks("1. a\n- b", inline: true).map { |b| [ b.type, b.text ] }
    assert_raises(Lessons::Markup::Refused) { Lessons::Markup.raw_blocks("14.") }
    assert_raises(Lessons::Markup::Refused) { Lessons::Markup.raw_blocks("*x*", inline: true) }
  end
end
