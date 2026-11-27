require "test_helper"
require_relative "../support/public_api_tokens"
require_relative "../support/contract_examples"

# The read-only grade commands of the reviewer and the solver (D-402 round 8): `banco item grade` and `banco lesson grade`. The answer goes through the
# student's own grader and comes back with the verdict, what it matched, the error code and the message; nothing is stored.
class GradeApiTest < ActionDispatch::IntegrationTest
  include PublicApiTokens

  setup do
    @english = Subject.create!(key: "english", name_it: "Inglese", position: 1)
    @spanish = Subject.create!(key: "spanish", name_it: "Spagnolo", position: 2)
    @agent = issue_token("agent_claude")
    @en_item = item_revision(@english, "grade-en-1", "english.be-have", [
      { stem: "My friend ___ of deep water.", answer: "is scared", errors: [ { code: "wrong_tense", value: "was scared" } ] },
      { stem: "She ___ a cold.", answer: "has got", errors: [ { code: "wrong_aux", value: "is got" } ] }
    ], catalogue: [ { code: "wrong_tense", message_en: "Use the present: it is now.", message_it: "Usa il presente: è adesso." }, { code: "wrong_aux", message_en: "Not «is got».", message_it: "Non «is got»." } ])
    @es_item = item_revision(@spanish, "grade-es-1", "spanish.ser-estar", [ { stem: "Mi hermana ___ cansada.", answer: "está", errors: [ { code: "es_ser", value: "es" } ] } ], catalogue: [])
    @en_lesson = lesson_revision(@english, "ripasso.english.grade", "english", [ { "n" => 1, "type" => "check", "component" => "normalized_text", "prompt_it" => "My friend ___ of deep water.", "answer" => "is scared",
                                                                                        "errors" => [ { "answer" => "was scared", "code" => "wrong_tense", "message_it" => "Usa il presente." } ] },
                                                                                   { "n" => 2, "type" => "try", "exercises" => [ { "n" => 1, "check" => { "component" => "normalized_text", "prompt_it" => "She ___ a cold.", "answer" => "has got", "errors" => [ { "answer" => "is got", "code" => "wrong_aux", "message_it" => "No." } ] } } ] } ])
    @es_lesson = lesson_revision(@spanish, "ripasso.spanish.grade", "spanish", [ { "n" => 1, "type" => "check", "component" => "normalized_text", "prompt_it" => "Mi hermana ___ cansada.", "answer" => "está" } ])
  end

  def item_revision(subject, key, skill, instances, catalogue:)
    item = Item.create!(subject: subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: subject.key, skill: skill, component: "normalized_text", level: 1, expected_seconds: 60,
             bilingual: true, prompt: { stem_en: "Complete.", stem_it: "Completa." }, error_catalogue: catalogue }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    instances.each_with_index do |inst, i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_en: inst[:stem], stem_it: "Completa."), answer_json: JSON.generate(inst[:answer]),
                           errors_json: JSON.generate(inst[:errors]), fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  def lesson_revision(subject, key, subject_key, blocks)
    lesson = Lesson.create!(subject: subject, key: key, kind: "ripasso")
    body = { schema: "banco.lesson/2", key: key, subject: subject_key, cards: [ { n: 1, blocks: blocks } ] }
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: "1" * 64, body_json: JSON.generate(body), rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  def grade_items(revision, answers, token: @agent) = api_as(token, "/api/v1/item-revisions/#{revision.id}/grade", method: :post, body: { answers: answers })

  def grade_lesson(revision, answers, token: @agent) = api_as(token, "/api/v1/lesson-revisions/#{revision.id}/grade", method: :post, body: { answers: answers })

  def ledger_counts = [ PracticeAttempt.count, PracticeServe.count, LessonEvent.count, AppEvent.count, Attempt.count ]

  # ---- items ----

  test "item grade: 's scared is right for «is scared» and says it matched the key; the whole sentence and the error value are told apart" do
    before = ledger_counts
    grade_items(@en_item, [ { instance: 1, answer: "'s scared" }, { instance: 1, answer: "is scared" }, { instance: 1, answer: "was scared" }, { instance: 1, answer: "is afraid" } ])
    assert_response :ok, json.inspect
    record_example "item grade", "contraction"
    one, two, err, wrong = json["results"]
    assert_equal [ "correct", "key", "is scared" ], [ one["verdict"], one["matched"]["kind"], one["matched"]["value"] ]
    assert_equal "correct", two["verdict"]
    assert_equal "correct", one["outcome"]
    assert_equal [ "typical_error", "wrong_tense", "error", "was scared" ], [ err["verdict"], err["error_code"], err["matched"]["kind"], err["matched"]["value"] ]
    assert_equal "Use the present: it is now.", err["message_en"]
    assert_equal "Usa il presente: è adesso.", err["message_it"]
    assert_equal "wrong", wrong["verdict"]
    assert_nil wrong["matched"]
    assert_equal true, json["read_only"]
    assert_equal before, ledger_counts, "nothing is stored"
  end

  test "item grade: 's got is right for the key «has got» though «is got» is a declared error, and the error written out is still the error" do
    grade_items(@en_item, [ { instance: 2, answer: "'s got" }, { instance: 2, answer: "She's got a cold." }, { instance: 2, answer: "is got" } ])
    assert_response :ok, json.inspect
    one, full, err = json["results"]
    assert_equal [ "correct", "has got" ], [ one["verdict"], one["matched"]["value"] ]
    assert_equal [ "correct", "full_sentence" ], [ full["verdict"], full["observation"] ]
    assert_equal [ "typical_error", "wrong_aux" ], [ err["verdict"], err["error_code"] ]
  end

  test "item grade: a Spanish answer without its accent is a slip of the key, with its code and the entry it is a slip of" do
    grade_items(@es_item, [ { instance: 1, answer: "esta" }, { instance: 1, answer: "está" }, { instance: 1, answer: "estás" } ])
    assert_response :ok, json.inspect
    record_example "item grade", "accent"
    slip, right, wrong = json["results"]
    assert_equal [ "typical_error", "es_accents", "slip", "está" ], [ slip["verdict"], slip["error_code"], slip["matched"]["kind"], slip["matched"]["value"] ]
    assert_equal [ "correct", "key" ], [ right["verdict"], right["matched"]["kind"] ]
    assert_equal "wrong", wrong["verdict"]
  end

  test "item grade: an answer that cannot be read says why and is not a try; an error value is told with its code" do
    grade_items(@es_item, [ { instance: 1, answer: "   " }, { instance: 1, answer: "es" } ])
    assert_response :ok, json.inspect
    blank, err = json["results"]
    assert_equal [ "invalid", "empty" ], [ blank["verdict"], blank["invalid_code"] ]
    assert_predicate blank["message_it"], :present?
    assert_equal [ "typical_error", "es_ser", "es" ], [ err["verdict"], err["error_code"], err["matched"]["value"] ]
  end

  test "item grade: an unknown instance or revision is a 404 with a code; a badly shaped body is E-FILES" do
    grade_items(@en_item, [ { instance: 1, answer: "is scared" }, { instance: 9, answer: "x" } ])
    assert_response :not_found
    assert_equal [ "E-NOT-FOUND", "answers/1/instance" ], [ json["code"], json["field"] ]
    record_example "item grade", "unknown-instance"
    api_as(@agent, "/api/v1/item-revisions/999999/grade", method: :post, body: { answers: [ { instance: 1, answer: "x" } ] })
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    grade_items(@en_item, [])
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    api_as(@agent, "/api/v1/item-revisions/#{@en_item.id}/grade", method: :post, body: { answers: [ { instance: "1", answer: "x" } ] })
    assert_response :unprocessable_entity
  end

  test "item grade: every token role may ask, a missing token is 401, and nothing is stored" do
    before = ledger_counts
    [ @agent, issue_token("bot_read"), issue_token("teacher"), issue_token("agent_omp"), issue_token("ci") ].each do |token|
      grade_items(@en_item, [ { instance: 1, answer: "'s scared" } ], token: token)
      assert_response :ok, json.inspect
      assert_equal "correct", json["results"].first["verdict"]
    end
    grade_items(@en_item, [ { instance: 1, answer: "is scared" } ], token: nil)
    assert_response :unauthorized
    assert_equal before, ledger_counts
  end

  test "item grade: an ordering shows its key and an accepted alternative order as the entry that matched" do
    item = Item.create!(subject: @english, key: "grade-order-1", kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "english", skill: "english.word-order", component: "ordering", level: 1, expected_seconds: 60 }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    elements = [ "In 1973", "Picasso", "died" ].each_with_index.map { |t, i| { id: "e#{i + 1}", text: t } }
    ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON.generate(stem_it: "Order the tiles.", elements: elements), answer_json: JSON.generate(%w[e1 e2 e3]),
                         errors_json: JSON.generate([ { code: "en_order", value: %w[e3 e2 e1] } ]), accept_json: JSON.generate([ %w[e2 e3 e1] ]), fingerprint: Digest::SHA256.hexdigest("order"))
    grade_items(revision, [ { instance: 1, answer: %w[e1 e2 e3] }, { instance: 1, answer: %w[e2 e3 e1] }, { instance: 1, answer: %w[e3 e2 e1] }, { instance: 1, answer: %w[e1 e3 e2] } ])
    assert_response :ok, json.inspect
    key, alt, err, wrong = json["results"]
    assert_equal [ "correct", "key" ], [ key["verdict"], key["matched"]["kind"] ]
    assert_equal [ "correct", "accept", %w[e2 e3 e1] ], [ alt["verdict"], alt["matched"]["kind"], alt["matched"]["value"] ]
    assert_equal [ "typical_error", "en_order" ], [ err["verdict"], err["error_code"] ]
    assert_equal "wrong", wrong["verdict"]
  end

  # ---- lessons ----

  test "lesson grade: 's scared is right for «is scared»; the error answer is told with its code and its message; a Prova tu check has its own id" do
    before = ledger_counts
    grade_lesson(@en_lesson, [ { check: "1.1", answer: "'s scared" }, { check: "1.1", answer: "was scared" }, { check: "1.2.ex1", answer: "'s got" }, { check: "1.2.ex1", answer: "is got" } ])
    assert_response :ok, json.inspect
    record_example "lesson grade", "contraction"
    one, err, ex, ex_err = json["results"]
    assert_equal [ "right", "key", "is scared" ], [ one["verdict"], one["matched"]["kind"], one["matched"]["value"] ]
    assert_equal [ "wrong", "wrong_tense", "error", "was scared" ], [ err["verdict"], err["error_code"], err["matched"]["kind"], err["matched"]["value"] ]
    assert_equal "Usa il presente.", err["message"]["message_it"]
    assert_equal [ "right", "has got" ], [ ex["verdict"], ex["matched"]["value"] ], "key has got, error is got: 's got is right"
    assert_equal "wrong_aux", ex_err["error_code"]
    assert_equal before, ledger_counts, "no lesson_events row"
  end

  test "lesson grade: a Spanish answer without its accent is a slip, and the accept entry that matched is named" do
    grade_lesson(@es_lesson, [ { check: "1.1", answer: "esta" }, { check: "1.1", answer: "está" } ])
    assert_response :ok, json.inspect
    slip, right = json["results"]
    assert_equal [ "wrong", "es_accents", "slip" ], [ slip["verdict"], slip["error_code"], slip["matched"]["kind"] ]
    assert_equal "right", right["verdict"]
    with_accept = lesson_revision(@spanish, "ripasso.spanish.accept", "spanish", [ { "n" => 1, "type" => "check", "component" => "normalized_text", "prompt_it" => "Mi hermana ___ cansada.", "answer" => "está", "accept" => [ "esta cansada" ] } ])
    grade_lesson(with_accept, [ { check: "1.1", answer: "esta cansada" } ])
    assert_equal [ "right", "accept", "esta cansada" ], [ json["results"][0]["verdict"], json["results"][0]["matched"]["kind"], json["results"][0]["matched"]["value"] ]
  end

  test "lesson grade: an unknown check is a 404 with a code that lists the checks; a lesson/1 or unknown revision is a 404; every role may ask" do
    grade_lesson(@en_lesson, [ { check: "7.7", answer: "x" } ])
    assert_response :not_found
    assert_equal [ "E-NOT-FOUND", "answers/0/check", [ "1.1", "1.2.ex1" ] ], [ json["code"], json["field"], json["checks"] ]
    record_example "lesson grade", "unknown-check"
    old = LessonRevision.create!(lesson: @en_lesson.lesson, seq: 2, source_md: "---\n", source_sha256: "2" * 64, body_json: JSON.generate(schema: "banco.lesson/1"), rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
    grade_lesson(old, [ { check: "1.1", answer: "x" } ])
    assert_response :not_found
    api_as(@agent, "/api/v1/lesson-revisions/999999/grade", method: :post, body: { answers: [ { check: "1.1", answer: "x" } ] })
    assert_response :not_found
    grade_lesson(@en_lesson, [ { check: "1.1", answer: "is scared" } ], token: issue_token("teacher"))
    assert_response :ok
    grade_lesson(@en_lesson, [ { check: "1.1", answer: "is scared" } ], token: issue_token("bot_read"))
    assert_response :ok
    grade_lesson(@en_lesson, [])
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
  end
end
