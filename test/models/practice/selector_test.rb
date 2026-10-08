require "test_helper"
require_relative "../../support/practice_world"

# Serving (A8.7) with real rows: the open serve, Prova questo, after the solution, progress through the
# pinned items, re-seen instances, bad follows.
class PracticeSelectorTest < ActiveSupport::TestCase
  include PracticeWorld

  setup { build_practice_world }

  test "the first serve is the first pinned item, reason next, with a seed and the rules version" do
    choice = serve!
    assert_equal [ "next", true ], [ choice.reason, choice.created ]
    assert_equal @revisions.first.id, choice.instance.item_revision_id
    assert_equal [ "practice/1", @skill, @student.id, @clock.now ], choice.serve.then { |s| [ s.rules_version, s.skill_key, s.student_id, s.created_at ] }
    assert_kind_of Integer, choice.serve.seed
    assert_nil choice.parent_serve_id
    assert_nil choice.error_code
  end

  test "the first instance of an item is the first by sha256(student:fingerprint)" do
    choice = serve!
    expected = @revisions.first.instances.min_by { |i| Digest::SHA256.hexdigest("#{@student.id}:#{i.fingerprint}") }
    assert_equal expected.id, choice.instance.id
  end

  test "an open serve is returned as it is, whatever follow says" do
    first = serve!
    again = serve!
    assert_equal [ first.serve.id, false ], [ again.serve.id, again.created ]
    assert_equal 1, PracticeServe.count
    assert_equal first.serve.id, serve!.serve.id
  end

  test "an open serve is returned even after hints and a wrong first try" do
    first = serve!
    answer!(first, wrong_raw)
    assert_equal first.serve.id, serve!.serve.id
  end

  test "a closed serve gives a new one, and an abandoned serve too (24 hours)" do
    first = serve!
    advance(24 * 3600 + 1)
    second = serve!
    assert_not_equal first.serve.id, second.serve.id
    assert second.created
  end

  test "an answered serve gives the next instance; no fingerprint repeats until the pool is gone" do
    seen = []
    24.times do
      choice = serve!
      assert_equal "next", choice.reason
      seen << choice.instance.fingerprint
      answer!(choice, wrong_raw) # wrong, then closed by a second wrong below
      answer!(choice, wrong_raw)
    end
    assert_equal 24, seen.uniq.size
    twenty_fifth = serve!
    assert_equal "reseen", twenty_fifth.reason
    assert_includes seen, twenty_fifth.instance.fingerprint
  end

  test "reseen picks the instance whose last serve is the oldest" do
    24.times do
      choice = serve!
      answer!(choice, correct_raw(choice))
    end
    oldest = PracticeServe.order(:id).first
    assert_equal oldest.item_instance_id, serve!.instance.id
  end

  test "after two correct unaided answers on an item the next item is served" do
    two = correct_serves!(2)
    assert_equal [ @revisions.first.id ] * 2, two.map { |s| s.item_instance.item_revision_id }
    third = serve!
    assert_equal @revisions.second.id, third.instance.item_revision_id
  end

  test "wrong or aided answers do not advance the item" do
    3.times do
      c = serve!
      answer!(c, wrong_raw)
      answer!(c, correct_raw(c)) # aided by rule: does not count
    end
    assert_equal @revisions.first.id, serve!.instance.item_revision_id
  end

  test "when every item has its credits the item served least recently comes next" do
    4.times { c = serve!; answer!(c, correct_raw(c)) }
    # item 1 served first (ids 1,2), item 2 next (3,4); now both have 2 credits: item 1 was served least recently
    fifth = serve!
    assert_equal @revisions.first.id, fifth.instance.item_revision_id
    answer!(fifth, correct_raw(fifth))
    sixth = serve!
    assert_equal @revisions.second.id, sixth.instance.item_revision_id
  end

  test "when an item has no unseen instance the next pinned item is used" do
    pin_items(2, 2)
    seen = Array.new(3) { c = serve!; answer!(c, wrong_raw); answer!(c, wrong_raw); c.instance.item_revision_id }
    assert_equal [ @revisions.first.id, @revisions.first.id, @revisions.second.id ], seen
  end

  test "an unpinned skill and an empty pool are refused" do
    assert_raises(Practice::Selector::NotPinned) { serve!(skill: "math.other") }
  end

  # ---- Prova questo and after the solution ----

  def typical_serve!
    c = serve!
    answer!(c, slip_raw(c))
    c
  end

  test "Prova questo serves an unseen instance whose errors carry the code, reason prova_questo, parent set" do
    pin_items(2, 6)
    # item 1: even instances carry "slip", odd ones carry "other"; item 2: all "slip"
    first = typical_serve!
    follow = { serve_id: first.serve.id, kind: "prova_questo" }
    next_choice = serve!(follow: follow)
    assert_equal [ "prova_questo", "slip", first.serve.id ], [ next_choice.reason, next_choice.error_code, next_choice.parent_serve_id ]
    assert_includes JSON.parse(next_choice.instance.errors_json).map { |e| e["code"] }, "slip"
    assert_not_equal first.instance.fingerprint, next_choice.instance.fingerprint
    assert_equal first.instance.item_revision_id, next_choice.instance.item_revision_id
  end

  test "Prova questo prefers the same item, then another pinned item, then falls back to next" do
    errors = { 0 => [ [ { code: "a_only", value: "9" } ], [ { code: "shared", value: "9" } ], [ { code: "shared", value: "9" } ] ],
               1 => [ [ { code: "shared", value: "9" } ], [ { code: "b_only", value: "9" } ] ] }
    catalogue = %w[a_only shared b_only].map { |c| { code: c, message_it: "Messaggio." } }
    @revisions = [ make_practice_item("math-q-1", @skill, instances: 3, errors: ->(i) { errors[0][i] }, catalogue: catalogue),
                   make_practice_item("math-q-2", @skill, instances: 2, errors: ->(i) { errors[1][i] }, catalogue: catalogue) ]
    @topic = make_topic(@lesson_revision, { @skill => @revisions })
    # several students: the order inside an item depends on the student, so the first instance (and its code) varies
    8.times { |n| prova_questo_case(practice_student("prova-#{n}")) }
  end

  def prova_questo_case(student)
    first = serve!(student: student)
    code = JSON.parse(first.instance.errors_json).first["code"]
    answer!(first, "9", student: student)
    choice = serve!(student: student, follow: { serve_id: first.serve.id, kind: "prova_questo" })
    carrying = ->(rev) { rev.instances.reject { |i| i.id == first.instance.id }.select { |i| JSON.parse(i.errors_json).any? { |e| e["code"] == code } } }
    if code == "shared"
      assert_equal [ "prova_questo", "shared" ], [ choice.reason, choice.error_code ]
      assert_includes JSON.parse(choice.instance.errors_json).map { |e| e["code"] }, "shared"
      # item 1 still has an unseen shared instance when the first one was the other of its two: same item preferred
      assert_equal first.instance.item_revision_id, choice.instance.item_revision_id if carrying.(first.instance.item_revision).any?
      assert_equal @revisions.second.id, choice.instance.item_revision_id unless carrying.(first.instance.item_revision).any?
    else
      assert_equal [ "next", first.serve.id ], [ choice.reason, choice.parent_serve_id ]
      assert_nil choice.error_code
    end
    assert_equal first.serve.id, choice.parent_serve_id
  end

  test "After the solution serves an unseen instance of the same item revision" do
    first = typical_serve!
    actions.solution(serve_id: first.serve.id)
    choice = serve!(follow: { serve_id: first.serve.id, kind: "after_solution" })
    assert_equal [ "after_solution", first.serve.id, nil ], [ choice.reason, choice.parent_serve_id, choice.error_code ]
    assert_equal first.instance.item_revision_id, choice.instance.item_revision_id
    assert_not_equal first.instance.id, choice.instance.id
  end

  test "After the solution falls back to next when the item has no unseen instance" do
    pin_items(2, 1)
    first = serve!
    answer!(first, wrong_raw)
    answer!(first, wrong_raw) # closed, solution sent
    choice = serve!(follow: { serve_id: first.serve.id, kind: "after_solution" })
    assert_equal [ "next", first.serve.id, @revisions.second.id ], [ choice.reason, choice.parent_serve_id, choice.instance.item_revision_id ]
  end

  test "bad follows: an open serve, a serve that does not allow it, another student's, another skill, an unknown kind or serve" do
    open = serve!
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: open.serve.id, kind: "prova_questo" }) }
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: open.serve.id, kind: "after_solution" }) }
    answer!(open, correct_raw(open))
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: open.serve.id, kind: "prova_questo" }) }
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: open.serve.id, kind: "after_solution" }) }
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: open.serve.id, kind: "skip" }) }
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: 0, kind: "after_solution" }) }
    other = practice_student("trial-one")
    mine = serve!
    answer!(mine, slip_raw(mine))
    assert_raises(Practice::Selector::BadFollow) { serve!(student: other, follow: { serve_id: mine.serve.id, kind: "prova_questo" }) }
    assert_equal 2, PracticeServe.where(student: @student).count
  end

  test "a bad follow writes nothing" do
    c = serve!
    answer!(c, correct_raw(c))
    before = PracticeServe.count
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: c.serve.id, kind: "prova_questo" }) }
    assert_equal before, PracticeServe.count
  end

  test "Prova questo is refused after a wrong that was not typical" do
    c = serve!
    answer!(c, wrong_raw)
    answer!(c, wrong_raw)
    assert_raises(Practice::Selector::BadFollow) { serve!(follow: { serve_id: c.serve.id, kind: "prova_questo" }) }
    choice = serve!(follow: { serve_id: c.serve.id, kind: "after_solution" })
    assert_equal "after_solution", choice.reason
  end

  test "students are independent: the same pool, another student, another first instance order" do
    mine = serve!
    other = practice_student("trial-two")
    theirs = serve!(student: other)
    assert_not_equal mine.serve.id, theirs.serve.id
    assert_equal 2, PracticeServe.count
  end

  test "choice-component items are re-keyed at serve time and the map is stored" do
    rev = make_practice_item("math-choice", @skill, instances: 0, component: "choice")
    options = [ { "id" => "o1", "text_it" => "uno" }, { "id" => "o2", "text_it" => "due" }, { "id" => "o3", "text_it" => "tre" }, { "id" => "o4", "text_it" => "quattro" } ]
    ItemInstance.create!(item_revision: rev, seed: 1, display_json: JSON.generate(stem_it: "Scegli", options: options), answer_json: JSON.generate("o2"),
                         errors_json: "[]", hints_json: JSON.generate([ "a", "b" ]), solution_json: "{}", fingerprint: "choice-fp")
    topic = make_topic(@lesson_revision, { @skill => [ rev ] })
    c = serve!(topic: topic)
    map = JSON.parse(c.serve.id_map_json)
    assert_equal %w[o1 o2 o3 o4], map.keys.sort
    assert_equal %w[o1 o2 o3 o4], map.values.sort
    assert_equal map.keys.sort, JSON.parse(c.serve.shown_order_json).fetch("options").size.times.map { |i| "o#{i + 1}" }
  end
end
