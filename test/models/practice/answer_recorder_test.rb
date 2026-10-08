require "test_helper"
require_relative "../../support/practice_world"

# The practice recorder (A8.4, A9.3): grading outside the transaction, the idempotent client id, a
# concurrent duplicate, 503, invalid input, 409 on a closed serve, and the body of every row.
class PracticeAnswerRecorderTest < ActiveSupport::TestCase
  include PracticeWorld

  setup { build_practice_world }

  def body(result) = result.body

  test "a correct answer: graded, solution sent, next and back" do
    c = serve!
    result = answer!(c, correct_raw(c))
    assert_equal 200, result.http
    b = body(result)
    assert_equal [ "graded", "correct", 1, "Corretto." ], [ b[:status], b[:outcome], b[:try_number], b[:message_it] ]
    assert_nil b[:note_it]
    assert_nil b[:error_code]
    assert_nil b[:hint]
    assert_equal({ steps: [ { text_it: "Passo.", math: "$x$" } ], final: "$x$" }, b[:solution])
    assert_equal %w[next back], b[:actions]
    assert_equal [ "math.linear-equation-integer", "in_study" ], [ b[:skill][:key], b[:skill][:state] ]
    assert_equal "In studio", b[:skill][:state_it]
    assert b[:skill][:changed]
    assert_equal "Corrette senza aiuto: 1 su 3, in 1 giorni su 2.", b[:skill][:why_it]
  end

  test "the rows: attempt, grading on the practice table, solution event, aided false" do
    c = serve!
    answer!(c, correct_raw(c), id: "client-0001")
    attempt = PracticeAttempt.find_by!(client_attempt_id: "client-0001")
    assert_equal [ 1, false, 0, "text", c.serve.id ], [ attempt.try_number, attempt.aided, attempt.hints_before, attempt.source, attempt.practice_serve_id ]
    assert_equal 1, attempt.gradings.size
    assert_equal [ 1, "correct", "sync" ], attempt.gradings.first.then { |g| [ g.seq, g.verdict, g.source ] }
    assert_equal [ "solution_shown" ], c.serve.events.map(&:kind)
    assert_equal({ "reason" => "after_correct" }, JSON.parse(c.serve.events.first.payload_json))
    assert_equal 0, Attempt.count
    assert_equal 0, AttemptGrading.count
  end

  test "row 2: a typical error closes the serve with the catalogue message, no solution, Prova questo offered" do
    c = serve!
    b = body(answer!(c, slip_raw(c)))
    assert_equal [ "typical_error", "slip", "Hai sbagliato un segno." ], [ b[:outcome], b[:error_code], b[:message_it] ]
    assert_nil b[:solution]
    assert_nil b[:hint]
    assert_equal %w[prova_questo show_solution back], b[:actions]
    assert_empty c.serve.events
  end

  test "row 3: a wrong answer gives the unrecognised message, the first hint (auto) and a retry" do
    c = serve!
    b = body(answer!(c, wrong_raw))
    assert_equal [ "unrecognised", "Questa risposta non corrisponde a un errore che conosco. Ecco un aiuto: riprova." ], [ b[:outcome], b[:message_it] ]
    assert_equal({ n: 1, total: 3, hint_it: "Che cosa guardi prima?" }, b[:hint])
    assert_nil b[:solution]
    assert_equal %w[retry show_solution], b[:actions]
    assert_equal({ "n" => 1, "auto" => true }, JSON.parse(c.serve.events.first.payload_json))
  end

  test "row 5: the correct second try is aided by rule and closes the serve" do
    c = serve!
    answer!(c, wrong_raw)
    b = body(answer!(c, correct_raw(c)))
    assert_equal [ "correct_aided", 2, "Corretto, con un aiuto." ], [ b[:outcome], b[:try_number], b[:message_it] ]
    assert b[:solution]
    assert_equal %w[next back], b[:actions]
    second = c.serve.attempts.order(:try_number).last
    assert_equal [ true, 1 ], [ second.aided, second.hints_before ]
  end

  test "row 6: a second wrong answer closes the serve with the solution and the second_wrong message" do
    c = serve!
    answer!(c, wrong_raw)
    b = body(answer!(c, wrong_raw))
    assert_equal [ "unrecognised", "Non è ancora giusta. Guarda la soluzione, poi prova un esercizio simile." ], [ b[:outcome], b[:message_it] ]
    assert b[:solution]
    assert_nil b[:hint]
    assert_equal %w[after_solution back], b[:actions]
  end

  test "row 6 with a typical error as the second try keeps the catalogue message and offers Prova questo" do
    c = serve!
    answer!(c, wrong_raw)
    b = body(answer!(c, slip_raw(c)))
    assert_equal [ "typical_error", "Hai sbagliato un segno." ], [ b[:outcome], b[:message_it] ]
    assert_equal %w[prova_questo after_solution back], b[:actions]
    assert b[:solution]
  end

  test "an unrecognised answer with all hints shown sends no hint" do
    c = serve!
    3.times { |n| actions.hint(serve_id: c.serve.id, n: n + 1) }
    assert_nil body(answer!(c, wrong_raw))[:hint]
  end

  test "a hint shown before makes a correct try aided" do
    c = serve!
    actions.hint(serve_id: c.serve.id, n: 1)
    b = body(answer!(c, correct_raw(c)))
    assert_equal "correct_aided", b[:outcome]
    assert_equal 1, c.serve.attempts.first.hints_before
    assert b[:skill][:changed]
  end

  test "an empty or too long answer is invalid and nothing is stored" do
    c = serve!
    assert_equal({ status: "invalid", message_it: "Scrivi una risposta prima di continuare." }, answer!(c, "   ").body)
    big = answer!(c, "7" * 20_001).body
    assert_equal "invalid", big[:status]
    assert_equal 0, PracticeAttempt.count
  end

  test "an answer the checker calls invalid is not a try: an app event, the grader's message, nothing stored" do
    c = serve!
    result = answer!(c, "3.5")
    assert_equal "invalid", result.body[:status]
    assert_equal "Per i decimali usa la virgola, per esempio 3,5.", result.body[:message_it]
    assert_equal 0, PracticeAttempt.count
    event = AppEvent.where(kind: "practice_invalid_input").last
    assert_equal({ "serve_id" => c.serve.id, "code" => "use_comma" }, JSON.parse(event.payload_json))
    assert_equal :open, Practice::Loader.status_of(c.serve.reload, now: @clock.now).state
  end

  test "Non lo so is not a practice try" do
    c = serve!
    result = answer!(c, Grading::DONT_KNOW_RAW)
    assert_equal "invalid", result.body[:status]
    assert_equal 0, PracticeAttempt.count
  end

  test "409 when the serve is closed; nothing is stored" do
    c = serve!
    answer!(c, correct_raw(c))
    result = answer!(c, correct_raw(c))
    assert_equal [ 409, { status: "closed", message_it: "Questo esercizio è chiuso: scegline un altro." } ], [ result.http, result.body ]
    assert_equal 1, PracticeAttempt.count
  end

  test "409 when the serve is abandoned (24 hours)" do
    c = serve!
    advance(24 * 3600 + 1)
    assert_equal 409, recorder.call(serve_id: c.serve.id, client_attempt_id: "late-answer-1", raw: correct_raw(c), source: "text").http
  end

  test "404 for another student's serve and an unknown serve; a malformed client id" do
    c = serve!
    other = practice_student("trial-x")
    assert_equal 404, recorder(student: other).call(serve_id: c.serve.id, client_attempt_id: "client-0002", raw: "1", source: "text").http
    assert_equal 404, recorder.call(serve_id: 0, client_attempt_id: "client-0002", raw: "1", source: "text").http
    assert_equal 404, recorder.call(serve_id: c.serve.id, client_attempt_id: "bad id", raw: "1", source: "text").http
    assert_equal 404, recorder.call(serve_id: c.serve.id, client_attempt_id: "client-0002", raw: 12, source: "text").http
    assert_equal 0, PracticeAttempt.count
  end

  test "a repeated client_attempt_id returns the stored answer and writes nothing" do
    c = serve!
    first = answer!(c, wrong_raw, id: "repeat-0001")
    rows = [ PracticeAttempt.count, PracticeEvent.count, PracticeGrading.count ]
    again = recorder.call(serve_id: c.serve.id, client_attempt_id: "repeat-0001", raw: wrong_raw, source: "text")
    assert_equal first.body, again.body
    assert_equal rows, [ PracticeAttempt.count, PracticeEvent.count, PracticeGrading.count ]
  end

  test "a repeat after later activity returns that answer as it was, with its hint and actions" do
    c = serve!
    first = answer!(c, wrong_raw, id: "repeat-0002")
    actions.hint(serve_id: c.serve.id, n: 2)
    answer!(c, correct_raw(c))
    again = recorder.call(serve_id: c.serve.id, client_attempt_id: "repeat-0002", raw: wrong_raw, source: "text")
    assert_equal first.body.except(:skill), again.body.except(:skill)
    assert_equal 1, again.body[:hint][:n]
  end

  test "the same client id on another student's serve is refused" do
    c = serve!
    answer!(c, wrong_raw, id: "taken-id-0001")
    other = practice_student("trial-y")
    oc = serve!(student: other)
    result = recorder(student: other).call(serve_id: oc.serve.id, client_attempt_id: "taken-id-0001", raw: "1", source: "text")
    assert_equal 404, result.http
  end

  test "a concurrent duplicate of the same client id returns the stored answer" do
    c = serve!
    answer!(c, wrong_raw, id: "dupe-0000001")
    # simulate the loser of the race: the row exists when the transaction inserts
    r = recorder
    original = PracticeAttempt.method(:find_by)
    calls = 0
    PracticeAttempt.define_singleton_method(:find_by) do |*args, **kw|
      calls += 1
      calls == 1 && args.first.is_a?(Hash) && args.first[:client_attempt_id] == "dupe-0000001" ? nil : original.call(*args, **kw)
    end
    result = r.call(serve_id: c.serve.id, client_attempt_id: "dupe-0000001", raw: wrong_raw, source: "text")
    assert_equal 200, result.http
    assert_equal "unrecognised", result.body[:outcome]
    assert_equal 1, PracticeAttempt.count
  ensure
    PracticeAttempt.singleton_class.send(:remove_method, :find_by) if PracticeAttempt.singleton_class.method_defined?(:find_by, false)
  end

  test "the worker down: 503 retry, nothing stored" do
    c = serve!
    raised = ->(*) { raise Grading::Expression::Unavailable }
    Grading.stub(:grade, raised) do
      result = answer!(c, "1")
      assert_equal [ 503, { status: "retry" } ], [ result.http, result.body ]
    end
    assert_equal 0, PracticeAttempt.count
    assert_equal 0, PracticeEvent.count
  end

  test "grading runs outside any transaction" do
    c = serve!
    seen = nil
    # the test's own transaction is not joinable; grading must run with none of ours open
    Grading.stub(:grade, ->(*args, **kw) { seen = ActiveRecord::Base.connection.current_transaction.joinable?; Grading.grade_spec(Grading::Spec.from_instance(args.first), args[1], **kw) }) do
      answer!(c, correct_raw(c))
    end
    assert_equal false, seen
  end

  test "the grading is refused inside a transaction" do
    c = serve!
    assert_raises(Grading::TransactionOpen) do
      PracticeAttempt.transaction { recorder.call(serve_id: c.serve.id, client_attempt_id: "tx-open-0001", raw: correct_raw(c), source: "text") }
    end
  end

  test "mathlive and button sources are stored, anything else becomes text" do
    c = serve!
    answer!(c, correct_raw(c), id: "src-0000001")
    assert_equal "text", PracticeAttempt.find_by(client_attempt_id: "src-0000001").source
    c2 = serve!
    advance
    recorder.call(serve_id: c2.serve.id, client_attempt_id: "src-0000002", raw: correct_raw(c2), source: "mathlive")
    assert_equal "mathlive", PracticeAttempt.find_by(client_attempt_id: "src-0000002").source
    c3 = serve!
    recorder.call(serve_id: c3.serve.id, client_attempt_id: "src-0000003", raw: correct_raw(c3), source: "ouija")
    assert_equal "text", PracticeAttempt.find_by(client_attempt_id: "src-0000003").source
  end

  test "near misses: a first keeps the serve open, a second closes it (normalized_text items)" do
    item = make_practice_item("it-near", @skill, instances: 0, component: "normalized_text")
    body = JSON.parse(item.body_json).merge("spelling_policy" => "near", "accept" => [])
    # a revision is immutable: build a second one carrying the policy
    near = ItemRevision.create!(item: item.item, seq: 2, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: near, seq: 1, status: "passed", codes_json: "[]")
    ItemInstance.create!(item_revision: near, seed: 1, display_json: JSON.generate(stem_it: "Scrivi"), answer_json: JSON.generate("giardino"), errors_json: "[]",
                         hints_json: JSON.generate([ "a", "b" ]), solution_json: JSON.generate(steps: [], final: "giardino"), fingerprint: "near-fp")
    topic = make_topic(@lesson_revision, { @skill => [ near ] })
    c = serve!(topic: topic)
    one = answer!(c, "giardnio").body
    assert_equal [ "near_miss", %w[retry] ], [ one[:outcome], one[:actions] ]
    assert_equal "Controlla come l'hai scritta: forse c'è un errore di battitura.", one[:message_it]
    assert_nil one[:solution]
    two = answer!(c, "giardnio").body
    assert_equal [ "near_miss", %w[after_solution next back] ], [ two[:outcome], two[:actions] ]
    assert two[:solution]
    assert_equal "Non è ancora giusta. Guarda la soluzione, poi prova un esercizio simile.", two[:message_it]
  end

  test "the body never carries the key, error values or unasked hints" do
    c = serve!
    json = answer!(c, wrong_raw).body.to_json
    assert_no_match(/"answer"|errors|"value"/, json)
    assert_no_match(/Quale regola usi|Fai il primo passaggio/, json) # hints 2 and 3
    refute_includes json, correct_raw(c) if correct_raw(c).size > 2
  end

  test "state changes are reported: demonstrated after the third day" do
    states = []
    3.times do |n|
      c = serve!
      b = answer!(c, correct_raw(c)).body
      states << [ b[:skill][:state], b[:skill][:changed] ]
      advance(86_400) if n >= 0
    end
    assert_equal [ [ "in_study", true ], [ "in_study", false ] ], states.first(2)
    assert_equal [ "demonstrated", true ], states.last
  end
end
