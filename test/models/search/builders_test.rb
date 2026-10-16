require "test_helper"
require_relative "../../support/search_world"
require_relative "../../support/lesson2_fixtures"

# What the builders put into the index: lesson/2 cards from the student's whitelist only, glossary terms with their card, items
# and instances without answers, references by article, answers for the teacher's kind alone.
class SearchBuildersTest < ActiveSupport::TestCase
  include SearchWorld

  HIDDEN = { "explain_it" => "zzspiegazz", "solution_it" => "zzsoluzz", "final_it" => "zzfinalezz" }.freeze

  # The fixture lesson/2 with a sentinel put in front of every explanation, solution and final answer, a glossary term in the
  # second card.
  def lesson2_body
    json = Lesson2Fixtures.check(Lesson2Fixtures.read("base.md")).body.to_json
    HIDDEN.each { |key, word| json = json.gsub("\"#{key}\":\"", "\"#{key}\":\"#{word} ") }
    body = JSON.parse(json).merge("key" => TOPIC, "glossary" => [ { "term_it" => "Piatto", "def_it" => "Il **recipiente** della bilancia.", "example_it" => "Un piatto pieno." } ])
    body["cards"][1]["blocks"].first["text_it"] = "#{body['cards'][1]['blocks'].first['text_it']} Guarda il [[g:piatto]]."
    body
  end

  setup do
    build_search_world
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "5" * 64, rules_version: Validation::Rules.version.to_s,
                                              warnings_json: "[]", body_json: JSON.generate(lesson2_body))
    @cards = Search::Builders::Lessons.call
  end

  def docs(kind) = @cards.select { |d| d.kind == kind && d.revision_id == @lesson_revision.id }

  test "a lesson/2 gives a cover and one document per card, anchored where the lesson page scrolls to" do
    assert_equal [ nil ] + (1..7).map { |n| "scheda-#{n}" }, docs("lesson_card").map(&:anchor)
    assert_equal "Un'equazione è una bilancia", docs("lesson_card")[1].title
    assert(docs("lesson_card").all? { |d| d.topic_key == TOPIC && d.subject == "math" && d.audience == "student" })
  end

  test "the explanations, solutions and final answers of a lesson are in no document" do
    text = @cards.map { |d| "#{d.title} #{d.body}" }.join(" ")
    HIDDEN.each_value do |word|
      assert_includes @lesson_revision.body_json, word, "the stored body has the sentinel"
      assert_not_includes text, word
    end
    assert_includes text, "bilancia"
  end

  test "a glossary term holds its definition and the card that marks it" do
    term = docs("glossary_term").first
    assert_equal "Piatto", term.title
    assert_equal "Il recipiente della bilancia. Un piatto pieno.", term.body.gsub(/\s*\n\s*/, " ").strip
    assert_equal "scheda-2", term.anchor
  end

  test "items: instances of a practice item show the stem, an entry-test instance is for the staff, nothing holds an answer" do
    docs = Search::Builders::Items.call
    practice = docs.select { |d| d.kind == "practice_item" && d.key == "leaky-item-1" }
    assert_equal 2, practice.size
    assert_equal "student", practice.first.audience
    assert_includes practice.first.body, "radice quadrata"
    diagnosis = docs.select { |d| d.kind == "item_instance" }
    assert_predicate diagnosis, :any?
    assert(diagnosis.all? { |d| d.audience == "staff" })
    text = docs.map { |d| "#{d.title} #{d.body}" }.join(" ")
    [ LEAKS[:key], LEAKS[:solution] ].each { |word| assert_not_includes text, word }
    item = docs.find { |d| d.kind == "item" && d.key == "leaky-item-1" }
    assert_includes item.body, LEAKS[:hint], "the staff's item document holds the hints"
    assert_equal "staff", item.audience
  end

  test "every kind has one audience, fixed by the kind" do
    assert_equal Search::Doc::KINDS.sort, (Search::Doc::STUDENT_KINDS + Search::Doc::STAFF_KINDS + Search::Doc::TEACHER_KINDS).sort
    assert_equal "teacher", Search::Doc.build(kind: "student_answer", key: "k", title: "t", body: "b").audience
    assert_equal "student", Search::Doc.build(kind: "practice_item", key: "k", title: "t", body: "b").audience
    assert_equal "staff", Search::Doc.build(kind: "finding", key: "k", title: "t", body: "b").audience
    assert_raises(ArgumentError) { Search::Doc.build(kind: "other", key: "k", title: "t", body: "b") }
  end

  test "a reference text is split by article, and by paragraphs when it has none" do
    ReferenceText.create!(key: "codice-test", title: "Codice", source_url: "https://example.org/c", sha256: "8" * 64,
                          body: "Art. 5\nPrimo testo.\n\nArt. 6 bis\nSecondo testo.\n")
    ReferenceText.create!(key: "poesia-test", title: "Poesia", source_url: "https://example.org/p", sha256: "7" * 64, body: "Un verso.\n\nUn altro verso.\n")
    docs = Search::Builders::References.call.select { |d| %w[codice-test poesia-test].include?(d.key) }
    assert_equal [ "art-5", "art-6", "p1" ], docs.map(&:anchor)
    assert_equal "Codice · Art. 5", docs.first.title
  end

  test "answers are teacher documents with the student, the item and the time" do
    add_answers!(@official, ANSWER_WORD, refused: REFUSED_WORD)
    add_diagnosis_answer!(@official, DIAGNOSIS_ANSWER_WORD)
    answers = Search::Builders::Answers.call
    assert_equal [ DIAGNOSIS_ANSWER_WORD, ANSWER_WORD, REFUSED_WORD ].sort, answers.map(&:body).sort
    assert(answers.all? { |d| d.kind == "student_answer" && d.audience == "teacher" && d.student_key == "student" && d.occurred_at })
    assert_equal "refused", answers.find { |d| d.body == REFUSED_WORD }.status
  end

  test "a preview student's attempts are not answers" do
    preview = Student.create!(key: "preview", kind: "preview")
    instance = @pinned_diagnosis.instances.first
    blueprint = BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, seq: 1, body_json: JSON.generate(subject: "math", entries: [ { skill: SKILL, items: [] } ]))
    run = DiagnosisRun.create!(student: preview, subject: @subject, blueprint_revision: blueprint, sequence: 1, seed_salt: "s", rules_version: "v1", engine_version: "e1")
    event = DiagnosisEvent.create!(diagnosis_run: run, seq: 1, kind: "item_served", payload_json: "{}", at: Time.current)
    ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: SKILL, shown_order_json: "[]", id_map_json: "{}")
    Attempt.create!(student: preview, context: "teacher_preview", served_event: event, client_attempt_id: "pv-1", item_instance: instance, raw: "zzanteprimazz", source: "text", answered_at: Time.current)
    assert_empty Search::Builders::Answers.call.select { |d| d.body.include?("zzanteprimazz") }
  end
end
