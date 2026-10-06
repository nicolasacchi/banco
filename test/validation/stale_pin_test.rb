require "test_helper"
require "support/decision_world"

# D-136: a pinned revision that a newer passed revision of the same item replaced.
class StalePinTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  setup { build_decision_world }

  def replace_pinned!
    pinned = ItemRevision.find(@blueprint.pinned_item_revision_ids.first)
    newer = ItemRevision.create!(item: pinned.item, seq: pinned.item.revisions.maximum(:seq) + 1, body_json: pinned.body_json)
    ItemValidation.create!(item_revision: newer, seq: 1, status: "passed")
    [ pinned, newer ]
  end

  test "no stale pin: the gate and status are quiet" do
    assert_empty Approval::BlueprintGate.stale_pins(@blueprint)
  end

  test "a replaced pin is listed by the gate, the reasons and status" do
    pinned, newer = replace_pinned!
    assert_equal [ { pinned: pinned.id, latest: newer.id } ], Approval::BlueprintGate.stale_pins(@blueprint)
    assert(Approval::BlueprintGate.check(@blueprint).reasons.any? { |r| r.include?("W-STALE-PIN") })
    row = SubjectStage.for(@subject)[:blueprint]
    assert_equal [ { pinned: pinned.id, latest: newer.id } ], row[:stale_pins]
  end

  test "the info of the older revision names the latest passed one" do
    pinned, newer = replace_pinned!
    assert_equal newer.id, Validation::ItemInfo.for(pinned).latest_passed_id
  end
end
