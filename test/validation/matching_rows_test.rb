require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"

# W-MATCHING-ROWS and E-MATCHING-ROWS (D-370): a practice matching with more than 4 rows warns, with more than 6 it is an
# error for a new submission; a revision that passed under older rules keeps its pass.
class MatchingRowsTest < ActiveJob::TestCase
  include CourseRows
  F = ValidationFixtures

  # A one-to-one matching of +rows+ rows (the right column has one more), the texts different in every instance.
  def instance(rows, number)
    left = (1..rows).map { |i| { "id" => "l#{i}", "text" => "cosa numero #{i} della serie #{number}" } }
    right = (1..rows + 1).map { |i| { "id" => "r#{i}", "text" => "nome numero #{i} della serie #{number}" } }
    answer = (1..rows).to_h { |i| [ "l#{i}", "r#{i}" ] }
    { "display" => { "stem_it" => "Abbina ogni riga al suo nome, serie #{number}.", "left" => left, "right" => right }, "answer" => answer,
      "errors" => [ { "code" => "swap", "value" => answer.merge("l1" => "r2", "l2" => "r1") } ],
      "solution" => { "steps" => [ { "text_it" => "Abbina ogni riga al suo nome." } ], "final" => "fatto" } }
  end

  def practice_matching(rows, kind: "practice_item")
    base = kind == "practice_item" ? F.practice_item : F.static_item
    F.deep_merge(base, "kind" => kind, "component" => "matching", "instances" => (1..10).map { |n| instance(rows, n) },
                       "error_catalogue" => [ { "code" => "swap", "description_it" => "Scambio.", "message_it" => "Controlla.", "implicates" => [] } ],
                       "tests" => { "must_accept" => [], "must_reject" => [], "blank" => "invalid" })
  end

  def run_item(item, **options) = Validation::ItemRunner.new(files: F.files_for(item), context: F.context, **options).call
  def found(result, code) = result.findings.select { |f| f.code == code }

  test "four rows are clean" do
    result = run_item(practice_matching(4))
    assert_empty found(result, "W-MATCHING-ROWS")
    assert_empty found(result, "E-MATCHING-ROWS")
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "five rows warn once for the item, with the most rows, and the item still passes" do
    result = run_item(practice_matching(5))
    warning = found(result, "W-MATCHING-ROWS")
    assert_equal [ "/instances" ], warning.map(&:field)
    assert_equal "warning", warning.first.severity
    assert_equal 5, warning.first.detail[:rows]
    assert_equal 10, warning.first.detail[:count]
    assert_empty found(result, "E-MATCHING-ROWS")
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "six rows still only warn" do
    result = run_item(practice_matching(6))
    assert_equal 1, found(result, "W-MATCHING-ROWS").size
    assert_empty found(result, "E-MATCHING-ROWS")
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "seven rows are an error in a new submission, with no warning beside it" do
    result = run_item(practice_matching(7))
    error = found(result, "E-MATCHING-ROWS")
    assert_equal [ "/instances" ], error.map(&:field)
    assert_equal 7, error.first.detail[:rows]
    assert_empty found(result, "W-MATCHING-ROWS")
    assert_equal "failed", result.status
    assert_includes result.codes, "E-MATCHING-ROWS"
  end

  test "one instance over the maximum is enough" do
    item = practice_matching(5)
    item["instances"][3] = instance(7, 99)
    result = run_item(item)
    assert_equal 1, found(result, "E-MATCHING-ROWS").first.detail[:count]
    assert_equal "failed", result.status
  end

  test "a revision that passed under older rules keeps its pass: seven rows are only the warning" do
    result = run_item(practice_matching(7), grandfathered: true)
    assert_empty found(result, "E-MATCHING-ROWS")
    warning = found(result, "W-MATCHING-ROWS")
    assert_equal 1, warning.size
    assert_includes warning.first.message, "older rules"
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "the thresholds are the file's" do
    Validation::Rules.with(practice: { matching_rows_warn: 5, matching_rows_max: 7 }) do
      assert_empty found(run_item(practice_matching(5)), "W-MATCHING-ROWS")
      assert_equal 1, found(run_item(practice_matching(6)), "W-MATCHING-ROWS").size
      assert_empty found(run_item(practice_matching(7)), "E-MATCHING-ROWS")
      assert_equal 1, found(run_item(practice_matching(8)), "E-MATCHING-ROWS").size
    end
  end

  test "a diagnosis matching is not checked here" do
    result = run_item(practice_matching(7, kind: "diagnosis_item"))
    assert_empty found(result, "W-MATCHING-ROWS")
    assert_empty found(result, "E-MATCHING-ROWS")
  end

  # A judge: two right options, +labels+ the key's option for each row.
  def judge_instance(labels, number)
    display = { "stem_it" => "Giudica le frasi, serie #{number}.", "reuse_right" => true,
                "left" => labels.each_index.map { |i| { "id" => "l#{i + 1}", "text" => "frase #{i + 1} della serie #{number}" } },
                "right" => [ { "id" => "r1", "text" => "giusta" }, { "id" => "r2", "text" => "sbagliata" } ] }
    answer = labels.each_with_index.to_h { |r, i| [ "l#{i + 1}", r ] }
    { "display" => display, "answer" => answer, "errors" => [ { "code" => "swap", "value" => answer.transform_values { |r| r == "r1" ? "r2" : "r1" } } ],
      "solution" => { "steps" => [ { "text_it" => "Giudica ogni frase." } ], "final" => "fatto" } }
  end

  def judge_item(labels, kind: "practice_item")
    practice_matching(4, kind: kind).merge("instances" => (1..10).map { |n| judge_instance(labels, n) })
  end

  test "a practice judge of four rows, two of each option, is clean" do
    result = run_item(judge_item(%w[r1 r2 r1 r2]))
    assert_empty found(result, "E-MATCHING-SIZE")
    assert_empty found(result, "W-MATCHING-ROWS")
    assert_empty found(result, "W-MATCHING-JUDGE-ROWS")
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "a practice judge of three rows is refused, and four rows with one odd row are warned" do
    assert_not_empty found(run_item(judge_item(%w[r1 r2 r1])), "E-MATCHING-SIZE")
    assert_not_empty found(run_item(judge_item(%w[r1 r1 r1 r2])), "W-MATCHING-JUDGE-ROWS")
  end

  test "a practice judge over four rows warns, six rows included" do
    result = run_item(judge_item(%w[r1 r1 r1 r2 r2 r2]))
    assert_equal 1, found(result, "W-MATCHING-ROWS").size
    assert_empty found(result, "E-MATCHING-ROWS")
    assert_empty found(result, "E-MATCHING-SIZE")
  end

  test "a practice judge of five rows (3 + 2) is clean: the split can vary, and the warning starts above five (D-402 round 7)" do
    result = run_item(judge_item(%w[r1 r1 r1 r2 r2]))
    assert_empty found(result, "W-MATCHING-ROWS")
    assert_empty found(result, "E-MATCHING-SIZE")
    assert_empty found(result, "W-MATCHING-JUDGE-ROWS")
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
    assert_equal 1, found(run_item(judge_item(%w[r1 r1 r1 r2 r2 r2])), "W-MATCHING-ROWS").size
    Validation::Rules.with(practice: { matching_two_labels_warn: 4 }) do
      assert_equal 1, found(run_item(judge_item(%w[r1 r1 r1 r2 r2])), "W-MATCHING-ROWS").size, "the five is the file's"
    end
  end

  test "a classification of four rows and four chips with a distractor chip is clean, no fifth row and no warning (D-402 round 7)" do
    display = lambda do |n|
      { "stem_it" => "Classifica la parola, serie #{n}.", "reuse_right" => true,
        "left" => (1..4).map { |i| { "id" => "l#{i}", "text" => "parola numero #{i} della serie #{n}" } },
        "right" => (1..4).map { |i| { "id" => "r#{i}", "text" => "categoria #{i} della serie #{n}" } } }
    end
    key = { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r1" }
    instances = (1..10).map do |n|
      { "display" => display.call(n), "answer" => key, "errors" => [ { "code" => "swap", "value" => key.merge("l1" => "r2") } ],
        "solution" => { "steps" => [ { "text_it" => "Classifica ogni parola." } ], "final" => "fatto" } }
    end
    result = run_item(practice_matching(4).merge("instances" => instances))
    assert_empty found(result, "E-MATCHING-SIZE")
    assert_empty found(result, "W-MATCHING-ROWS")
    assert_equal "passed", result.status, result.findings.map(&:to_h).inspect
  end

  test "a diagnosis judge keeps its six rows" do
    assert_not_empty found(run_item(judge_item(%w[r1 r2 r1 r2], kind: "diagnosis_item")), "E-MATCHING-SIZE")
    assert_empty found(run_item(judge_item(%w[r1 r1 r1 r2 r2 r2], kind: "diagnosis_item")), "E-MATCHING-SIZE")
  end

  test "the practice judge minimum is the file's" do
    Validation::Rules.with(practice: { judge_min_rows: 5 }) do
      assert_not_empty found(run_item(judge_item(%w[r1 r2 r1 r2])), "E-MATCHING-SIZE")
    end
  end

  test "the teacher's card counts the rows of a matching, from every instance" do
    rows = ->(sizes) { Struct.new(:instances).new(sizes.map { |n| Struct.new(:display_json).new(JSON.generate("left" => Array.new(n) { |i| { "id" => "l#{i}" } })) }) }
    assert_equal "4", Teacher::ItemCard.rows_of(rows.([ 4, 4 ]), "component" => "matching").label
    assert_equal "4\u20136", Teacher::ItemCard.rows_of(rows.([ 4, 6, 5 ]), "component" => "matching").label
    assert_nil Teacher::ItemCard.rows_of(rows.([ 4 ]), "component" => "choice")
    assert_nil Teacher::ItemCard.rows_of(rows.([]), "component" => "matching")
  end

  # The stored side: a new revision is validated with the error; one that already passed under older rules keeps its pass.
  test "a new revision of seven rows fails and an approved one under older rules is validated again without the error" do
    build_course
    author = AgentSession.create!(label: "t", role: "author", agent: "test", model: "claude-test")
    fresh, = Validation::Submission.new(key: "rows-new", base: nil, files: F.files_for(practice_matching(7)), session: author).prepare!.store!
    ValidateItemRevisionJob.perform_now(fresh.id)
    assert_equal "failed", fresh.reload.status
    assert_includes JSON.parse(fresh.latest_validation.codes_json), "E-MATCHING-ROWS"

    old, = Validation::Submission.new(key: "rows-old", base: nil, files: F.files_for(practice_matching(7)), session: author).prepare!.store!
    ItemValidation.create!(item_revision: old, seq: 1, status: "passed", codes_json: "[]", rules_version: "11")
    ValidateItemRevisionJob.perform_now(old.id)
    assert_equal %w[passed passed], old.reload.validations.order(:seq).pluck(:status)
    assert_not_includes JSON.parse(old.latest_validation.codes_json), "E-MATCHING-ROWS"
    assert_includes JSON.parse(old.latest_validation.findings_json).map { |f| f["code"] }, "W-MATCHING-ROWS"
  end
end
