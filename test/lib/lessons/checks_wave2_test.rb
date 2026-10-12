require "test_helper"
require "minitest/mock"
require_relative "../../support/lesson_checks_wave2_world"

# The check components of wave 2 that T1 owns (WAVE2 2.11, D-267): tiles, ordering, select, and the options thousands, profile, contractions.
class LessonsChecksWave2Test < ActiveSupport::TestCase
  include LessonChecksWave2World

  def grade(check, response, id_map = nil, **opts) = Lessons::Checks.grade(check, response, id_map, **opts)

  def shown(check, seed = "seed-1") = Lessons::Checks.rekey(check, seed)

  def shown_ids(check, stored, seed = "seed-1")
    map = Lessons::Checks.id_map(check, seed)
    stored.map { |s| map.key(s) }
  end

  test "tiles are served shuffled under fresh ids, the same for the same seed, and never in the key's order first" do
    a = shown(TILES)
    assert_equal %w[e1 e2 e3 e4 e5 e6 e7], a.display["elements"].map { |t| t["id"] }
    assert_equal a.shown_order, shown(TILES).shown_order
    assert_not_equal TILES["answer"], a.shown_order["elements"].first(6)
    assert_equal TILES["tiles"].map { |t| t["id"] }.sort, a.shown_order["elements"].sort
  end

  test "tiles: the answer, an accepted sequence, a typical error with its code and message, a plain wrong, a partial sentence" do
    assert grade(TILES, shown_ids(TILES, %w[a b c d e f]), Lessons::Checks.id_map(TILES, "seed-1")).right?
    assert grade(TILES, shown_ids(TILES, %w[d e f a b c]), Lessons::Checks.id_map(TILES, "seed-1")).right?
    map = Lessons::Checks.id_map(TILES, "seed-1")
    w = grade(TILES, shown_ids(TILES, %w[a b g d e f]), map)
    assert w.wrong?
    assert_equal "en_past_in_if", w.code
    assert_equal "Dopo if, qui serve il presente.", w.message_it
    plain = grade(TILES, shown_ids(TILES, %w[a c b d e f]), map)
    assert plain.wrong?
    assert_nil plain.code
    assert grade(TILES, shown_ids(TILES, %w[a b c]), map).wrong?, "a sentence that is not finished is wrong, not unreadable"
  end

  test "tiles: an empty line, an unknown id and a tile used twice cannot be read" do
    map = Lessons::Checks.id_map(TILES, "seed-1")
    assert grade(TILES, [], map).invalid?
    assert grade(TILES, %w[zz], map).invalid?
    assert grade(TILES, %w[e1 e1], map).invalid?
    assert grade(TILES, "e1", map).invalid?
    assert grade(TILES, [ 1 ], map).invalid?
  end

  test "ordering: the right order, a coded error, a wrong order, and a list that is not complete" do
    map = Lessons::Checks.id_map(ORDERING, "s2")
    assert grade(ORDERING, shown_ids(ORDERING, %w[p q r s], "s2"), map).right?
    w = grade(ORDERING, shown_ids(ORDERING, %w[p r q s], "s2"), map)
    assert_equal "Prima si discute, poi si vota.", w.message_it
    assert grade(ORDERING, shown_ids(ORDERING, %w[s r q p], "s2"), map).wrong?
    incomplete = grade(ORDERING, shown_ids(ORDERING, %w[p q], "s2"), map)
    assert incomplete.invalid?
    assert_match(/in ordine/, incomplete.message_it)
  end

  test "ordering: the first view is never the key, its reverse or the stored listing" do
    40.times do |i|
      order = shown(ORDERING, "seed-#{i}").shown_order["elements"]
      assert_not_equal ORDERING["answer"], order
      assert_not_equal ORDERING["answer"].reverse, order
      assert_not_equal %w[p r q s], order, "an untouched list would be graded as a typical error"
    end
  end

  # ---- select: with a figure type that offers targets -------------------------------------------------------

  def with_fake(&) = Lessons::Diagrams.stub(:module_for, ->(type) { type == "network" ? FakeFigure : nil }, &)

  test "select: the targets are named t1..tN in the figure's reading order and the response is a list of tN" do
    with_fake do
      check = select_check
      assert_equal({ "t1" => "n1", "t2" => "n2", "t3" => "n3", "t4" => "n4", "t5" => "n5" }, Lessons::Checks.id_map(check, "x"))
      map = Lessons::Checks.id_map(check, "x")
      assert grade(check, %w[t2 t4], map).right?
      assert grade(check, %w[t4 t2], map).right?, "the order of the taps is nothing"
      assert grade(check, %w[t2], map).wrong?
      w = grade(check, %w[t1], map)
      assert_equal "bio_membrane", w.code
      assert_equal "Quella è la membrana.", w.message_it
      assert grade(check, [], map).invalid?
      assert grade(check, %w[t9], map).invalid?
      assert grade(check, %w[t2 t2], map).invalid?
    end
  end

  test "select pick one: any one member of the answer is right, two taps are not" do
    with_fake do
      check = select_check(pick: "one", answer: %w[n2 n4])
      map = Lessons::Checks.id_map(check, "x")
      assert grade(check, %w[t2], map).right?
      assert grade(check, %w[t4], map).right?
      assert grade(check, %w[t2 t4], map).wrong?
      assert grade(check, %w[t3], map).wrong?
    end
  end

  test "select on a type with no targets yet: every response is unreadable, never guessed" do
    check = select_check
    assert_empty Lessons::Checks.id_map(check, "x")
    assert grade(check, %w[t1], {}).invalid?
  end

  # ---- options ---------------------------------------------------------------------------------------------

  NUMBER = { "component" => "number", "prompt_it" => "Quanto?", "answer" => "1115" }.freeze

  test "thousands: a dot that groups exactly three digits is a separator, anything else keeps its old answer" do
    on = NUMBER.merge("thousands" => true)
    assert grade(on, "1.115").right?
    assert grade(on, "1.115,00").right?
    assert grade(on, "1115").right?
    assert grade(NUMBER, "1.115").invalid?, "without the option a dot is still refused"
    assert_equal "thousands_separator", grade(NUMBER, "1.115").code
    assert grade(on, "1.5").invalid?, "a dot decimal is not a thousands dot"
    assert grade(on, "11.15").invalid?
    assert grade(on, "1 115").invalid?
    assert grade(on.merge("answer" => "1115,5"), "1.115,5").right?
  end

  BINARY = { "component" => "normalized_text", "prompt_it" => "Scrivi in binario.", "answer" => "00001101", "profile" => { "name" => "binary", "width" => 8, "leading_zeros" => "required" },
             "errors" => [ { "answer" => "1101", "code" => "padding_missing", "message_it" => "Mancano gli zeri davanti." } ] }.freeze

  test "profile: a binary profile of a lesson check reaches the shared grader (width, leading zeros, the padding error)" do
    assert grade(BINARY, "00001101").right?
    assert grade(BINARY, "0000 1101").right?
    w = grade(BINARY, "1101")
    assert w.wrong?
    assert_equal "padding_missing", w.code
    assert grade(BINARY, "00001111").wrong?
    assert grade(BINARY, "0000110x").invalid?
  end

  test "contractions: en expands the table's contractions on both sides; ambiguous forms stay as typed" do
    Grading::Closed::Contractions.table = JSON.parse(Rails.root.join("test/fixtures/lesson2/contractions_table.json").read).fetch("contractions")
    check = { "component" => "normalized_text", "prompt_it" => "Completa.", "answer" => "I will stay", "contractions" => "en" }
    assert grade(check, "I will stay").right?
    assert grade(check, "I'll stay").right?
    assert grade(check, "i’ll stay").right?, "a curly apostrophe is the same"
    assert grade(check.merge("answer" => "I'll stay"), "I will stay").right?
    assert grade(check.merge("answer" => "He will not go"), "He won't go").right?
    assert grade(check.merge("answer" => "He will not go"), "He wont go").wrong?
    assert grade(check.merge("answer" => "She is here"), "She's here").wrong?, "'s is ambiguous: not expanded"
    assert grade(check.merge("answer" => "They are late"), "They're late").right?
    assert grade(check.merge("answer" => "I cannot go"), "I can't go").right?
    assert grade(check.merge("answer" => "I can not go"), "I can't go").right?
    without = check.merge("contractions" => nil)
    assert grade(without, "I'll stay").wrong?
    coded = check.merge("errors" => [ { "answer" => "I will go", "code" => "en_verb", "message_it" => "Il verbo è un altro." } ])
    assert_equal "en_verb", grade(coded, "I'll go").code
  ensure
    Grading::Closed::Contractions.reset!
  end

  test "an answer that is too long is refused whatever the component" do
    assert grade(TILES, Array.new(300) { |i| "e#{i}" }, {}).invalid?
  end
end
