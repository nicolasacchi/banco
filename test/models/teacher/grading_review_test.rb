require "test_helper"
require_relative "../../support/grading_review_world"

# D-368: «Contestazioni», the read model of where the grader may be wrong. A world with written tries made right by the teacher, contested, sent twice, a whole
# sentence, a typo, a comment, a number item at exactly half, a superseded revision and the entry test (test/support/grading_review_world.rb).
class TeacherGradingReviewTest < ActiveSupport::TestCase
  include GradingReviewWorld

  setup { build_grading_review_world }

  def review(**over) = Teacher::GradingReview.new(student: @official, **over)

  def signals(review, record, kind: "practice") = review_try(review, record, kind: kind)&.fetch(:signals)

  def decide_resolution(attempt, verdict)
    Decision.create!(kind: "resolve_attempt", subject: @subject, student: @official, request_id: SecureRandom.hex(4), teacher_login: "nik", remote_addr: "127.0.0.1",
                     payload_json: JSON.generate(attempt_id: attempt.id, attempt_kind: "practice", practice_serve_id: attempt.practice_serve_id, try_number: attempt.try_number,
                                                 verdict: verdict, reason_it: "Deciso a mano."))
  end

  # ---- the signals of a not-right try -------------------------------------------------------------------------------

  test "every not-right try has its signals: a sentence round the key, a typo, a resend, contested, a comment, made right by the teacher" do
    r = review
    assert_equal %w[comment resolved_right], signals(r, @resolved_try)
    assert_equal %w[contested comment], signals(r, @contested_try)
    assert_equal %w[full_sentence comment], signals(r, @sentence_try)
    assert_equal %w[near_text], signals(r, @near_try)
    assert_empty signals(r, @first_send)
    assert_equal %w[resend], signals(r, @resend)
    assert_equal %w[comment], signals(r, @commented_try)
    assert_empty signals(r, @plain_try)
    assert_equal %w[full_sentence resolved_right], signals(r, @diag_resolved, kind: "diagnosis")
    assert_empty signals(r, @diag_plain, kind: "diagnosis")
  end

  test "the details a signal rests on: the distance of a typo, the comment's id, the resolution the teacher gave, the grader's own outcome" do
    r = review
    assert_equal 1, review_try(r, @near_try)[:near_distance]
    assert_equal [ @comment.id ], review_try(r, @commented_try)[:comment_ids]
    resolved = review_try(r, @resolved_try)
    assert_equal "unrecognised", resolved[:outcome], "a resolved try keeps what the grader said"
    assert_equal [ "correct", "Era giusta.", @resolution.id ], resolved[:resolution].values_at(:verdict, :reason_it, :decision_id)
    assert_equal "play", resolved[:answer]
    assert_equal [ "wrong", "1 mela" ], review_try(r, @diag_resolved, kind: "diagnosis").values_at(:outcome, :answer)
    assert_equal [ "correct", "Va bene anche così." ], review_try(r, @diag_resolved, kind: "diagnosis")[:resolution].values_at(:verdict, :reason_it)
  end

  test "a right try, a «non lo so» and a try on an older revision are not in the list" do
    refs = review.tries.map { |t| t[:ref] }
    assert_not_includes refs, "practice-#{@right_try.id}"
    assert_not_includes refs, "diagnosis-#{@diag_dont_know.id}"
    assert_not_includes refs, "practice-#{@superseded_try.id}"
    wrong, right = @number_tries.values_at(1, 3, 5), @number_tries.values_at(0, 2, 4)
    assert_empty wrong.map { |t| "practice-#{t.id}" } - refs
    assert_empty right.map { |t| "practice-#{t.id}" } & refs
  end

  test "a comment that names no exercise counts for the tries of its practice page within the hour before it; a «mi piace» counts for nothing" do
    make_comment(page_kind: "practice", page_path: "/topics/#{TOPIC}/practice/#{SKILL}", created_at: @text_t + 700)
    make_comment(reason: "like", practice_serve: @near_try.practice_serve, created_at: @text_t + 800)
    r = review
    assert_equal %w[near_text comment], signals(r, @near_try)
    assert_equal %w[comment], signals(r, @plain_try)
    assert_equal %w[comment resolved_right], signals(r, @resolved_try), "two hours before the comment: not about it, only the contest's own comment says so"
    assert_equal %w[comment], signals(r, @commented_try)
  end

  # ---- «Per me va bene così» writes no comment (D-400): the review is where the teacher reads every contest ----------------

  test "D-400: a practice contest made now is the contested signal of its try, with no comment of its own, and is counted" do
    serve = text_serve(@word, 4, at: @clock.now)
    try = make_try(serve, raw: "play", verdict: "wrong", at: @clock.now)
    comments = Comment.count
    assert_equal 200, Practice::Contest.new(student: @official, course_view: Course::StudentView.new(@official), clock: @clock).call(serve_id: serve.id).http
    assert_equal comments, Comment.count
    r = review
    assert_equal %w[contested], signals(r, try)
    assert_equal 2, r.totals[:contested]
    assert_equal "play", r.answer_words.fetch("practice-#{try.id}")
  end

  test "D-400: the checks of the lessons that he sent are listed with his answer in words, oldest first, in the window and the subject" do
    r = review
    row = r.lesson_contests.sole
    assert_equal [ "lesson_check", "lesson_check-#{@lesson_contest.id}", @lesson_contest.id, @subject.key, TOPIC, 2, 1, { "ex" => 2 }, "legge Marco un libro", [] ],
                 row.values_at(:kind, :ref, :id, :subject, :topic, :card, :block, :place, :answer, :comment_ids)
    assert_equal 1, r.totals[:lesson_contested]

    assert_equal 1, review(subject: @subject.key).lesson_contests.size
    assert_empty review(subject: "no_such_subject").lesson_contests
    assert_equal 1, review(since: @lesson_contest.at - 1).lesson_contests.size
    assert_empty review(since: @lesson_contest.at + 1).lesson_contests
    assert_empty Teacher::GradingReview.new(student: @trial).lesson_contests
  end

  test "D-400: a lesson contest of before has no words and points at its comment" do
    old = make_comment(text_it: "La mia risposta, secondo me giusta: «nome».", page_kind: "lesson", page_path: "/topics/#{TOPIC}/lesson")
    event = LessonEvent.create!(student: @official, topic_revision: @text_topic, lesson_revision: @lesson_revision, kind: "check_contested", card: 1, block: 1,
                                payload_json: JSON.generate(of: 2, try: 1, comment_id: old.id), client_event_id: "contest-#{SecureRandom.hex(6)}", at: @text_t + 1000, created_at: @text_t + 1000)
    row = review.lesson_contests.find { |c| c[:id] == event.id }
    assert_equal [ nil, [ old.id ] ], row.values_at(:answer, :comment_ids)
  end

  test "a resolution to wrong is a manual correction that is not a signal of a wrong grade" do
    decide_resolution(@plain_try, "wrong")
    r = review
    assert_empty signals(r, @plain_try)
    row = r.items.find { |i| i[:item] == WORD }
    assert_equal [ 1, true, %w[many_not_right manual_correction] ], row.values_at(:manual_corrections, :flagged, :flag_reasons)
  end

  # ---- the items ------------------------------------------------------------------------------------------------------

  test "the items: tries, not-right rate, manual-correction rate, the flagged ones first" do
    items = review.items
    assert_equal [ "diag-text-1", SENTENCE, WORD, "demo-item-2" ], items.map { |i| i[:item] }
    by_key = items.index_by { |i| i[:item] }

    assert_equal({ item: "diag-text-1", subject: "math", skill: SKILL, component: "normalized_text", tries: 2, not_right: 2, not_right_rate: 1.0, manual_corrections: 1,
                   manual_correction_rate: 0.5, resends: 0, contested: 0, suspect_tries: 1, flagged: true, flag_reasons: [ "manual_correction" ],
                   last_at: review_try(review, @diag_plain, kind: "diagnosis")[:at] }, by_key["diag-text-1"])
    assert_equal [ 4, 3, 0.75, 1, 0.25, 1, 3, true, [ "manual_correction" ] ],
                 by_key[SENTENCE].values_at(:tries, :not_right, :not_right_rate, :manual_corrections, :manual_correction_rate, :contested, :suspect_tries, :flagged, :flag_reasons)
    assert_equal [ 5, 5, 1.0, 0, 1, 3, true, [ "many_not_right" ] ],
                 by_key[WORD].values_at(:tries, :not_right, :not_right_rate, :manual_corrections, :resends, :suspect_tries, :flagged, :flag_reasons)
    assert_equal [ 6, 3, 0.5, 0, false, [] ], by_key["demo-item-2"].values_at(:tries, :not_right, :not_right_rate, :manual_corrections, :flagged, :flag_reasons)
    assert_nil by_key["demo-item-1"], "its only try is on a revision a newer one replaced"
  end

  test "four wrong tries with no correction are not flagged; the fifth flags the item; exactly half of six is not enough" do
    revision = make_practice_item("demo-item-3", SKILL, instances: 6)
    try = lambda do |n|
      at = @text_t + 9000 + n * 120
      make_try(make_serve(@official, @topic_revision, instance_n(revision, n), skill_key: SKILL, at: at), raw: "9", verdict: "wrong", at: at + 60)
    end
    4.times { |n| try.call(n) }
    row = review.items.find { |i| i[:item] == "demo-item-3" }
    assert_equal [ 4, 4, false, [] ], row.values_at(:tries, :not_right, :flagged, :flag_reasons)

    try.call(4)
    row = review.items.find { |i| i[:item] == "demo-item-3" }
    assert_equal [ 5, 5, true, [ "many_not_right" ] ], row.values_at(:tries, :not_right, :flagged, :flag_reasons)
    assert_equal false, review.items.find { |i| i[:item] == "demo-item-2" }[:flagged]
  end

  # ---- the totals, the window and the filters ----------------------------------------------------------------------------

  test "the totals are the weekly measure: written answers not right, manual corrections, resends, contested" do
    assert_equal({ tries: 17, not_right: 13, written_tries: 11, written_not_right: 10, written_not_right_rate: 0.909, manual_corrections: 2, resends: 1, contested: 1, lesson_contested: 1, items: 4,
                   flagged_items: 3, superseded: 1,
                   signals: { "full_sentence" => 2, "near_text" => 1, "resend" => 1, "contested" => 1, "comment" => 4, "resolved_right" => 2 } }, review.totals)
  end

  test "since keeps the tries from that moment on, and a resend still sees the try before the window" do
    r = review(since: @text_t + 330)
    assert_equal [ WORD, "demo-item-2" ], r.items.map { |i| i[:item] }
    assert_equal [ 3, false ], r.items.first.values_at(:tries, :flagged)
    assert_equal %w[resend], signals(r, @resend)
    assert_nil review_try(r, @first_send), "the first of the two is before the window"
    assert_nil review_try(r, @resolved_try)
    assert_equal @text_t.utc.iso8601, review(since: @text_t).to_h[:since]
  end

  test "a subject with no try has nothing" do
    r = review(subject: "english")
    assert_empty r.items
    assert_empty r.tries
    assert_equal [ 0, 0, 0.0 ], r.totals.values_at(:tries, :not_right, :written_not_right_rate)
  end

  test "the answers are the student's words: to_h gives them or leaves them out" do
    with = review.to_h
    assert_equal "play", with[:tries].find { |t| t[:ref] == "practice-#{@resolved_try.id}" }[:answer]
    without = review.to_h(answers: false)
    assert without[:tries].none? { |t| t.key?(:answer) }
    assert_equal with[:items], without[:items]
    assert_not_includes JSON.generate(without), "neighbourhod"
    assert_equal %i[student since subject totals items tries lesson_contests], with.keys
    assert without[:lesson_contests].none? { |c| c.key?(:answer) }
    assert_equal "legge Marco un libro", with[:lesson_contests].sole[:answer]
  end

  test "it reads and writes nothing: no row of the ledger changes" do
    counts = -> { [ PracticeAttempt, PracticeContest, PracticeServe, PracticeGrading, Attempt, AttemptGrading, Decision, Comment, CommentEvent, AppEvent ].map(&:count) }
    before = counts.call
    review.to_h
    Teacher::GradingVectors.new(@official).cases
    assert_equal before, counts.call
  end

  test "a trial student's tries are not the official student's" do
    other = Teacher::GradingReview.new(student: @trial)
    assert_empty other.items
    assert_equal 0, other.totals[:tries]
  end
end
