require "test_helper"
require_relative "../../support/diagnosis_helper"

# D-297: an item served again in a run shows the instance least alike the ones already served.
class DiagnosisOverlapTest < ActiveSupport::TestCase
  include DiagnosisHelper

  A = "math.a".freeze

  def texts(strong, weak = [])
    { strong: strong, weak: weak }
  end

  # One item "x" with four instances; texts_by_position gives, by position in the plan's
  # order, the texts of each. Returns the plan and the instances in plan order.
  def plan_with(texts_by_position)
    base = build_plan(skills: { A => {} }, items: { A => %w[x] }, pool: { "x" => { "instances" => 0, "component" => "matching" } })
    raw = %w[x#1 x#2 x#3 x#4].map { |id| instance(id, skills: [ A ], item: "x", component: "matching") }
    order = with_instances(base, raw).instances_for(A)
    marked = order.each_with_index.map { |inst, n| inst.with(texts: texts_by_position[n]) }
    [ with_instances(base, marked), marked ]
  end

  def play_wrong_then_next(plan)
    d = DiagnosisHelper::Driver.new(plan)
    d.start
    first = d.play("wrong")
    [ first, d.action ]
  end

  test "a repeat picks the instance with the fewest texts in common with the one served" do
    plan, order = plan_with([ texts(%w[a b c]), texts(%w[a b c]), texts(%w[x y z]), texts(%w[a y z]) ])
    first, second = play_wrong_then_next(plan)
    assert_equal order[0].id, first.instance.id
    assert_equal :serve, second.type
    assert_equal order[2].id, second.instance.id
  end

  test "equal overlaps keep the plan order" do
    plan, order = plan_with([ texts(%w[a b]), texts(%w[a c]), texts(%w[a d]), texts(%w[a e]) ])
    _, second = play_wrong_then_next(plan)
    assert_equal order[1].id, second.instance.id
  end

  test "instances without texts keep the plan order" do
    plan, order = plan_with([ nil, nil, nil, nil ])
    _, second = play_wrong_then_next(plan)
    assert_equal order[1].id, second.instance.id
  end

  test "stem and rows weigh more than a repeated right column" do
    plan, order = plan_with([ texts(%w[a], %w[r1 r2 r3]), texts(%w[b], %w[r1 r2 r3]), texts(%w[a], %w[q1 q2 q3]), texts(%w[a], %w[q1]) ])
    _, second = play_wrong_then_next(plan)
    # order[1] shares three weak texts (3); order[2] and order[3] share one strong text (2): order[2] comes first
    assert_equal order[2].id, second.instance.id
  end

  test "the overlap counts every instance of the item already served" do
    first = instance("x#1", skills: [ A ], item: "x").with(texts: texts(%w[a b]))
    second = instance("x#2", skills: [ A ], item: "x").with(texts: texts(%w[c d]))
    near_first = instance("x#3", skills: [ A ], item: "x").with(texts: texts(%w[a b]))
    near_both = instance("x#4", skills: [ A ], item: "x").with(texts: texts(%w[e f]))
    got = Diagnosis::Overlap.least_alike([ near_first, near_both ], [ first, second ])
    assert_equal "x#4", got.id
  end

  test "another item is never swapped in" do
    other = instance("y#1", skills: [ A ], item: "y").with(texts: texts(%w[zzz]))
    cand = instance("x#2", skills: [ A ], item: "x").with(texts: texts(%w[a]))
    served = instance("x#1", skills: [ A ], item: "x").with(texts: texts(%w[a]))
    assert_equal "x#2", Diagnosis::Overlap.least_alike([ cand, other ], [ served ]).id
  end

  test "InstanceTexts normalizes, puts the right column apart and reads a testlet's sub items" do
    display = { "stem_it" => "  Abbina.  ", "left" => [ { "id" => "l1", "text" => "Roma" } ],
                "right" => [ { "id" => "r1", "text" => "ROMA" }, { "id" => "r2", "text" => "Antica" } ] }
    t = Diagnosis::InstanceTexts.call(display)
    assert_equal %w[abbina roma], t[:strong]
    assert_equal %w[antica], t[:weak]
    tl = Diagnosis::InstanceTexts.call("passage_it" => "Testo", "sub_items" => [ { "display" => { "options" => [ { "text" => "Uno." } ] } } ])
    assert_equal %w[testo uno], tl[:strong]
  end
end
