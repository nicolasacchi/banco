require "test_helper"
require "support/grading_rows"

# D-402, slice 2: the review of a bilingual item. The reviewer and the solver read both layers (the translation is what the student opens), the
# solver never reads the Italian of a reading passage, and the checklist has two more points (14 and 15) only for a bilingual item or lesson.
class Review::BilingualReviewTest < ActiveSupport::TestCase
  C = Review::Checklist
  include GradingRows

  def golden = JSON.parse(Rails.root.join("test/fixtures/lang/item_choice_translated.json").read)

  def revision_of(body, instance)
    create_instance(body, instance).item_revision
  end

  test "the reviewer and the solver see both layers of the instance, the prompt and the supports" do
    body = golden
    revision = revision_of(body, body["instances"].first)
    text = Review::ItemText.new(revision)
    shown = text.solver_instances.first[:display]
    assert_equal "On Saturdays I ___ my bed and then I ___ the shopping with Dad.", shown["stem_en"]
    assert_equal "Il sabato io ___ il letto e poi io ___ la spesa con papà.", shown["stem_it"]
    assert_equal body["prompt"]["stem_en"], shown["prompt_stem_en"]
    assert_equal body["prompt"]["stem_it"], shown["prompt_stem_it"]
    assert_equal body["answer_format_en"], shown["answer_format_en"]
    assert_equal body["answer_format_it"], shown["answer_format_it"]
    assert_equal body["steps_en"], shown["steps_en"]
    assert_equal "fare / fare", shown["options"].first["text_it"]
    assert_equal shown, text.review_instances.first[:display]
    assert text.bilingual?
  end

  test "an item that says translate_material: false shows the solver the target sentence and options only; the instruction keeps both layers" do
    body = JSON.parse(Rails.root.join("test/fixtures/lang/item_choice.json").read)
    revision = revision_of(body, body["instances"].first)
    text = Review::ItemText.new(revision)
    shown = text.solver_instances.first[:display]
    assert text.material_off?
    assert_equal "On Saturdays I ___ my bed and then I ___ the shopping with Dad.", shown["stem_en"]
    assert_not shown.key?("stem_it"), "the sentence is not translated: stem_it must not read as its translation"
    assert_equal body["prompt"]["stem_it"], shown["prompt_stem_it"]
    assert_equal body["prompt"]["stem_en"], shown["prompt_stem_en"]
    assert_equal body["instances"][0]["display"]["options"].map { |o| o["text"] }, shown["options"].map { |o| o["text"] }
    assert_empty shown["options"].filter_map { |o| o["text_it"] }
    stored = body["instances"].first.deep_dup
    stored["display"]["options"][0]["text_it"] = "fare"
    stored["display"]["stem_it"] = "Il sabato io ___."
    leaked = Review::ItemText.new(revision_of(body.merge("skill" => "english.make-do-b"), stored)).solver_instances.first[:display]
    assert_not leaked.key?("stem_it"), "whatever is stored, the solver reads no Italian of the material"
    assert_empty leaked["options"].filter_map { |o| o["text_it"] }
  end

  test "a legacy item is shown exactly as before: no sibling key appears" do
    body = item_body("short-answer").merge("prompt" => { "stem_it" => "Ordina." })
    instance = create_instance(body, { "display" => { "stem_it" => "Calcola 2+2" }, "answer" => "4" })
    text = Review::ItemText.new(instance.item_revision)
    assert_not text.bilingual?
    assert_equal %w[prompt_stem_it stem_it], text.solver_instances.first[:display].keys.sort
  end

  test "the solver never reads the Italian of the reading passage of a bilingual item, the reviewer does; a legacy passage stays" do
    body = item_body("short-answer").merge("bilingual" => true, "subject" => "english",
                                           "passage_en" => "Tom wakes up at seven.", "passage_it" => "Tom si sveglia alle sette.", "prompt" => { "stem_en" => "Say when.", "stem_it" => "Di' quando." })
    revision = create_instance(body, { "display" => { "stem_en" => "When?", "stem_it" => "Quando?" }, "answer" => "7" }).item_revision
    text = Review::ItemText.new(revision)
    assert_equal "Tom wakes up at seven.", text.solver_instances.first[:display]["passage_en"]
    assert_not text.solver_instances.first[:display].key?("passage_it")
    assert_equal "Tom si sveglia alle sette.", text.review_instances.first[:display]["passage_it"]
    assert_equal "Say when.", text.solver_instances.first[:display]["prompt_stem_en"]

    testlet = item_body("short-answer").merge("kind" => "testlet", "bilingual" => true, "subject" => "english", "passage_en" => "A text.", "passage_it" => "Un testo.",
                                              "sub_items" => [ { "id" => "a", "prompt" => { "stem_en" => "Q?", "stem_it" => "D?" } } ])
    shown = Review::ItemText.new(create_instance(testlet, { "display" => { "passage_en" => "A text.", "passage_it" => "Un testo.",
                                                                           "sub_items" => [ { "id" => "a", "display" => { "stem_en" => "Q?", "stem_it" => "D?" } } ] }, "answer" => {} }).item_revision)
    assert_equal({ "passage_en" => "A text." }, shown.solver_instances.first[:display].slice("passage_en", "passage_it"))
    assert_equal "Un testo.", shown.review_instances.first[:display]["passage_it"]

    legacy = item_body("short-answer").merge("passage_it" => "An English text.")
    shown = Review::ItemText.new(create_instance(legacy, { "display" => { "stem_it" => "Q" }, "answer" => "1" }).item_revision)
    assert_equal "An English text.", shown.solver_instances.first[:display]["passage_it"], "in a legacy revision passage_it is the target text, as before"
  end

  test "an instance's own passage (display.passage_*) follows the same rule: the solver reads its target text only, the reviewer both, and it overrides the item's" do
    body = item_body("short-answer").merge("bilingual" => true, "subject" => "english", "passage_en" => "The item's text.", "passage_it" => "Il testo dell'esercizio.",
                                           "prompt" => { "stem_en" => "Say when.", "stem_it" => "Di' quando." })
    own = { "passage_en" => "Tom wakes up at seven.", "passage_it" => "Tom si sveglia alle sette.", "stem_en" => "When?", "stem_it" => "Quando?" }
    text = Review::ItemText.new(create_instance(body, { "display" => own, "answer" => "7" }).item_revision)
    solver = text.solver_instances.first[:display]
    assert_equal "Tom wakes up at seven.", solver["passage_en"], "the instance's text replaces the item's"
    assert_not solver.key?("passage_it")
    assert_not_includes JSON.generate(solver), "Il testo dell'esercizio", "nor does the item's Italian reach the solver"
    assert_not_includes JSON.generate(solver), "si sveglia"
    reviewer = text.review_instances.first[:display]
    assert_equal [ "Tom wakes up at seven.", "Tom si sveglia alle sette." ], reviewer.values_at("passage_en", "passage_it")

    legacy = item_body("short-answer").merge("passage_it" => "The item's text.")
    shown = Review::ItemText.new(create_instance(legacy, { "display" => { "stem_it" => "Q", "passage_it" => "Tom wakes up at seven." }, "answer" => "1" }).item_revision)
    assert_equal "Tom wakes up at seven.", shown.solver_instances.first[:display]["passage_it"], "in a legacy revision the instance's passage_it is the target text, as before"
  end

  test "a quote may be taken from either layer" do
    body = golden
    text = Review::ItemText.new(revision_of(body, body["instances"].first))
    assert text.quote?("Il sabato io ___ il letto")
    assert text.quote?("On Saturdays I ___ my bed")
    assert text.quote?("fare / fare")
  end

  # ---- the checklist -------------------------------------------------------------------------------------------------------------------

  test "the checklist has two more points only for a bilingual item, with ids 14 and 15; the old counts are kept" do
    assert_equal 11, C.expected_count(practice: false)
    assert_equal 13, C.expected_count(practice: true)
    assert_equal 13, C.expected_count(practice: false, bilingual: true)
    assert_equal 15, C.expected_count(practice: true, bilingual: true)
    assert_equal (1..11).to_a, C.ids(practice: false)
    assert_equal (1..13).to_a, C.ids(practice: true)
    assert_equal (1..11).to_a + [ 14, 15 ], C.ids(practice: false, bilingual: true)
    assert_equal (1..15).to_a, C.ids(practice: true, bilingual: true)
    assert_equal C::POINTS.first(11).each_with_index.map { |t, i| { id: i + 1, point: t } }, C.all
    both = C.all(practice: true, bilingual: true)
    assert_equal C::TRANSLATION_POINTS, both.last(2).map { |p| p[:point] }
    assert_equal C::ALL_POINTS[13], C.all(practice: false, bilingual: true).last(2).first[:point], "the id still reads from ALL_POINTS"
    assert_match(/Italian translation/, C::ALL_POINTS[13])
  end

  test "a lesson/2 review has 11 points, 13 for a bilingual lesson, a lesson/1 review keeps its 8" do
    revision = ->(body) { Struct.new(:body).new(body) }
    assert_equal 8, Review::LessonChecklist.for(revision.call({ "schema" => "banco.lesson/1" })).size
    assert_equal 11, Review::LessonChecklist.for(revision.call({ "schema" => "banco.lesson/2" })).size
    bilingual = Review::LessonChecklist.for(revision.call({ "schema" => "banco.lesson/2", "bilingual" => true }))
    assert_equal (1..13).to_a, bilingual.map { |p| p[:id] }
    assert_equal Review::Checklist::TRANSLATION_POINTS, bilingual.last(2).map { |p| p[:text] }
    assert_equal 8, Review::LessonChecklist.for(revision.call({ "schema" => "banco.lesson/1", "bilingual" => true })).size
  end

  test "the count of a bilingual lesson's checklist is the same in the code, the schema and the brief" do
    revision = Struct.new(:body).new({ "schema" => "banco.lesson/2", "bilingual" => true })
    count = Review::LessonChecklist.for(revision).size
    schema = Banco::Schemas.read("lesson_review")
    assert_equal count, schema.dig("properties", "checklist", "maxItems"), "the schema allows up to the bilingual count (Ruby tells the exact one)"
    assert_equal 13, count
    brief = Rails.root.join("briefs/lesson-review.md").read
    assert_match(/has \*\*#{count} points\*\*/, brief)
    assert_match(/12\. The Italian translation/, brief)
    assert_match(/13\. The target-language text/, brief)
  end

  def review_doc(ids)
    { "schema" => "banco.review/1", "schema_version" => 1, "revision" => "1", "findings" => [],
      "checklist" => ids.map { |id| { "id" => id, "result" => "pass", "evidence" => "Read the stem and options of instances 1 and 2, point #{id}." } } }
  end

  test "Intake wants the ids of the item: 11, 13, 13 with 14 and 15, or 15; the schema accepts each" do
    practice = golden
    bilingual_practice = Review::ItemText.new(revision_of(practice, practice["instances"].first))
    assert_empty Review::Intake.call(review_doc((1..15).to_a), bilingual_practice).map(&:code)
    assert_equal [ "E-REVIEW-CHECKLIST" ], Review::Intake.call(review_doc((1..13).to_a), bilingual_practice).map(&:code)
    assert_equal [ "E-REVIEW-CHECKLIST" ], Review::Intake.call(review_doc((1..11).to_a + [ 14, 15 ]), bilingual_practice).map(&:code)

    plain = Review::ItemText.new(revision_of(item_body("short-answer"), { "display" => { "stem_it" => "x" }, "answer" => "1" }))
    assert_empty Review::Intake.call(review_doc((1..11).to_a), plain).map(&:code)
    assert_equal [ "E-REVIEW-CHECKLIST" ], Review::Intake.call(review_doc((1..11).to_a + [ 14, 15 ]), plain).map(&:code)
    # the schema now allows up to 15 points; the exact count of a legacy (not bilingual) item is Intake's
    [ (1..12).to_a, (1..13).to_a, (1..14).to_a, (1..15).to_a ].each do |ids|
      assert_equal [ "E-REVIEW-CHECKLIST" ], Review::Intake.call(review_doc(ids), plain).map(&:code), "#{ids.size} points on a legacy item"
    end

    other = item_body("short-answer").merge("bilingual" => true, "subject" => "english")
    non_practice = Review::ItemText.new(revision_of(other, { "display" => { "stem_it" => "x" }, "answer" => "1" }))
    assert_empty Review::Intake.call(review_doc((1..11).to_a + [ 14, 15 ]), non_practice).map(&:code)
    wrong = Review::Intake.call(review_doc((1..13).to_a), non_practice)
    assert_equal [ "E-REVIEW-CHECKLIST" ], wrong.map(&:code), "12 and 13 are the practice points, a translation review keeps its own ids"
  end
end
