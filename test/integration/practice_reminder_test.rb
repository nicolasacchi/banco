require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/practice_text_world"

# D-358 over the real endpoints: «Ricorda: …» above an exercise that declares a typical error the student made lately in the skill. It is the item's own
# message for the code (else the skill graph's description), it is not a hint, it never states the answer and it is recorded as an app event.
class PracticeReminderTest < ActionDispatch::IntegrationTest
  include MultiUser
  include PracticeTextWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  PREVIEW = "/teacher/preview".freeze
  SIBLING = "rem-sibling".freeze      # declares does_eat, with a message of its own
  OTHER = "rem-other".freeze          # declares another code only
  LEAKY = "rem-leaky".freeze          # declares does_eat, but its message states the key
  GRAPH_A = "rem-graph-a".freeze      # declares sign_error with no message: the skill graph describes it
  GRAPH_B = "rem-graph-b".freeze
  SIBLING_MESSAGE = "Con sisters si usa don't, non doesn't.".freeze
  GRAPH_MESSAGE = "Sposta il termine senza cambiargli il segno.".freeze # the graph of the test world, for math.linear-equation-integer

  setup do
    build_text_world
    pins = [ @sentence, @word,
             reminder_item(SIBLING, stem: "Negativa: My sisters ___ tea.", answer: "don't drink", code: "does_eat", value: "doesn't drink", message: SIBLING_MESSAGE),
             reminder_item(OTHER, stem: "Negativa: My uncles ___ fish.", answer: "don't cook", code: "other_code", value: "doesn't cook", message: "Altro."),
             reminder_item(LEAKY, stem: "Negativa: My pals ___ rice.", answer: "don't want", code: "does_eat", value: "doesn't want", message: "La risposta è don't want."),
             reminder_item(GRAPH_A, stem: "Negativa: My aunts ___ jam.", answer: "don't sell", code: "sign_error", value: "doesn't sell", message: nil),
             reminder_item(GRAPH_B, stem: "Negativa: My nieces ___ ham.", answer: "don't buy", code: "sign_error", value: "doesn't buy", message: nil) ]
    approve_topic!(make_topic(@lesson_revision, { SKILL => pins }, course: @course))
  end

  # A text item that declares one typical error: in its instances' error values and, with a message, in its catalogue.
  def reminder_item(key, stem:, answer:, code:, value:, message:)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    catalogue = message ? [ { code: code, message_it: message } ] : []
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: "normalized_text", level: 1,
             expected_seconds: 60, hints_it: [ "Pensa al plurale." ], error_catalogue: catalogue }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    6.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: stem), answer_json: JSON.generate(answer),
                           errors_json: JSON.generate([ { code: code, value: value } ]), hints_json: JSON.generate([ "Pensa al plurale." ]),
                           solution_json: JSON.generate(steps: [ { text_it: "Passo." } ], final: answer), fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  def post_json(headers, path, body = {}, root: "")
    on(:web, "#{root}/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(headers, key, root: "") = post_json(headers, "#{root}/practice/serves", { topic: TOPIC, skill: SKILL, item: key }, root: root)

  def answer_for(headers, serve, raw, root: "")
    post_json(headers, "#{root}/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: raw, source: "text" }, root: root)
  end

  def reminders = AppEvent.where(kind: "practice_reminder_shown").order(:id).map { |e| JSON.parse(e.payload_json) }

  test "a typical error made lately, and the next exercise declares it: «Ricorda» carries the item's own message, and the try is not aided" do
    first = serve_for(OFFICIAL, SENTENCE)
    assert_nil first["reminder_it"], "nothing is known about this student yet"
    assert_equal "typical_error", answer_for(OFFICIAL, first, "doesn't eat")["outcome"]

    serve = serve_for(OFFICIAL, SIBLING)
    assert_equal "item", serve["type"]
    assert_equal SIBLING_MESSAGE, serve["reminder_it"]
    assert_equal [ [], 1 ], [ serve["hints"]["shown"], serve["hints"]["total"] ], "the reminder is not one of the hints: none shown, the item's own count"

    right = answer_for(OFFICIAL, serve, "don't drink")
    assert_equal [ "graded", "correct" ], right.values_at("status", "outcome")
    attempt = PracticeAttempt.find(right["attempt_id"])
    assert_equal [ false, 0 ], [ attempt.aided, attempt.hints_before ]
    assert_empty PracticeEvent.where(practice_serve_id: serve["serve_id"], kind: "hint_shown")
    assert_equal "practice/6", PracticeServe.find(serve["serve_id"]).rules_version
  end

  test "an item that does not declare the code shows nothing; nor does a student with no typical error" do
    first = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, first, "doesn't eat")
    assert_nil serve_for(OFFICIAL, OTHER)["reminder_it"], "this item does not declare does_eat"
    assert_nil serve_for(OFFICIAL, WORD)["reminder_it"]

    # a wrong answer that is no declared error is not a typical error
    other = serve_for(TRIAL, WORD)
    assert_equal "unrecognised", answer_for(TRIAL, other, "zzzz")["outcome"]
    assert_nil serve_for(TRIAL, SIBLING)["reminder_it"]
    assert_empty reminders
  end

  test "the typical error has to be among the last ten tries of the skill" do
    first = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, first, "doesn't eat")
    assert_equal SIBLING_MESSAGE, serve_for(OFFICIAL, SIBLING)["reminder_it"]

    5.times do |i|
      serve = serve_for(OFFICIAL, WORD)
      assert_equal "unrecognised", answer_for(OFFICIAL, serve, "zz#{i}a")["outcome"]
      assert_equal "unrecognised", answer_for(OFFICIAL, serve, "zz#{i}b")["outcome"]
    end
    assert_equal 11, PracticeAttempt.where(student: @official).count
    assert_nil serve_for(OFFICIAL, SIBLING)["reminder_it"], "ten later tries push the error out of the window"
  end

  test "the most recent typical error that the item declares wins; an error the item does not declare is skipped" do
    a = serve_for(OFFICIAL, GRAPH_A)
    assert_equal "typical_error", answer_for(OFFICIAL, a, "doesn't sell")["outcome"]
    s = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, s, "doesn't eat")
    assert_equal SIBLING_MESSAGE, serve_for(OFFICIAL, SIBLING)["reminder_it"], "does_eat is the most recent"
    assert_equal GRAPH_MESSAGE, serve_for(OFFICIAL, GRAPH_B)["reminder_it"], "sign_error is the one GRAPH_B declares"
  end

  test "an item with no message of its own gets the skill graph's description of the error" do
    a = serve_for(OFFICIAL, GRAPH_A)
    assert_equal "typical_error", answer_for(OFFICIAL, a, "doesn't sell")["outcome"]
    assert_equal GRAPH_MESSAGE, serve_for(OFFICIAL, GRAPH_B)["reminder_it"]
    assert_equal "graph", reminders.last["source"]
  end

  test "the reminder never contains the answer, and the page gets nothing else about the item's errors" do
    first = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, first, "doesn't eat")

    leaky = serve_for(OFFICIAL, LEAKY)
    assert_nil leaky["reminder_it"], "a message that states the key is not shown before the answer"
    assert_empty reminders.select { |r| r["serve_id"] == leaky["serve_id"] }

    serve = serve_for(OFFICIAL, SIBLING)
    assert_equal SIBLING_MESSAGE, serve["reminder_it"]
    [ "don't drink", "doesn't drink", "does_eat", "doesn't eat" ].each { |secret| refute_includes response.body, secret }
    refute_match(/hai sbagliato/i, serve["reminder_it"])
    assert_equal %w[actions draft exercise hints item rating reason reason_it reminder_it serve_id skill status type next_try_number].sort, serve.keys.sort
  end

  test "it is recorded once per serve and code, with the code, however many times the page is opened" do
    first = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, first, "doesn't eat")
    assert_empty reminders

    serve = serve_for(OFFICIAL, SIBLING)
    again = serve_for(OFFICIAL, SIBLING)
    assert_equal serve["serve_id"], again["serve_id"], "the open serve is resumed"
    assert_equal SIBLING_MESSAGE, again["reminder_it"]
    assert_equal [ { "serve_id" => serve["serve_id"], "code" => "does_eat", "source" => "item" } ], reminders
    assert_equal [ @official.id ], AppEvent.where(kind: "practice_reminder_shown").pluck(:student_id)
    assert_equal 0, PracticeEvent.where(practice_serve_id: serve["serve_id"]).count, "no serve event: the reminder is not a hint nor a solution"
  end

  test "the teacher's detail of a try says the reminder was shown" do
    first = serve_for(OFFICIAL, SENTENCE)
    answer_for(OFFICIAL, first, "doesn't eat")
    serve = serve_for(OFFICIAL, SIBLING)
    right = answer_for(OFFICIAL, serve, "don't drink")

    detail = Practice::AttemptLog.new(@official).detail(right["attempt_id"])
    shown = detail[:served][:reminders]
    assert_equal [ [ "does_eat", "item" ] ], shown.map { |r| r.values_at(:code, :source) }
    assert_nil Practice::AttemptLog.new(@official).detail(PracticeAttempt.find_by(practice_serve_id: first["serve_id"]).id)[:served][:reminders]
  end

  test "a trial student and the teacher's preview have their own tries: the preview is not told about the official student's errors" do
    answer_for(OFFICIAL, serve_for(OFFICIAL, SENTENCE), "doesn't eat")
    assert_nil serve_for(TEACHER, SIBLING, root: PREVIEW)["reminder_it"]

    answer_for(TEACHER, serve_for(TEACHER, SENTENCE, root: PREVIEW), "doesn't eat", root: PREVIEW)
    preview = serve_for(TEACHER, SIBLING, root: PREVIEW)
    assert_equal SIBLING_MESSAGE, preview["reminder_it"]
    assert_equal [ Student.where(kind: "preview").order(:id).last.id ], AppEvent.where(kind: "practice_reminder_shown").pluck(:student_id)

    answer_for(TRIAL, serve_for(TRIAL, SENTENCE), "doesn't eat")
    assert_equal SIBLING_MESSAGE, serve_for(TRIAL, SIBLING)["reminder_it"]
    assert_equal [ @trial.id ], AppEvent.where(kind: "practice_reminder_shown").order(:id).pluck(:student_id).last(1)
  end
end
