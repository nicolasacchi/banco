require "test_helper"
require_relative "../support/grading_rows"

# Gradings are appended, never updated; a retry adds a row.
class GradingRecorderTest < ActiveSupport::TestCase
  include GradingRows
  include ActiveJob::TestHelper

  setup do
    body = item_body("normalized-text-static")
    @instance = create_instance(body, body["instances"].first)
  end

  test "append writes one row with the grader's words" do
    attempt = create_attempt(@instance, "hablo")
    result = Grading.grade(@instance, attempt.raw)

    row = Grading::Recorder.append(attempt, result, source: "sync")

    assert_equal 1, row.seq
    assert_equal "correct", row.verdict
    assert_equal "closed", row.grader
    assert_equal "exact", row[:method]
    assert_equal "sync", row.source
    assert_equal "[]", row.error_codes_json
    assert_equal Grading.git_sha, row.grader_version
    assert_nil row.ce_version
  end

  test "stores the error codes, the form violations and the normalized answer" do
    attempt = create_attempt(@instance, "Hablas.")
    row = Grading::Recorder.append(attempt, Grading.grade(@instance, attempt.raw))
    assert_equal "typical_error", row.verdict
    assert_equal [ "wrong_person_ending" ], JSON.parse(row.error_codes_json)
    assert_equal "hablas", row.normalized
  end

  test "a second row gets the next seq and the first is untouched" do
    attempt = create_attempt(@instance, "hablo")
    first = Grading::Recorder.append(attempt, Grading.grade(@instance, attempt.raw))
    second = Grading::Recorder.append(attempt, Grading.grade(@instance, attempt.raw), source: "retry")
    assert_equal [ 1, 2 ], [ first.seq, second.seq ]
    assert_equal %w[sync retry], attempt.gradings.reload.map(&:source)
    assert_raises(ActiveRecord::StatementInvalid) { first.update_columns(verdict: "wrong") }
  end

  test "an invalid answer is not an attempt and is not recorded" do
    attempt = create_attempt(@instance, " ")
    result = Grading.grade(@instance, attempt.raw)
    assert_predicate result, :invalid?
    assert_equal "Scrivi una risposta prima di continuare.", result.message_it
    assert_raises(ArgumentError) { Grading::Recorder.append(attempt, result) }
    assert_equal 0, attempt.gradings.count
  end

  test "dont_know is recorded as a verdict of its own" do
    attempt = create_attempt(@instance, Grading::DONT_KNOW_RAW)
    row = Grading::Recorder.append(attempt, Grading.grade(@instance, attempt.raw))
    assert_equal "dont_know", row.verdict
    assert_equal :D, Grading.evidence(row, @instance)
  end

  test "evidence of a stored row uses the item's declarations" do
    attempt = create_attempt(@instance, "hablas")
    row = Grading::Recorder.append(attempt, Grading.grade(@instance, attempt.raw))
    assert_equal :W, Grading.evidence(row, @instance)
  end

  test "ordering stores the inverted pairs with the grading" do
    body = item_body("ordering-static")
    instance = create_instance(body)
    attempt = create_attempt(instance, [ "e2", "e1", "e3", "e4" ].to_json)
    row = Grading::Recorder.append(attempt, Grading.grade(instance, attempt.raw))
    assert_equal "wrong", row.verdict
    assert_equal 1, JSON.parse(row.normalized)["inverted_pairs"]
  end

  test "the id map of the shuffle is undone before grading" do
    body = item_body("choice-static")
    instance = create_instance(body)
    shown_to_canonical = { "o1" => "o3", "o2" => "o1", "o3" => "o2", "o4" => "o4" }
    assert_equal "correct", Grading.grade(instance, "o2", id_map: shown_to_canonical).verdict
    assert_equal "typical_error", Grading.grade(instance, "o3", id_map: shown_to_canonical).verdict
  end

  test "a short answer is pending for the teacher" do
    instance = create_instance(item_body("short-answer"), "display" => {}, "answer" => "n/a")
    result = Grading.grade(instance, "una risposta libera")
    assert_equal "short_answer", result.verdict
    assert_equal :pending, Grading::Evidence.call(verdict: result.verdict, spec: Grading::Spec.from_instance(instance))
  end
end
