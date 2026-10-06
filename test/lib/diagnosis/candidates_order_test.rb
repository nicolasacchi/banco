require "test_helper"

class CandidatesOrderTest < ActiveSupport::TestCase
  test "entry items order decides which low-guess item is served first" do
    bp = { "subject" => "spanish", "entries" => [ { "skill" => "spanish.x", "items" => %w[403 656] } ] }
    plan = Diagnosis::Plan.build(blueprint: bp)
    assert_equal %w[403 656], plan.entry("spanish.x").items
    state = Diagnosis::State.new(plan) if Diagnosis.const_defined?(:State)
    skip "State not constructible here" unless state
    got = Diagnosis::Candidates.for(state, "spanish.x", :first).map(&:item)
    assert_equal "403", got.first
    rev = Diagnosis::Plan.build(blueprint: bp.merge("entries" => [ { "skill" => "spanish.x", "items" => %w[656 403] } ]))
    assert_equal "656", Diagnosis::Candidates.for(Diagnosis::State.new(rev), "spanish.x", :first).first.item
  end

  test "descent items order decides the served order for a skill without an entry (D-142)" do
    bp = { "subject" => "spanish", "entries" => [ { "skill" => "spanish.x", "items" => %w[1] } ],
           "descent" => [ { "skill" => "spanish.y", "items" => %w[900 100] } ] }
    plan = Diagnosis::Plan.build(blueprint: bp)
    assert_equal %w[900 100], plan.item_order("spanish.y")
    [ "a", "b", "c", "d" ].each do |salt|
      p2 = Diagnosis::Plan.build(blueprint: bp, seed_salt: salt)
      assert_equal "900", Diagnosis::Candidates.for(Diagnosis::State.new(p2), "spanish.y", :first).first.item
    end
  end
end
