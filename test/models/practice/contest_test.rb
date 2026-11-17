require "test_helper"
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

  test "it is refused with 409 and writes nothing unless the latest try is unrecognised or form and not contested" do
    serve = serve_of(SENTENCE)
    refused = contest_for(@official).call(serve_id: serve.id)
    assert_equal [ 409, { status: "not_contestable" } ], [ refused.http, refused.body ]
    wrong!(serve, "doesn't eat") # a typical error
    assert_equal 409, contest_for(@official).call(serve_id: serve.id).http

    right = serve_of(SENTENCE)
    wrong!(right, "don't eat")
    assert_equal 409, contest_for(@official).call(serve_id: right.id).http

    near = serve_of(WORD)
    wrong!(near, "neighbourhod")
    assert_equal 409, contest_for(@official).call(serve_id: near.id).http
    assert_equal [ 0, 0 ], [ PracticeContest.count, Comment.count ]
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
end
