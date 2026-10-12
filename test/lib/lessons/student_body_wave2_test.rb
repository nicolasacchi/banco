require "test_helper"
require "minitest/mock"
require_relative "../../support/lesson_checks_wave2_world"

# What the student's page is told about tiles, ordering and select checks (L1, L3), and the check endpoint's reply for them.
class LessonsStudentBodyWave2Test < ActiveSupport::TestCase
  include LessonChecksWave2World

  SENTINEL = "ANS-9f3c1d"

  def leaky(check) = check.merge("verify" => { "fn" => "x.y", "args" => { "a" => SENTINEL } }, "reachable_ok_it" => SENTINEL, "explain_it" => SENTINEL)

  def served(check, seed = "seed-1") = Lessons::StudentBody.check(check, "english", seed)

  test "tiles are served shuffled with fresh ids; the answer, the accepted sequences, the errors and the verify never" do
    json = JSON.generate(served(leaky(TILES)))
    assert_not_includes json, SENTINEL
    assert_not_includes json, "en_past_in_if"
    assert_not_includes json, "Dopo if"
    out = served(TILES)
    assert_equal %w[component prompt_it tiles], out.keys.sort
    assert_equal %w[e1 e2 e3 e4 e5 e6 e7], out["tiles"].map { |t| t["id"] }
    assert_equal TILES["tiles"].map { |t| t["text_en"] }.sort, out["tiles"].map { |t| t["text_en"] }.sort
    assert_equal served(TILES), served(TILES), "the same student sees the same order"
    assert_not_equal served(TILES, "other")["tiles"], served(TILES)["tiles"], "another student's order differs"
  end

  test "ordering items are served shuffled and without the key" do
    out = served(leaky(ORDERING))
    assert_equal %w[component items prompt_it], out.keys.sort
    assert_equal %w[e1 e2 e3 e4], out["items"].map { |t| t["id"] }
    assert_not_includes JSON.generate(out), SENTINEL
  end

  test "a select check serves the type's select projection, the set name and pick; never the answer" do
    Lessons::Diagrams.stub(:module_for, ->(type) { type == "network" ? FakeFigure : nil }) do
      out = served(leaky(select_check))
      assert_equal %w[component diagram pick prompt_it targets], out.keys.sort
      assert_equal "select", out["diagram"]["mode"]
      assert_equal "many", out["pick"]
      assert_not_includes JSON.generate(out), SENTINEL
      assert_not_includes JSON.generate(out), "n2", "the answer's target ids are not in the page"
    end
  end

  test "a select check on a type that cannot give the select projection is never served" do
    assert_raises(NotImplementedError) { served(select_check) }
  end

  Revision = Struct.new(:id, :body)

  def revision_with(check)
    body = { "subject" => "english", "cards" => [ { "n" => 1, "blocks" => [ { "n" => 1, "type" => "check" }.merge(check) ] } ] }
    Revision.new(7, body)
  end

  def answer(revision, response)
    Lessons::CheckAnswer.new(revision, student_key: "prova-1").call({ card: 1, block: 1 }, response).body
  end

  test "the endpoint undoes the student's own shuffle: tiles and ordering" do
    rev = revision_with(TILES)
    seed = Lessons::StudentBody.seed_for("prova-1", 7, 1, 1)
    map = Lessons::Checks.id_map(TILES, seed)
    built = %w[a b c d e f].map { |s| map.key(s) }
    reply = answer(rev, built)
    assert_equal "right", reply[:verdict]
    wrong = answer(rev, %w[a b g d e f].map { |s| map.key(s) })
    assert_equal "wrong", wrong[:verdict]
    assert_equal "Dopo if, qui serve il presente.", wrong[:message_it]
    assert_equal "invalid", answer(rev, [])[:verdict]
  end

  test "the endpoint maps tN back through the figure's reading order: select" do
    Lessons::Diagrams.stub(:module_for, ->(type) { type == "network" ? FakeFigure : nil }) do
      rev = revision_with(select_check)
      assert_equal "right", answer(rev, %w[t2 t4])[:verdict]
      assert_equal "wrong", answer(rev, %w[t2])[:verdict]
      assert_equal "bio_membrane", Lessons::Checks.grade(select_check, %w[t1], Lessons::Checks.id_map(select_check, "")).code
    end
  end
end
