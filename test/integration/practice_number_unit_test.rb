require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-386 over the real endpoint: a number written with a unit word the exercise itself uses («2 minuti») is a right try with a note;
# a word it does not use («2 metri») is refused with a message that names it, no try is recorded, and the exercise stays open.
class PracticeNumberUnitTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  NUMBER = "number-minutes".freeze
  STEM = "Il discorso dura quanti minuti?".freeze
  FORMAT = "Scrivi il numero, senza l'unità.".freeze

  setup do
    build_student_world
    @number = make_number_item(NUMBER)
    @number_topic = make_topic(@lesson_revision, { SKILL => [ @number ] }, course: @course)
    approve_topic!(@number_topic)
  end

  def make_number_item(key, answer: 2, instances: 6)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: "number", level: 1,
             expected_seconds: 60, hints_it: [ "Conta i secondi." ], answer_format_it: FORMAT, error_catalogue: [] }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    instances.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: STEM), answer_json: JSON.generate(answer),
                           errors_json: "[]", hints_json: JSON.generate([ "Conta i secondi." ]),
                           solution_json: JSON.generate(steps: [ { text_it: "Divido per 60." } ], final: "2 minuti"),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  def post_json(path, body = {})
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: OFFICIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def serve_number = post_json("/practice/serves", { topic: TOPIC, skill: SKILL, item: NUMBER })

  def answer(serve, raw, id: SecureRandom.uuid)
    post_json("/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: id, raw: raw, source: "text" })
  end

  def tries(serve) = PracticeAttempt.where(practice_serve_id: serve["serve_id"]).count

  test "«2 minuti» on an exercise that says minuti: right on the number, with the note, and the same note on a repeat" do
    serve = serve_number
    reply = answer(serve, "2 minuti", id: "unit-client-1")
    assert_equal [ "graded", "correct", "Corretto." ], reply.values_at("status", "outcome", "message_it")
    assert_equal "Il numero è giusto. La prossima volta scrivi solo il numero, senza «minuti».", reply["note_it"]
    attempt = PracticeAttempt.find(reply["attempt_id"])
    assert_equal [ "2 minuti", 1, "correct" ], [ attempt.raw, attempt.try_number, attempt.latest_grading.verdict ]
    assert_equal "2", attempt.latest_grading.normalized
    assert_equal %w[next back], reply["actions"]

    again = answer(serve, "2 minuti", id: "unit-client-1")
    assert_equal reply["note_it"], again["note_it"]
    assert_equal 1, tries(serve)
  end

  test "the bare number has no note" do
    serve = serve_number
    reply = answer(serve, "2")
    assert_equal [ "graded", "correct" ], reply.values_at("status", "outcome")
    assert_nil reply["note_it"]
  end

  test "«2 metri» is refused with the word named: no try, the exercise stays open, and the right number still goes through" do
    serve = serve_number
    refused = answer(serve, "2 metri")
    assert_equal [ "invalid", "Scrivi solo il numero, senza «metri»." ], refused.values_at("status", "message_it")
    assert_equal 200, response.status
    assert_equal 0, tries(serve)
    event = AppEvent.where(kind: "practice_invalid_input").last
    assert_equal [ "extra_word", "2 metri" ], JSON.parse(event.payload_json).values_at("code", "text")

    second = answer(serve, "2 chilometri")
    assert_equal [ "invalid", "Scrivi solo il numero, senza «chilometri»." ], second.values_at("status", "message_it")
    assert_equal 0, tries(serve)

    right = answer(serve, "2")
    assert_equal [ "graded", "correct" ], right.values_at("status", "outcome")
    assert_equal 1, tries(serve)
  end

  test "a wrong number with the exercise's own word is a wrong try, not a refusal" do
    serve = serve_number
    reply = answer(serve, "3 minuti")
    assert_equal "graded", reply["status"]
    assert_equal "unrecognised", reply["outcome"]
    assert_nil reply["note_it"]
    assert_equal 1, tries(serve)
  end
end
