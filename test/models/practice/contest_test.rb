require "test_helper"
require "minitest/mock"
require_relative "../../support/practice_text_world"

# «Fai controllare» (D-339) as the service: the contest row, the teacher's comment, the solution event, idempotence, what the loader makes of it,
# and the table's append-only triggers.
class PracticeContestTest < ActiveSupport::TestCase
  include PracticeTextWorld

  setup { build_text_world }

  def contest_for(student, view: nil) = Practice::Contest.new(student: student, course_view: Course::StudentView.new(student, view: view), clock: @clock)

  def serve_of(key, student: @official) = serve!(student: student, topic: @text_topic, skill: SKILL, item: key).serve

  def wrong!(serve, raw = "play", student: @official) = answer!(serve, raw, student: student).body

  def solution_reasons(serve) = serve.events.reload.select { |e| e.kind == "solution_shown" }.map { |e| JSON.parse(e.payload_json)["reason"] }

  test "a contest on an open serve writes the row, the comment and the solution event, once" do
    serve = serve_of(SENTENCE)
    wrong!(serve)
    result = contest_for(@official).call(serve_id: serve.id)
    assert_equal 200, result.http
    assert_equal %i[status message_it solution actions], result.body.keys
    assert_equal [ "contested", I18n.t("practice.contested"), %w[next back] ], result.body.values_at(:status, :message_it, :actions)
    assert_equal({ steps: [ { text_it: "Passo." } ], final: "don't eat" }, result.body[:solution])

    contest = PracticeContest.sole
    attempt = serve.attempts.sole
    assert_equal [ @official, serve, attempt ], [ contest.student, contest.practice_serve, contest.practice_attempt ]
    assert_equal "La mia risposta, secondo me giusta: «play».", contest.comment.text_it
    assert_equal [ "error", "practice", "exercise/item/answer" ], contest.comment.attributes.values_at("reason", "page_kind", "anchor")
    assert_equal [ serve.id, serve.item_instance_id ], [ contest.comment.practice_serve_id, contest.comment.item_instance_id ]
    assert_equal %w[after_contest], solution_reasons(serve)

    again = contest_for(@official).call(serve_id: serve.id)
    assert_equal result, again
    assert_equal [ 1, 1, %w[after_contest] ], [ PracticeContest.count, Comment.count, solution_reasons(serve) ]
  end

  test "the loader reads the contest: the try is contested and counts neither way, the serve is closed contested" do
    serve = serve_of(SENTENCE)
    wrong!(serve)
    before = Practice::Loader.status_of(PracticeServe.find(serve.id), now: @clock.now)
    assert_equal :open, before.state
    assert_includes before.actions, :contest

    contest_for(@official).call(serve_id: serve.id)
    status = Practice::Loader.status_of(PracticeServe.find(serve.id), now: @clock.now)
    assert_equal [ :closed, :contested, %i[next back] ], [ status.state, status.closed_by, status.actions ]
    try = Practice::Loader.for(@official, subject: @subject, seeds: false, now: @clock.now).tries.sole
    assert_equal [ :contested, :N, true ], [ try.outcome, try.evidence, try.contested ]
  end

  test "it is refused with 409 and writes nothing with no try or on a right one (D-389)" do
    serve = serve_of(SENTENCE)
    refused = contest_for(@official).call(serve_id: serve.id)
    assert_equal [ 409, { status: "not_contestable" } ], [ refused.http, refused.body ]

    right = serve_of(SENTENCE)
    wrong!(right, "don't eat")
    assert_equal 409, contest_for(@official).call(serve_id: right.id).http
    assert_equal [ 0, 0 ], [ PracticeContest.count, Comment.count ]
  end

  test "D-389: a typical error and a near miss are contested too, the comment carrying the answer as typed" do
    typical = serve_of(SENTENCE)
    wrong!(typical, "doesn't eat")
    assert_equal 200, contest_for(@official).call(serve_id: typical.id).http
    near = serve_of(WORD)
    wrong!(near, "neighbourhod")
    assert_equal 200, contest_for(@official).call(serve_id: near.id).http
    assert_equal [ "La mia risposta, secondo me giusta: «doesn't eat».", "La mia risposta, secondo me giusta: «neighbourhod»." ],
                 PracticeContest.order(:id).map { |c| c.comment.text_it }
    assert_equal %w[after_contest], solution_reasons(near)
  end

  test "D-395: after «Mostra la soluzione» on an open serve the latest try is still contested; the solution is not sent twice" do
    serve = serve_of(SENTENCE)
    wrong!(serve)
    shown = Practice::Actions.new(student: @official, clock: @clock).solution(serve_id: serve.id)
    assert_equal %w[after_solution back contest], shown.body[:actions]
    assert_equal %w[requested], solution_reasons(serve)

    result = contest_for(@official).call(serve_id: serve.id)
    assert_equal [ 200, "contested", %w[next back] ], [ result.http, result.body[:status], result.body[:actions] ]
    assert_equal "La mia risposta, secondo me giusta: «play».", PracticeContest.sole.comment.text_it
    assert_equal %w[requested], solution_reasons(serve)
    assert_equal [ :closed, :contested ], Practice::Loader.status_of(PracticeServe.find(serve.id), now: @clock.now).then { |st| [ st.state, st.closed_by ] }
  end

  test "D-395: a solution asked for with no try is not contestable" do
    serve = serve_of(SENTENCE)
    Practice::Actions.new(student: @official, clock: @clock).solution(serve_id: serve.id)
    assert_equal 409, contest_for(@official).call(serve_id: serve.id).http
    assert_equal [ 0, 0 ], [ PracticeContest.count, Comment.count ]
  end

  test "D-395: the contests of two serves with the same words are two comments, never one merged by the repeat check" do
    first = serve_of(SENTENCE)
    wrong!(first, "play")
    second = serve_of(WORD)
    wrong!(second, "play")
    contest_for(@official).call(serve_id: first.id)
    contest_for(@official).call(serve_id: second.id)

    contests = PracticeContest.order(:id).to_a
    assert_equal 2, Comment.count
    assert_equal 2, contests.map(&:comment_id).uniq.size
    assert_equal [ first.id, second.id ], contests.map { |c| c.comment.practice_serve_id }
    assert_equal [ "La mia risposta, secondo me giusta: «play»." ], Comment.pluck(:text_it).uniq
  end

  test "D-395: a repeat of the same contest comment on the same serve is still one comment (D-388)" do
    serve = serve_of(SENTENCE)
    wrong!(serve, "play")
    contest_for(@official).call(serve_id: serve.id)
    again = Comments::Intake.call(student: @official, course_view: Course::StudentView.new(@official),
                                  params: { client_comment_id: "other-id-1", reason: "error", text_it: Comment.sole.text_it, page_path: Comment.sole.page_path,
                                            anchor: Practice::Contest::COMMENT_ANCHOR, refs: { "serve_id" => serve.id } })
    assert_equal [ :recorded, Comment.sole.id ], [ again.status, again.comment.id ]
    assert_equal 1, Comment.count
  end

  test "D-395: a long typed answer is carried up to the comment's limit less the template; over it, it is cut and ends with «…»" do
    serve = serve_of(WORD)
    wrong!(serve, "parola " * 100) # 700 characters: whole
    contest_for(@official).call(serve_id: serve.id)
    assert_equal "La mia risposta, secondo me giusta: «#{'parola ' * 99}parola».", Comment.sole.text_it

    long = serve_of(WORD)
    wrong!(long, "y" * 5000)
    contest_for(@official).call(serve_id: long.id)
    text = Comment.order(:id).last.text_it
    assert_equal Comment::TEXT_MAX, text.length
    assert_match(/\ALa mia risposta, secondo me giusta: «y+…»\.\z/, text)
  end

  test "D-395: a matching too long for the comment is cut at the last «; », a whole pair, and ends with «…»" do
    left = (1..4).map { |n| { id: "l#{n}", text: "Autore #{n} #{'lungo ' * 40}".strip } }
    right = (1..4).map { |n| { id: "r#{n}", text: "Opera #{n} #{'vasta ' * 40}".strip } }
    serve = closed_serve("closed-matching-long", "matching", { left: left, right: right }, { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r4" })
    raw = { "l1" => "r1", "l2" => "r1", "l3" => "r1", "l4" => "r2" }
    wrong!(serve, JSON.generate(raw))
    assert_equal 200, contest_for(@official).call(serve_id: serve.id).http

    words = shown_texts(PracticeServe.find(serve.id))
    pairs = raw.map { |l, r| "#{words.call(l)} – #{words.call(r)}" }
    assert_operator pairs.join("; ").length, :>, Comment::TEXT_MAX - 60, "the whole answer does not fit"
    assert_equal "La mia risposta, secondo me giusta: «#{pairs.first(3).join('; ')}…».", PracticeContest.sole.comment.text_it
  end

  test "another student's serve is a 404" do
    serve = serve_of(SENTENCE)
    wrong!(serve)
    result = contest_for(@trial).call(serve_id: serve.id)
    assert_equal [ 404, { status: "not_found" } ], [ result.http, result.body ]
    assert_equal 0, PracticeContest.count
  end

  test "a serve closed wrong contests its second try without a second solution" do
    serve = serve_of(WORD)
    wrong!(serve, "casa")
    wrong!(serve, "albero")
    assert_equal %w[after_last_try], solution_reasons(serve)
    assert_equal %i[after_solution back contest], Practice::Loader.status_of(PracticeServe.find(serve.id), now: @clock.now).actions
    result = contest_for(@official).call(serve_id: serve.id)
    assert_equal [ 200, "contested" ], [ result.http, result.body[:status] ]
    assert_equal 2, PracticeContest.sole.practice_attempt.try_number
    assert_equal %w[after_last_try], solution_reasons(serve)
  end

  test "the preview student's contest has no comment" do
    preview = Student.reset_preview!
    serve = serve_of(SENTENCE, student: preview)
    wrong!(serve, student: preview)
    result = contest_for(preview, view: :official).call(serve_id: serve.id)
    assert_equal 200, result.http
    contest = PracticeContest.sole
    assert_equal [ preview.id, nil ], [ contest.student_id, contest.comment_id ]
    assert_equal 0, Comment.count
    assert_equal %w[after_contest], solution_reasons(serve)
  end

  test "the table is append-only and holds one contest per attempt" do
    serve = serve_of(SENTENCE)
    wrong!(serve)
    contest_for(@official).call(serve_id: serve.id)
    row = PracticeContest.sole
    assert_raises(ActiveRecord::StatementInvalid) { row.update_columns(comment_id: nil) }
    assert_raises(ActiveRecord::StatementInvalid) { PracticeContest.where(id: row.id).delete_all }
    assert_raises(ActiveRecord::RecordNotUnique) { PracticeContest.create!(student: @official, practice_serve: serve, practice_attempt: row.practice_attempt) }
  end

  test "the sentence of a contested try is the contested one" do
    assert_equal I18n.t("practice.contested"), Practice::Messages.feedback(:contested)
  end

  # ---- the comment says his answer in words, never in code (D-387) ----------------------------------

  # A practice item of a closed component (choice, matching) pinned alone on a new approved topic revision; the serve's ids are re-keyed as the page does.
  def closed_serve(key, component, display, answer)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: component, level: 1,
             expected_seconds: 60, hints_it: [], error_catalogue: [] }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    6.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(display), answer_json: JSON.generate(answer), errors_json: "[]",
                           hints_json: "[]", solution_json: JSON.generate(steps: [ { text_it: "Passo." } ], final: "Vedi."),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    topic = make_topic(@lesson_revision, { SKILL => [ revision ] }, course: @course)
    approve_topic!(topic)
    serve!(student: @official, topic: topic, skill: SKILL, item: key).serve
  end

  # The texts of the stored display by stored id, and the shown id's text through the serve's logged map.
  def shown_texts(serve)
    display = JSON.parse(serve.item_instance.display_json)
    texts = (%w[options left right].flat_map { |k| Array(display[k]) }).to_h { |e| [ e["id"], e["text"] ] }
    map = JSON.parse(serve.id_map_json.presence || "{}")
    ->(shown_id) { texts.fetch(map.fetch(shown_id, shown_id)) }
  end

  test "the comment of a wrong choice is the option text he read, not its id" do
    options = [ { id: "o1", text: "Produrre automobili" }, { id: "o2", text: "Vendere libri" }, { id: "o3", text: "Insegnare a scuola" }, { id: "o4", text: "Curare i malati" } ]
    serve = closed_serve("closed-choice", "choice", { options: options }, "o1")
    map = JSON.parse(serve.id_map_json.presence || "{}")
    wrong_id = %w[o1 o2 o3 o4].find { |shown| map.fetch(shown, shown) != "o1" }
    wrong!(serve, wrong_id)
    assert_equal 200, contest_for(@official).call(serve_id: serve.id).http

    text = PracticeContest.sole.comment.text_it
    assert_equal "La mia risposta, secondo me giusta: «#{shown_texts(PracticeServe.find(serve.id)).call(wrong_id)}».", text
    assert_no_match(/\bo\d\b|[{\[]/, text)
  end

  test "the comment of a wrong matching is «riga – scelta; riga – scelta» in the texts he read, with no braces and no l1" do
    left = (1..4).map { |n| { id: "l#{n}", text: "Autore #{n}" } }
    right = (1..4).map { |n| { id: "r#{n}", text: "Opera #{n}" } }
    serve = closed_serve("closed-matching", "matching", { left: left, right: right }, { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r4" })
    raw = { "l1" => "r1", "l2" => "r1", "l3" => "r1", "l4" => "r2" }
    wrong!(serve, JSON.generate(raw))
    assert_equal 200, contest_for(@official).call(serve_id: serve.id).http

    text = PracticeContest.sole.comment.text_it
    words = shown_texts(PracticeServe.find(serve.id))
    expected = raw.map { |l, r| "#{words.call(l)} – #{words.call(r)}" }.join("; ")
    assert_equal "La mia risposta, secondo me giusta: «#{expected}».", text
    assert_no_match(/[{}\[\]]|\bl\d\b|\br\d\b/, text)
  end

  test "an answer that cannot be put in words goes without the answer, never as code" do
    serve = closed_serve("closed-broken", "choice", { options: [ { id: "o1", text: "Uno" }, { id: "o2", text: "Due" } ] }, "o1")
    map = JSON.parse(serve.id_map_json.presence || "{}")
    wrong!(serve, %w[o1 o2].find { |shown| map.fetch(shown, shown) != "o1" }) # the options are re-keyed: the shown id that is not the key
    reader_fails = ->(*) { raise JSON::ParserError, "the answer does not read as this exercise's" }
    Diagnosis::AnswerText.stub(:call, reader_fails) do
      assert_equal 200, contest_for(@official).call(serve_id: serve.id).http
    end
    assert_equal "Secondo me la mia risposta è giusta.", PracticeContest.sole.comment.text_it
  end
end
