require "test_helper"
require_relative "../../support/student_ui_rows"

# A testlet has no component of its own: the loader decides per skill from the
# sub items (D-096), so a testlet of choice sub items is neither hard to guess nor
# a number item (D-099 serves a passage once per run).
class PlanLoaderTestletTest < ActiveSupport::TestCase
  include StudentUiRows

  test "a testlet of choice sub items is a choice instance and not low-guess" do
    rows = build_ui_subject(components: %w[number testlet])
    plan = Diagnosis::PlanLoader.for_blueprint_revision(rows[:blueprint])
    skill = skill_key("math", "testlet")
    testlets = plan.instances_for(skill).select(&:testlet?)
    assert testlets.any?
    testlets.each do |i|
      assert_not i.low_guess_for(skill), "choice sub items are easy to guess"
      assert i.choice_for(skill)
    end
  end
end
