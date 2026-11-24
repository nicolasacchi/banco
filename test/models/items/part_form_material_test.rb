require "test_helper"

# D-402: an exercise that tests a FORM keeps its material target-only: the instance sentence, the options or rows that are forms and the `final` have no `_it`.
# The golden items (test/fixtures/lang/item_form_*.json, served as test/fixtures/lang/served_item_form.json) are served with the instruction, the steps, the
# format, the hints and the solution steps in both languages, and the material in the target language alone. The browser draws exactly that
# (test/javascript/items/bilingual.test.mjs).
class ItemsPartFormMaterialTest < ActiveSupport::TestCase
  Subject = Struct.new(:key)
  Revision = Struct.new(:body_json)
  Instance = Struct.new(:item_revision, :hints_json, :solution_json, :display_json, :answer_json, :accept_json)

  SERVED = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/served_item_form.json")))

  def item(name) = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/item_form_#{name}.json")))

  def json(value) = JSON.parse(value.to_json)

  SERVED.each_key do |name|
    test "the golden form-material #{name} item is served with a target-only material" do
      body = item(name)
      display = body["instances"][0]["display"]
      part = Items::Part.new(subject: Subject.new("english")).call(body, body["component"], display)
      assert_equal SERVED[name]["part"], json(part)
      assert_equal "en", part[:lang]
      assert_nil part[:instance_stem_it], "the sentence is material"
      assert(%i[options left].filter_map { |k| part[k] }.flatten.none? { |entry| entry.key?("text_it") }, "the forms and rows are material")

      instance = Instance.new(Revision.new(JSON.generate(body.except("instances"))), nil, JSON.generate(body["instances"][0]["solution"]), JSON.generate(display))
      assert_equal SERVED[name]["hint"], json(Practice::Payload.hint(instance, 1))
      solution = json(Practice::Payload.solution(instance))
      assert_equal SERVED[name]["solution"], solution
      assert_not solution.key?("final_it"), "the final is material"
      assert(solution["steps"].all? { |step| step["text_it"].present? }, "the solution steps keep their Italian")
    end
  end

  test "the matching's verdict labels are not material: they keep their Italian" do
    right = SERVED["matching"]["part"]["right"]
    assert_equal %w[giusta ha\ un\ errore], right.map { |label| label["text_it"] }
  end
end
