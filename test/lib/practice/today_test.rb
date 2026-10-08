require "test_helper"
require_relative "../../support/practice_engine_helper"

# Oggi (A8.8) and the graph order it uses.
class PracticeTodayTest < ActiveSupport::TestCase
  include PracticeEngineHelper

  Subject = Struct.new(:key, :position)
  View = Struct.new(:subject, :topics)
  Topic = Struct.new(:key, :skills, :after)

  def state(skill, name) = Practice::SkillState.new(skill: skill, state: name, since: nil, demonstrated_at: nil, consolidated_at: nil, seed: nil, counts: {}, why: {})

  def topic(key, *skills, after: []) = Topic.new(key, skills, after)

  def catalog(*views) = views

  def math = Subject.new("math", 1)
  def italian = Subject.new("italian", 2)

  def call(catalog, states = {}, order: {}, last: nil)
    Practice::Today.call(catalog: catalog, states: states, graph_order: order, last_topic: last)
  end

  test "graph order is Kahn with ties by key, and ignores prerequisites of other subjects" do
    order = Practice::GraphOrder.call([ { "key" => "math.c", "prerequisites" => [ "math.a", "math.b" ] }, { "key" => "math.b", "prerequisites" => [ "math.a" ] },
                                        { "key" => "math.a", "prerequisites" => [ "italian.x" ] }, { "key" => "math.z", "prerequisites" => [] } ])
    assert_equal %w[math.a math.b math.c math.z], order.sort_by { |_, v| v }.map(&:first)
  end

  test "graph order puts a cycle last instead of looping" do
    order = Practice::GraphOrder.call([ { "key" => "a", "prerequisites" => [ "b" ] }, { "key" => "b", "prerequisites" => [ "a" ] }, { "key" => "c", "prerequisites" => [] } ])
    assert_equal %w[c a b], order.sort_by { |_, v| v }.map(&:first)
  end

  test "to_recover first, then to_learn, then to_review, then the course order; each with its reason" do
    cat = catalog(View.new(math, [ topic("t1", "math.a"), topic("t2", "math.b"), topic("t3", "math.c"), topic("t4", "math.d") ]))
    states = { "math.b" => state("math.b", "to_learn"), "math.c" => state("math.c", "to_review"), "math.d" => state("math.d", "to_recover") }
    out = call(cat, states, order: { "math.a" => 0, "math.b" => 1, "math.c" => 2, "math.d" => 3 })
    assert_equal [ %w[t4 to_recover math.d], %w[t2 to_learn math.b], %w[t3 to_review math.c] ], out[:suggestions].map { |s| [ s.topic_key, s.reason.to_s, s.skill ] }
  end

  test "at most three suggestions, and the remaining topics come in course order with reason course_next" do
    cat = catalog(View.new(math, (1..6).map { |i| topic("t#{i}", "math.s#{i}") }))
    out = call(cat)
    assert_equal %w[t1 t2 t3], out[:suggestions].map(&:topic_key)
    assert(out[:suggestions].all? { |s| s.reason == :course_next && s.skill.nil? })
  end

  test "within a reason the graph position of the skill orders the topics, then the course order" do
    cat = catalog(View.new(math, [ topic("t1", "math.late"), topic("t2", "math.early"), topic("t3", "math.early2") ]))
    states = %w[math.late math.early math.early2].to_h { |k| [ k, state(k, "to_recover") ] }
    out = call(cat, states, order: { "math.early" => 0, "math.early2" => 0, "math.late" => 5 })
    assert_equal %w[t2 t3 t1], out[:suggestions].map(&:topic_key)
  end

  test "subjects are interleaved round robin by position" do
    cat = catalog(View.new(italian, [ topic("i1", "italian.a"), topic("i2", "italian.b") ]), View.new(math, [ topic("m1", "math.a"), topic("m2", "math.b") ]))
    states = %w[italian.a italian.b math.a math.b].to_h { |k| [ k, state(k, "to_recover") ] }
    out = call(cat, states, order: { "italian.a" => 0, "italian.b" => 1, "math.a" => 0, "math.b" => 1 })
    assert_equal %w[m1 i1 m2], out[:suggestions].map(&:topic_key)
  end

  test "Riprendi is the last topic when visible and not done, and is left out of the suggestions" do
    cat = catalog(View.new(math, [ topic("t1", "math.a"), topic("t2", "math.b") ]))
    out = call(cat, {}, last: "t1")
    assert_equal "t1", out[:resume]
    assert_equal %w[t2], out[:suggestions].map(&:topic_key)
  end

  test "a done last topic is not resumed, an unknown one neither" do
    cat = catalog(View.new(math, [ topic("t1", "math.a"), topic("t2", "math.b") ]))
    done = { "math.a" => state("math.a", "demonstrated") }
    assert_nil call(cat, done, last: "t1")[:resume]
    assert_equal %w[t2], call(cat, done, last: "t1")[:suggestions].map(&:topic_key)
    assert_nil call(cat, {}, last: "ghost")[:resume]
    assert_nil call(cat, {}, last: nil)[:resume]
  end

  test "consolidated also counts as done; a topic needs every skill done" do
    t = topic("t1", "math.a", "math.b")
    assert Practice::Today.done?(t, { "math.a" => state("math.a", "demonstrated"), "math.b" => state("math.b", "consolidated") })
    assert_not Practice::Today.done?(t, { "math.a" => state("math.a", "demonstrated") })
    assert_not Practice::Today.done?(t, { "math.a" => state("math.a", "demonstrated"), "math.b" => state("math.b", "to_review") })
  end

  test "skills to recover with no visible topic are never suggested" do
    cat = catalog(View.new(math, [ topic("t1", "math.a") ]))
    out = call(cat, { "math.orphan" => state("math.orphan", "to_recover") })
    assert_equal %w[t1], out[:suggestions].map(&:topic_key)
    assert_equal :course_next, out[:suggestions].first.reason
  end

  test "an empty catalog gives nothing" do
    assert_equal({ resume: nil, suggestions: [] }, call([]))
  end

  test "topic status and the recover tag" do
    t = topic("t1", "math.a")
    assert_equal :todo, Practice::Today.status(t, {}, started: false)
    assert_equal :in_progress, Practice::Today.status(t, {}, started: true)
    assert_equal :done, Practice::Today.status(t, { "math.a" => state("math.a", "consolidated") }, started: true)
    assert Practice::Today.recover_tag?(t, { "math.a" => state("math.a", "to_review") })
    assert Practice::Today.recover_tag?(t, { "math.a" => state("math.a", "to_recover") })
    assert_not Practice::Today.recover_tag?(t, { "math.a" => state("math.a", "to_learn") })
  end

  test "Prima conviene fare names the first after-topic that is visible and not done" do
    t1 = topic("t1", "math.a")
    t2 = topic("t2", "math.b")
    t3 = topic("t3", "math.c", after: [ "gone", "t1", "t2" ])
    visible = { "t1" => t1, "t2" => t2, "t3" => t3 }
    assert_equal t1, Practice::Today.before(t3, visible, {})
    assert_equal t2, Practice::Today.before(t3, visible, { "math.a" => state("math.a", "demonstrated") })
    assert_nil Practice::Today.before(t3, visible, { "math.a" => state("math.a", "demonstrated"), "math.b" => state("math.b", "demonstrated") })
  end
end
