require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson2_fixtures"

# D-403, round 9 of the tooling (slice C, validators): what the fifth wave of authors met. Each message that was wrong or each rule that was narrowed has its false
# positive here and, next to it, the true positive it keeps.
class BilingualTooling9cTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  V = ValidationFixtures

  def en = DIR.join("lesson_en.md").read
  def es = DIR.join("lesson_es_figures.md").read
  def check(md, subject) = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))
  def found(outcome, *codes) = outcome.findings.select { |f| codes.include?(f.code) }

  # ---- 1. W-SENTENCE-COMMA-VARIANTS says what the grader does -----------------------------------------------------------------------------

  def commas(answer)
    unit = Validation::Units::Unit.new(path: "", skill: V::SKILL, component: "normalized_text", body: { "kind" => "diagnosis_item" }, generator: false, instances: [])
    inst = { "display" => { "stem_it" => "Completa la frase." }, "answer" => answer, "errors" => [], "solution" => { "steps" => [ { "text_it" => "Ragiona." } ], "final" => "Fatto." } }
    Validation::InstanceChecks.new(unit, context: V.context).call(inst, label: "/instances/2").select { |f| f.code == "W-SENTENCE-COMMA-VARIANTS" }
  end

  test "W-SENTENCE-COMMA-VARIANTS: the message says a comma-less form is a near miss, as the grader grades it, never «graded wrong»" do
    spec = Grading::Spec.new(component: "normalized_text", subject: "spanish", skill: "spanish.x", answer: "Como llovía, no salimos.", errors: [], spelling_policy: "near")
    assert_equal "near_miss", Grading.grade_spec(spec, "Como llovía no salimos").verdict, "the grader: one comma short is a near miss"
    assert_equal "wrong", Grading.grade_spec(spec, "Como, llovía no salimos").verdict, "the comma elsewhere is wrong"
    message = commas("Como llovía, no salimos.").sole.message
    assert_match(/graded as a near miss, not right/, message)
    assert_no_match(/graded wrong/, message)
    assert_match(/near miss/, Validation::Codes.all.fetch("W-SENTENCE-COMMA-VARIANTS")["description"])
  end

  # ---- 2. word-count errors name the field that is long, and a contraction is one word -----------------------------------------------------

  def callout(text) = en.sub("::: check choice", "::: callout tip \"Remember\" it=\"Ricorda\"\n#{text}\n:::\n\n::: it\nUsa il verbo base.\n:::\n\n::: check choice")

  test "E-CARD-WORDS names text_en when it counts the English text of a bilingual lesson; a lesson that is not bilingual keeps text_it" do
    long = ([ "word" ] * 43).join(" ")
    hit = found(check(callout(long), "english"), "E-CARD-WORDS").find { |f| f.message.start_with?("a callout has") }
    assert_not_nil hit
    assert_match(%r{/callout|/blocks/\d+/text_en\z}, hit.field)
    assert hit.field.end_with?("/text_en"), hit.field
    assert_match(/43 words/, hit.message)
    # the same block through a context with no language (a lesson/2 that is not bilingual) is about the Italian text
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: "math", findings: findings)
    ctx.at("/cards/0/blocks/1", 4) { Lessons::Blocks::Simple.check({ "type" => "callout", "text_it" => ([ "parola" ] * 43).join(" ") }, ctx) }
    assert_equal [ [ "E-CARD-WORDS", "/cards/0/blocks/1/text_it", "a callout has 43 words (at most 40)" ] ], findings.map { |f| [ f.code, f.field, f.message ] }
  end

  test "a contraction is one word: «I've», «I’ve» and «don't» count one each, so 40 words with contractions are not 43" do
    assert_equal 3, Validation::LessonChecks.words("I've I’ve don't")
    assert_equal 2, Validation::LessonChecks.words("l'albero l’acqua"), "the typographic apostrophe counts as the straight one"
    ok = ([ "I've" ] * 40).join(" ")
    assert_empty found(check(callout(ok), "english"), "E-CARD-WORDS").select { |f| f.message.start_with?("a callout has") }
    assert_equal 1, found(check(callout(([ "I've" ] * 41).join(" ")), "english"), "E-CARD-WORDS").count { |f| f.message.start_with?("a callout has") }, "41 words are still too many"
  end

  test "the 6-word concept-map node check names text_es when the long text is the Spanish one" do
    md = DIR.join("lesson_en_concept_map.md").read.gsub("text_en", "text_es").gsub("english", "spanish").gsub(/^(\s*- \{id: r, text_es: )"play"/, '\1"uno dos tres cuatro cinco seis siete"')
    hit = found(check(md, "spanish"), "E-LESSON-DIAGRAM").find { |f| f.message.start_with?("a node has") }
    assert_not_nil hit, check(md, "spanish").findings.map { |f| [ f.code, f.field, f.message ] }.first(5).inspect
    assert hit.field.end_with?("/nodes/0/text_es"), hit.field
    en_md = DIR.join("lesson_en_concept_map.md").read.sub('{id: r, text_en: "play"}', '{id: r, text_en: "one two three four five six seven"}')
    assert found(check(en_md, "english"), "E-LESSON-DIAGRAM").any? { |f| f.field.end_with?("/nodes/0/text_en") && f.message.start_with?("a node has 7 words") }
  end

  # ---- 5. warning noise ---------------------------------------------------------------------------------------------------------------------

  def absolute(md, subject) = found(check(md, subject), "W-ABSOLUTE").map { |f| [ f.field, f.detail[:word] ] }

  test "W-ABSOLUTE skips the taught word in a sentence figure (its text and parts) and in a dialogue's Italian gloss; a claim in a text still warns" do
    figure = es.sub('text_es: "Tú tienes tu dinero"', 'text_es: "Nunca tienes tu dinero"').sub('{id: a, text_es: "Tú", role: highlight', '{id: a, text_es: "Nunca", role: highlight')
    assert_empty absolute(figure, "spanish")
    dialogue = <<~MD
      ::: dialogue
      title_es: "Un diálogo"
      title_it: "Un dialogo"
      speakers:
        - {id: t, name: "Tom", voice: 1}
        - {id: a, name: "Amy", voice: 2}
      transcript: hidden
      lines:
        - {speaker: t, text_es: "¿Vienes al lago?", gloss_it: "Non sei mai stato al lago?"}
        - {speaker: a, text_es: "Sí, si no llueve.", gloss_it: "Sì, se non piove."}
      :::

    MD
    with_gloss = figure.sub("::: diagram sentence\nalt_es", "#{dialogue}::: diagram sentence\nalt_es")
    assert_empty absolute(with_gloss, "spanish")
    # true positive: the same word in a sentence of the lesson's own text (not a figure) is a claim
    claim = es.sub("Como en italiano, la voz suena más fuerte en una [[g:sílaba]].", "Siempre la voz suena más fuerte en una [[g:sílaba]].")
    assert_equal [ "siempre" ], absolute(claim, "spanish").map(&:last)
  end

  test "W-ABSOLUTE in Italian skips a word inside «…» (the taught «mai»); a claim written plain still warns" do
    lint = ->(text, role: :text) { Validation::Findings.new.tap { |f| Validation::Readability.lint(text, field: "/f", role: role, findings: f) }.map(&:code) }
    assert_not_includes lint.("Il contrario di «sempre» è «mai»."), "W-ABSOLUTE"
    assert_not_includes lint.("In inglese «never» e «mai» sono quasi la stessa parola."), "W-ABSOLUTE"
    assert_includes lint.("Il vento soffia sempre da nord."), "W-ABSOLUTE"
    assert_includes lint.("Il vento non soffia mai da nord, «sempre» no."), "W-ABSOLUTE"
  end

  def negative(item_display, bilingual: true)
    Validation::Findings.new.tap { |f| Validation::Readability.lint_document({ "display" => item_display }, "/instances/0", f, bilingual: bilingual) }.select { |f| f.code == "W-NEGATIVE-STEM" }.map(&:field)
  end

  test "W-NEGATIVE-STEM does not fire on a task_it that only describes a negative fact; the stem the student answers still does" do
    assert_empty negative({ "task_it" => "Di' in inglese che non sei mai stato in Giappone." })
    assert_empty negative({ "task_it" => "Non sei mai stato in Giappone: fai la domanda." }, bilingual: false)
    assert_equal [ "/instances/0/display/stem_it" ], negative({ "stem_it" => "Quale di queste frasi non è corretta?" }, bilingual: false)
    assert_equal [ "/instances/0/display/stem_it" ], negative({ "stem_it" => "Quale di queste frasi non è corretta?", "task_it" => "Non sei mai stato in Giappone." }, bilingual: false)
  end
end
