require "test_helper"

# Lessons::Checks.grade (A9): the declared fields mapped to the shared graders, the shuffle undone with the id_map.
class LessonsChecksTest < ActiveSupport::TestCase
  def grade(check, response, id_map = nil, **opts) = Lessons::Checks.grade(check, response, id_map, **opts)

  NUMBER = { "component" => "number", "prompt_it" => "Quanto?", "answer" => "3,5",
             "errors" => [ { "answer" => "7", "code" => "math_divide_missing", "message_it" => "Non hai diviso." }, { "answer" => "-3,5", "message_it" => "Guarda il segno." } ] }.freeze

  test "number: right (decimal comma and fraction spelling), typical error with its message and code, wrong, invalid" do
    assert grade(NUMBER, "3,5").right?
    assert grade(NUMBER, " 3,50 ").right?
    assert grade(NUMBER, "7/2").invalid?, "a number box does not read a fraction: use the fraction component"
    w = grade(NUMBER, "7")
    assert w.wrong?
    assert_equal "math_divide_missing", w.code
    assert_equal "Non hai diviso.", w.message_it
    assert_equal 0, w.error_index
    w2 = grade(NUMBER, "-3,5")
    assert_equal "Guarda il segno.", w2.message_it
    assert_nil w2.code
    plain = grade(NUMBER, "11")
    assert plain.wrong?
    assert_nil plain.message_it
    bad = grade(NUMBER, "3.5")
    assert bad.invalid?
    assert_equal "use_comma", bad.code
    assert_match(/virgola/, bad.message_it)
    assert grade(NUMBER, "").invalid?
  end

  test "fraction: boxes n and d, an equal value is right, mixed form is checked" do
    check = { "component" => "fraction", "prompt_it" => "Quanto?", "answer" => "5/2", "errors" => [ { "answer" => "2/5", "message_it" => "Numeratore e denominatore sono al contrario." } ] }
    assert grade(check, { "n" => "5", "d" => "2" }).right?
    assert grade(check, { "n" => "10", "d" => "4" }).right?
    assert_equal "Numeratore e denominatore sono al contrario.", grade(check, { "n" => "2", "d" => "5" }).message_it
    assert grade(check, { "n" => "1", "d" => "0" }).invalid?
    mixed = check.merge("mixed" => true)
    assert grade(mixed, { "w" => "2", "n" => "1", "d" => "2" }).right?
    assert grade(mixed, { "n" => "5", "d" => "2" }).wrong?
  end

  CHOICE = { "component" => "choice", "prompt_it" => "Quale?", "answer" => "b",
             "options" => [ { "id" => "a", "text_it" => "A" }, { "id" => "b", "text_it" => "B" }, { "id" => "c", "text_it" => "C" } ],
             "errors" => [ { "answer" => "a", "code" => "math_eval_wrong", "message_it" => "Con A no." } ] }.freeze

  test "choice: shown ids are mapped back by the id_map of the same Rekey call" do
    map = Lessons::Checks.rekey(CHOICE, "lesson|s|1|2|3").id_map
    shown_for = ->(stored) { map.key(stored) }
    assert grade(CHOICE, shown_for.call("b"), map).right?
    w = grade(CHOICE, shown_for.call("a"), map)
    assert_equal "Con A no.", w.message_it
    assert_equal "math_eval_wrong", w.code
    assert grade(CHOICE, shown_for.call("c"), map).wrong?
    assert grade(CHOICE, "zz", map).invalid?
    assert grade(CHOICE, "", map).invalid?
  end

  test "normalized_text: normalisation, accepted spellings, declared errors, an accent slip" do
    check = { "component" => "normalized_text", "prompt_it" => "Scrivi.", "answer" => "è", "accept" => [ "e'" ], "errors" => [ { "answer" => "e", "message_it" => "Manca l'accento." } ] }
    assert grade(check, "È", subject: "italian").right?
    assert grade(check, "e'").right?
    assert_equal "Manca l'accento.", grade(check, "e", subject: "italian").message_it
    assert grade(check, "o").wrong?
    assert grade(check, 12).invalid?
  end

  test "matching: pairs by shown ids, a classification may reuse a right item" do
    check = { "component" => "matching", "prompt_it" => "Abbina.", "reuse_right" => true,
              "left" => [ { "id" => "l1", "text_it" => "uno" }, { "id" => "l2", "text_it" => "due" }, { "id" => "l3", "text_it" => "tre" } ],
              "right" => [ { "id" => "r1", "text_it" => "A" }, { "id" => "r2", "text_it" => "B" } ],
              "answer" => { "l1" => "r1", "l2" => "r1", "l3" => "r2" },
              "errors" => [ { "answer" => { "l1" => "r2", "l2" => "r1", "l3" => "r2" }, "message_it" => "Il primo è di A." } ] }
    map = Lessons::Checks.id_map(check, "lesson|s|1|2|3")
    shown = ->(stored) { map.key(stored) }
    right = { shown.call("l1") => shown.call("r1"), shown.call("l2") => shown.call("r1"), shown.call("l3") => shown.call("r2") }
    assert grade(check, right, map).right?
    typical = right.merge(shown.call("l1") => shown.call("r2"))
    assert_equal "Il primo è di A.", grade(check, typical, map).message_it
    assert grade(check, right.merge(shown.call("l2") => shown.call("r2")), map).wrong?
    assert grade(check, right.except(shown.call("l3")), map).invalid?
  end

  test "span_select: a set of shown span ids, in any order" do
    check = { "component" => "span_select", "prompt_it" => "Tocca.", "text_it" => "La bambina canta una canzone",
              "spans" => [ { "id" => "s1", "text_it" => "La bambina" }, { "id" => "s2", "text_it" => "canta" }, { "id" => "s3", "text_it" => "una canzone" } ],
              "answer" => [ "s2", "s3" ], "errors" => [ { "answer" => [ "s1" ], "code" => "it_subject_for_predicate", "message_it" => "Chi fa l'azione non è il predicato." } ] }
    map = Lessons::Checks.id_map(check, "x")
    assert_equal({ "s1" => "s1", "s2" => "s2", "s3" => "s3" }, map)
    assert grade(check, %w[s3 s2], map).right?
    w = grade(check, %w[s1], map)
    assert_equal "it_subject_for_predicate", w.code
    assert grade(check, %w[s2], map).wrong?
    assert grade(check, [], map).invalid?
    assert grade(check, %w[s9], map).invalid?
    assert grade(check, "s2", map).invalid?
  end

  test "a response over 200 characters is invalid, not graded" do
    assert grade(NUMBER, "1" * 250).invalid?
    assert grade(NUMBER, { "n" => "1" * 250 }).invalid?
  end

  test "the verdict carries the grader version of the shared graders" do
    assert_equal Grading.git_sha, grade(NUMBER, "3,5").grader_version
  end
end
