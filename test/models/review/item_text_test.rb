require "test_helper"
require "support/grading_rows"

class Review::ItemTextTest < ActiveSupport::TestCase
  include GradingRows

  setup do
    body = item_body("short-answer").merge("generator" => "generator.mjs")
    first = create_instance(body, { "display" => { "stem_it" => "Uno" }, "answer" => "1" })
    @revision = first.item_revision
    (2..24).each do |n|
      ItemInstance.create!(item_revision: @revision, seed: 100 + n, display_json: { stem_it: "N#{n}" }.to_json,
                           answer_json: n.to_json, errors_json: "[]", fingerprint: SecureRandom.hex(32))
    end
  end

  test "the solver sees 8 instances of a generator item, the reviewer all of the pool (D-133)" do
    assert_equal 8, Review::ItemText.new(@revision).review_instances.size
    all = Review::ItemText.new(@revision, all: true).review_instances
    assert_equal 24, all.size
    assert_equal (1..24).to_a, all.map { |i| i[:instance] }
  end

  test "the reviewer sees each instance's accept list when stored, and none when not" do
    ItemInstance.create!(item_revision: @revision, seed: 999, display_json: { stem_it: "Acc" }.to_json, answer_json: "\"it is\"".to_json,
                         errors_json: "[]", accept_json: [ "it's" ].to_json, fingerprint: SecureRandom.hex(32))
    all = Review::ItemText.new(@revision, all: true).review_instances
    assert_equal [ "it's" ], all.last[:accept]
    assert_not all.first.key?(:accept)
  end

  test "the solver and the reviewer see the item's own prompt, as the student does (D-169)" do
    body = item_body("short-answer").merge("prompt" => { "stem_it" => "Ordina in senso crescente.", "quote" => "Q" })
    instance = create_instance(body, { "display" => { "elements" => [ { "id" => "e1", "text" => "1" } ] }, "answer" => [ "e1" ] })
    text = Review::ItemText.new(instance.item_revision)
    shown = text.solver_instances.first[:display]
    assert_equal "Ordina in senso crescente.", shown["stem_it"]
    assert_equal "Q", shown["quote"]
    assert_equal shown, text.review_instances.first[:display]
  end

  test "an instance stem stays, and the prompt stem is added beside it (D-169)" do
    body = item_body("short-answer").merge("prompt" => { "stem_it" => "Ordina." })
    instance = create_instance(body, { "display" => { "stem_it" => "Calcola 2+2" }, "answer" => "4" })
    shown = Review::ItemText.new(instance.item_revision).solver_instances.first[:display]
    assert_equal "Calcola 2+2", shown["stem_it"]
    assert_equal "Ordina.", shown["prompt_stem_it"]
  end
end
