require "test_helper"
require_relative "../../support/practice_world"

# Hints and solutions of a serve (A8.3 rows 11-15, A8.4).
class PracticeActionsTest < ActiveSupport::TestCase
  include PracticeWorld

  setup { build_practice_world }

  test "the hints come one at a time, in order" do
    c = serve!
    r1 = actions.hint(serve_id: c.serve.id, n: 1)
    assert_equal [ 200, { n: 1, total: 3, hint_it: "Che cosa guardi prima?" } ], [ r1.http, r1.body ]
    assert_equal 422, actions.hint(serve_id: c.serve.id, n: 3).http
    assert_equal({ n: 2, total: 3, hint_it: "Quale regola usi?" }, actions.hint(serve_id: c.serve.id, n: 2).body)
    assert_equal({ n: 3, total: 3, hint_it: "Fai il primo passaggio." }, actions.hint(serve_id: c.serve.id, n: 3).body)
    assert_equal [ 422, { status: "bad_hint" } ], actions.hint(serve_id: c.serve.id, n: 4).then { |r| [ r.http, r.body ] }
    assert_equal 3, c.serve.events.where(kind: "hint_shown").count
  end

  test "a hint already shown is returned again without a new event" do
    c = serve!
    actions.hint(serve_id: c.serve.id, n: 1)
    again = actions.hint(serve_id: c.serve.id, n: 1)
    assert_equal 200, again.http
    assert_equal 1, c.serve.events.count
  end

  test "n below one, not a number or missing is 422" do
    c = serve!
    [ 0, -1, nil, "1", 1.5 ].each { |n| assert_equal 422, actions.hint(serve_id: c.serve.id, n: n).http, n.inspect }
    assert_equal 0, PracticeEvent.count
  end

  test "a hint on a closed serve is 409" do
    c = serve!
    answer!(c, correct_raw(c))
    assert_equal 409, actions.hint(serve_id: c.serve.id, n: 1).http
  end

  test "a hint on someone else's serve is 404" do
    c = serve!
    other = practice_student("trial-h")
    assert_equal 404, actions(student: other).hint(serve_id: c.serve.id, n: 1).http
    assert_equal 404, actions(student: other).solution(serve_id: c.serve.id).http
  end

  test "row 12: the solution on an open serve closes it with reason requested; the next answer is 409" do
    c = serve!
    r = actions.solution(serve_id: c.serve.id)
    assert_equal 200, r.http
    assert_equal({ steps: [ { text_it: "Passo.", math: "$x$" } ], final: "$x$" }, r.body[:solution])
    assert_equal %w[after_solution back], r.body[:actions]
    assert_equal({ "reason" => "requested" }, JSON.parse(c.serve.events.last.payload_json))
    assert_equal 409, answer!(c, correct_raw(c)).http
    assert_equal 0, PracticeAttempt.count
  end

  test "row 13: after a typical error the solution is sent with reason after_wrong, no try" do
    c = serve!
    answer!(c, slip_raw(c))
    r = actions.solution(serve_id: c.serve.id)
    assert_equal %w[after_solution back], r.body[:actions]
    assert_equal({ "reason" => "after_wrong" }, JSON.parse(c.serve.events.last.payload_json))
    assert_equal 1, PracticeAttempt.count
  end

  test "row 14: asking again returns the same solution and writes no event" do
    c = serve!
    answer!(c, slip_raw(c))
    first = actions.solution(serve_id: c.serve.id)
    count = PracticeEvent.count
    again = actions.solution(serve_id: c.serve.id)
    assert_equal first.body, again.body
    assert_equal count, PracticeEvent.count
    d = serve!
    answer!(d, correct_raw(d))
    assert_equal 200, actions.solution(serve_id: d.serve.id).http
    assert_equal 1, d.serve.events.where(kind: "solution_shown").count
  end

  test "row 15: on an abandoned serve the solution is 409" do
    c = serve!
    advance(25 * 3600)
    assert_equal 409, actions.solution(serve_id: c.serve.id).http
    assert_equal 409, actions.hint(serve_id: c.serve.id, n: 1).http
  end

  test "a requested solution counts in the skill and the serve's counts" do
    c = serve!
    actions.solution(serve_id: c.serve.id)
    input = Practice::Loader.for(@student, subject: @subject)
    counts = Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves, skills: [ @skill ]).fetch(@skill).counts
    assert_equal [ 1, 1, 0 ], [ counts[:serves], counts[:solutions_requested], counts[:tries] ]
  end

  test "an instance without hints of its own uses the item's, one with none at all has zero" do
    rev = make_practice_item("math-nohint", @skill, instances: 0, hints: [])
    ItemInstance.create!(item_revision: rev, seed: 1, display_json: JSON.generate(stem_it: "x"), answer_json: JSON.generate("1"), errors_json: "[]",
                         hints_json: nil, solution_json: "{}", fingerprint: "nohint-fp")
    topic = make_topic(@lesson_revision, { @skill => [ rev ] })
    c = serve!(topic: topic)
    assert_equal 422, actions.hint(serve_id: c.serve.id, n: 1).http
    assert_empty Practice::Instances.hints(c.instance)
  end
end
