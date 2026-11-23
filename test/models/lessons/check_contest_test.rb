require "test_helper"
require_relative "../../support/lesson_events_world"

# «Per me va bene così» on a check of a lesson/2 (D-396) as the service: the comment with his answer in words for every kind of check, the lesson
# event, the anchor, idempotence, what is refused, and what Lessons::Progress makes of it.
class LessonsCheckContestTest < ActiveSupport::TestCase
  include LessonEventsWorld

  def lesson_body
    @check_kinds ||= Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2/check_kinds.md").read, Validation::Findings.new).body.merge("key" => TOPIC)
  end

  setup { build_student_world(approve: true, release: true) }

  def card_of(component) = stored_body["cards"].find { |c| c["blocks"].any? { |b| b["component"] == component } }
  def block_of(component) = card_of(component)["blocks"].find { |b| b["component"] == component }
  def locator_of(component) = { card: card_of(component)["n"], block: block_of(component)["n"] }
  def try_card = stored_body["cards"].find { |c| c["role"] == "try" }
  def try_locator(ex) = { card: try_card["n"], block: try_card["blocks"].find { |b| b["type"] == "try" }["n"], ex: ex }

  def answerer = Lessons::CheckAnswer.new(@lesson_revision, student_key: @official.key, student: @official, topic_revision: @topic_revision)

  def contest(locator, student: @official)
    view = Course::StudentView.new(student)
    Lessons::CheckContest.new(@lesson_revision, student: student, topic_revision: @topic_revision, course_view: view).call(locator)
  end

  # The stored answer as the page would send it: the shown ids of this student's shuffle.
  def shown_response(locator, stored)
    located = answerer.located(locator)
    map = Lessons::Checks.id_map(located.check, located.seed).invert
    case located.check["component"]
    when "choice" then map.fetch(stored)
    when "tiles", "ordering" then stored.map { |id| map.fetch(id) }
    when "matching" then stored.to_h { |l, r| [ map.fetch(l), map.fetch(r) ] }
    else stored
    end
  end

  def wrong!(locator, stored)
    reply = answerer.call(locator, shown_response(locator, stored), client_event_id: "t-#{SecureRandom.hex(6)}")
    assert_equal "wrong", reply.body[:verdict]
    reply
  end

  {
    "normalized_text" => [ "nome", "nome" ],
    "tiles" => [ %w[b a c d], "legge Marco un libro" ],
    "ordering" => [ %w[b a c], "Rita arriva al cinema. → Rita esce di casa. → Rita si siede." ],
    "span_select" => [ %w[s1], "La bambina" ],
    "matching" => [ { "l1" => "r2", "l2" => "r1", "l3" => "r3" }, "Marco – predicato; legge – soggetto; un libro – oggetto" ]
  }.each do |component, (stored, words)|
    test "a wrong #{component} goes to the teacher with the answer in the words he read" do
      locator = locator_of(component)
      wrong!(locator, stored)
      result = contest(locator)
      assert_equal 200, result.status
      assert_equal "contested", result.body[:status]
      comment = Comment.sole
      assert_equal "La mia risposta, secondo me giusta: «#{words}».", comment.text_it
      assert_equal [ "error", "lesson", "card:#{locator[:card]}/block:#{locator[:block]}", locator[:card] ],
                   comment.attributes.values_at("reason", "page_kind", "anchor", "card")
      assert_equal [ @official.id, @lesson_revision.id ], [ comment.student_id, comment.lesson_revision_id ]
    end
  end

  test "the comment and the event are written once, and a second press answers the same" do
    locator = locator_of("normalized_text")
    wrong!(locator, "nome")
    first = contest(locator)
    event = LessonEvent.where(kind: "check_contested").sole
    comment = Comment.sole
    assert_equal [ @official.id, locator[:card], locator[:block] ], [ event.student_id, event.card, event.block ]
    assert_equal({ "of" => LessonEvent.where(kind: "check_answered").sole.id, "try" => 1, "comment_id" => comment.id }, event.payload)
    assert_nil event.grader_version
    assert_equal first.body[:explain_it], block_of("normalized_text")["explain_it"], "the explanation a finished check shows"
    again = contest(locator)
    assert_equal first, again
    assert_equal [ 1, 1 ], [ LessonEvent.where(kind: "check_contested").count, Comment.count ]
  end

  test "an exercise of «Prova tu» is anchored on its block and its exercise, and the event names the exercise" do
    locator = try_locator(1)
    wrong!(locator, "a")
    assert_equal 200, contest(locator).status
    comment = Comment.sole
    assert_equal "card:#{locator[:card]}/block:#{locator[:block]}/exercise:1", comment.anchor
    assert_equal "La mia risposta, secondo me giusta: «Arriva».", comment.text_it
    assert_equal 1, LessonEvent.where(kind: "check_contested").sole.payload["ex"]
  end

  test "two exercises of «Prova tu» are two comments, each on its own exercise" do
    wrong!(try_locator(1), "a")
    other = try_locator(2)
    wrong!(other, %w[b a c])
    assert_equal 200, contest(try_locator(1)).status
    assert_equal 200, contest(other).status
    assert_equal [ "exercise:1", "exercise:2" ], Comment.order(:id).map { |c| c.anchor.split("/").last }
    assert_equal "La mia risposta, secondo me giusta: «legge Paola un fumetto».", Comment.order(:id).last.text_it
    assert_equal [ 1, 2 ], LessonEvent.where(kind: "check_contested").order(:id).map { |e| e.payload["ex"] }
  end

  test "before the first try, on a right answer and on a check that is not there nothing is written" do
    locator = locator_of("normalized_text")
    assert_equal [ 409, { status: "not_contestable" } ], contest(locator).then { |r| [ r.status, r.body ] }
    assert_equal 200, answerer.call(locator, "verbo", client_event_id: "t-#{SecureRandom.hex(6)}").status
    assert_equal 409, contest(locator).status
    wrong!(locator, "nome")
    assert_equal 200, contest(locator).status, "the latest answer is the wrong one"
    assert_equal 404, contest({ card: 99, block: 1 }).status
    assert_equal 404, contest(locator.merge(ex: 1)).status
    assert_equal [ 1, 1 ], [ LessonEvent.where(kind: "check_contested").count, Comment.count ]
  end

  test "a right answer after a wrong one closes the door, and another student's answer is not his" do
    locator = locator_of("normalized_text")
    wrong!(locator, "nome")
    assert_equal 200, answerer.call(locator, "verbo", client_event_id: "t-#{SecureRandom.hex(6)}").status
    assert_equal 409, contest(locator).status
    assert_equal 409, contest(locator, student: @trial).status
    assert_equal [ 0, 0 ], [ LessonEvent.where(kind: "check_contested").count, Comment.count ]
  end

  test "Lessons::Progress counts a contested check as answered and says how many were sent" do
    locator = locator_of("normalized_text")
    wrong!(locator, "nome")
    before = Lessons::Progress.summary(@official, @lesson_revision)
    assert_equal [ 1, 0 ], [ before.checks_answered, before.checks_contested ]
    contest(locator)
    after = Lessons::Progress.summary(@official, @lesson_revision)
    assert_equal [ 1, 1, 0 ], [ after.checks_answered, after.checks_contested, after.first_try_right ]
  end

  test "the lesson ledger refuses an update of a contest" do
    locator = locator_of("normalized_text")
    wrong!(locator, "nome")
    contest(locator)
    id = LessonEvent.where(kind: "check_contested").sole.id
    assert_raises(ActiveRecord::StatementInvalid) { LessonEvent.connection.execute("UPDATE lesson_events SET block = 9 WHERE id = #{id}") }
    assert_raises(ActiveRecord::StatementInvalid) { LessonEvent.connection.execute("DELETE FROM lesson_events WHERE id = #{id}") }
  end
end
