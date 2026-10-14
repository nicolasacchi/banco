# frozen_string_literal: true

require "test_helper"

# A select check serves, draws and describes its own target set (not the first set the figure happens to have): a map that has areas and
# places, a check that taps the places.
class LessonsSelectSetTest < ActiveSupport::TestCase
  DOC = JSON.parse(Rails.root.join("test/fixtures/diagrams/types/map.json").read)
  VECTOR = DOC["vectors"].find { |v| v["name"] == "map-south-america-core" }

  def check(set) = { "component" => "select", "prompt_it" => "Tocca.", "targets" => set, "pick" => "many", "answer" => [ VECTOR["targets"][set].first ], "diagram" => VECTOR["data"] }

  test "a map select check serves the set the check targets, areas or places" do
    %w[areas places].each do |set|
      served = Lessons::StudentBody.check(check(set), "geography", "s1")["diagram"]
      assert_equal VECTOR["served_select"][set], served, "served #{set}"
    end
    places = Lessons::StudentBody.check(check("places"), "geography", "s1")["diagram"]
    assert_equal VECTOR["targets"]["places"].size, places["places"].size
    assert_nil places["candidates"], "the places figure carries no area candidates"
  end

  test "every figure type with a set-aware served projection receives the check's set" do
    seen = []
    mod = Lessons::Diagrams::Map
    original = mod.method(:served)
    mod.define_singleton_method(:served) { |data, mode: :student, set: nil| seen << set; original.call(data, mode: mode, set: set) }
    begin
      Lessons::StudentBody.check(check("places"), "geography", "s1")
    ensure
      mod.singleton_class.send(:remove_method, :served)
      mod.define_singleton_method(:served, original)
    end
    assert_equal [ "places" ], seen
  end

  test "a timeline select figure counts the targets of the check's set" do
    data = { "type" => "timeline", "scale" => "years", "from" => 0, "to" => 100,
             "events" => [ { "id" => "e1", "at" => 10, "label_it" => "A" }, { "id" => "e2", "at" => 20, "label_it" => "B" } ],
             "periods" => [ { "from" => 30, "to" => 60, "label_it" => "P" } ] }
    assert_match(/\b2 punti/, Lessons::Diagrams::Timeline.served(data, mode: :select, set: "events")["alt_it"])
    assert_match(/\b1 punti/, Lessons::Diagrams::Timeline.served(data, mode: :select, set: "periods")["alt_it"])
  end
end
