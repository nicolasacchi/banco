require "test_helper"

# Serve-time re-keying (X-01): shuffled, fresh ids in shown order, an id map back to
# the stored ids, and never a key-order ordering.
class RekeyTest < ActiveSupport::TestCase
  CHOICE = { "options" => (1..4).map { |n| { "id" => "o#{n}", "text" => "T#{n}" } } }.freeze
  ORDERING = { "elements" => (1..5).map { |n| { "id" => "e#{n}", "text" => "E#{n}" } } }.freeze
  MATCHING = { "left" => (1..4).map { |n| { "id" => "l#{n}", "text" => "L#{n}" } },
               "right" => (1..5).map { |n| { "id" => "r#{n}", "text" => "R#{n}" } } }.freeze
  KEY = %w[e1 e2 e3 e4 e5].freeze
  PAIRS = { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r4" }.freeze

  def rekey(display, component, answer, seed) = Diagnosis::Rekey.call(display: display, component: component, answer: answer, seed: seed)

  test "choice options keep their text, get fresh ids in shown order and a map back" do
    r = rekey(CHOICE, "choice", "o1", "s1")
    assert_equal %w[o1 o2 o3 o4], r.display["options"].map { |o| o["id"] }
    assert_equal %w[T1 T2 T3 T4], r.display["options"].map { |o| o["text"] }.sort
    r.display["options"].each { |o| assert_equal "T#{r.id_map.fetch(o['id'])[1]}", o["text"] }
    assert_equal r.shown_order["options"], r.display["options"].map { |o| r.id_map[o["id"]] }
  end

  test "the same seed gives the same shuffle and replay rebuilds it from the logged order" do
    a = rekey(CHOICE, "choice", "o1", "same")
    b = rekey(CHOICE, "choice", "o1", "same")
    assert_equal a, b
    assert_equal a.display, Diagnosis::Rekey.replay(display: CHOICE, component: "choice", shown_order: a.shown_order)
  end

  test "different seeds do not all give the same order" do
    orders = (1..30).map { |n| rekey(CHOICE, "choice", "o1", "seed-#{n}").shown_order["options"] }
    assert_operator orders.uniq.size, :>, 5
  end

  test "an ordering is never shown in key order, in its reverse or in its stored listing" do
    200.times do |n|
      r = rekey(ORDERING, "ordering", KEY, "seed-#{n}")
      shown = r.shown_order["elements"]
      refute_equal KEY, shown
      refute_equal KEY.reverse, shown
      assert_equal KEY.sort, shown.sort
      assert_equal %w[e1 e2 e3 e4 e5], r.display["elements"].map { |e| e["id"] }
    end
  end

  test "an ordering is never shown as a declared error permutation" do
    declared = [ %w[e2 e1 e3 e4 e5], %w[e1 e2 e4 e3 e5], %w[e3 e1 e2 e4 e5] ]
    errors = declared.each_with_index.map { |v, i| { "code" => "err_#{i}", "value" => v } }
    300.times do |n|
      shown = Diagnosis::Rekey.call(display: ORDERING, component: "ordering", answer: KEY, seed: "seed-#{n}", errors: errors).shown_order["elements"]
      refute_includes declared, shown
    end
  end

  test "a testlet sub item ordering avoids its declared error permutations" do
    errors = [ { "code" => "c", "value" => %w[e2 e1 e3 e4 e5] } ]
    200.times do |n|
      sub = { "id" => "q1", "component" => "ordering", "display" => ORDERING, "answer" => KEY, "errors" => errors }
      shown = Diagnosis::Rekey.testlet([ sub ], seed: "t-#{n}").shown_order["q1"]["elements"]
      refute_equal %w[e2 e1 e3 e4 e5], shown
    end
  end

  test "matching columns are both shuffled, and the rows never line up with the pairs" do
    200.times do |n|
      r = rekey(MATCHING, "matching", PAIRS, "seed-#{n}")
      left = r.shown_order["left"]
      right = r.shown_order["right"]
      refute_equal %w[l1 l2 l3 l4], left
      refute_equal %w[r1 r2 r3 r4 r5], right
      refute left.each_with_index.all? { |l, i| PAIRS[l] == right[i] }
      assert_equal %w[l1 l2 l3 l4 r1 r2 r3 r4 r5], r.id_map.values.sort
      assert_equal 9, r.id_map.size
    end
  end

  test "the shown ids carry the shown position only" do
    r = rekey(MATCHING, "matching", PAIRS, "x")
    assert_equal %w[l1 l2 l3 l4], r.display["left"].map { |e| e["id"] }
    assert_equal %w[r1 r2 r3 r4 r5], r.display["right"].map { |e| e["id"] }
  end

  test "other components pass through untouched" do
    display = { "stem_it" => "x" }
    r = rekey(display, "number", "3", "s")
    assert_equal display, r.display
    assert_empty r.id_map
  end

  test "a testlet re-keys each sub item on its own" do
    subs = (1..2).map { |n| { "id" => "q#{n}", "component" => "choice", "display" => CHOICE, "answer" => "o1" } }
    r = Diagnosis::Rekey.testlet(subs, seed: "t")
    assert_equal %w[q1 q2], r.id_map.keys
    assert_equal %w[q1 q2], r.display["sub_items"].map { |s| s["id"] }
    assert_equal 4, r.id_map["q1"].size
  end
end
