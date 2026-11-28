require "test_helper"
require_relative "../../support/course_rows"

# D-336: one instance as the student's page draws it, shuffled with a fixed seed that the shot states, and nothing the student is not told.
class ItemsShotPresentationTest < ActiveSupport::TestCase
  include CourseRows

  setup do
    build_course
    item = Item.create!(subject: @subject, key: "shot-pres", kind: "diagnosis_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "diagnosis_item", subject: "math", skill: "math.number", component: "choice", expected_seconds: 60,
             prompt: { stem_it: "Quale è pari?" } }
    @revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: @revision, seq: 1, status: "passed", codes_json: "[]")
    2.times do |i|
      options = (1..6).map { |n| { id: "o#{n}", text: "Opzione #{n} #{i}" } }
      ItemInstance.create!(item_revision: @revision, seed: i + 1, display_json: JSON.generate(options: options), answer_json: JSON.generate("o2"),
                           errors_json: JSON.generate([ { code: "pick_o5", value: "o5" } ]), fingerprint: SecureRandom.hex(8))
    end
  end

  test "instances are numbered by id from 1, and a number outside them is none" do
    ids = @revision.instances.order(:id).pluck(:id)
    assert_equal ids.first, Items::ShotPresentation.instance(@revision, 1).id
    assert_equal ids.last, Items::ShotPresentation.instance(@revision, 2).id
    [ 0, 3, -1, nil, "1" ].each { |n| assert_nil Items::ShotPresentation.instance(@revision, n), n.inspect }
  end

  test "the seed is fixed per revision and instance number, so a picture is the same every time, and the shown order is a permutation of the stored ids" do
    one = Items::ShotPresentation.call(@revision, Items::ShotPresentation.instance(@revision, 1), 1)
    again = Items::ShotPresentation.call(@revision, Items::ShotPresentation.instance(@revision, 1), 1)
    two = Items::ShotPresentation.call(@revision, Items::ShotPresentation.instance(@revision, 2), 2)
    assert_equal "item-shots|#{@revision.id}|1", one[:seed]
    assert_equal one, again
    assert_equal %w[o1 o2 o3 o4 o5 o6], one[:shown_order]["options"].sort
    assert_equal one[:shown_order]["options"].map { |id| "Opzione #{id[1]} 0" }, one[:item][:options].map { |o| o["text"] }, "the drawn options are in the shown order"
    refute_equal one[:shown_order], two[:shown_order], "another instance, another seed"
    assert_equal({ "instance" => 1, "seed" => one[:seed], "shown_order" => one[:shown_order] }, Items::ShotPresentation.meta(one))
  end

  test "what the browser is told holds no key, no error value, no hint and no solution, and the frame follows the item's kind" do
    shown = Items::ShotPresentation.call(@revision, Items::ShotPresentation.instance(@revision, 1), 1)
    assert_equal "sitting", shown[:frame]
    assert_equal 0, shown[:hints]
    text = JSON.generate(shown[:item])
    refute_includes text, "pick_o5"
    assert_equal %w[o1 o2 o3 o4 o5 o6], shown[:item][:options].map { |o| o["id"] }.sort, "the options carry ids the shuffle made"
    practice = ItemRevision.create!(item: @revision.item, seq: 2, body_json: JSON.generate(JSON.parse(@revision.body_json).merge("kind" => "practice_item", "hints_it" => %w[a b c])), file_sessions_json: "{}")
    ItemInstance.create!(item_revision: practice, seed: 1, display_json: JSON.generate(options: [ { id: "o1", text: "x" }, { id: "o2", text: "y" } ]), answer_json: JSON.generate("o1"), fingerprint: SecureRandom.hex(8))
    shown = Items::ShotPresentation.call(practice, Items::ShotPresentation.instance(practice, 1), 1)
    assert_equal [ "practice", 3 ], shown.values_at(:frame, :hints)
  end

  # D-410: a short answer with a word range is a writing task; its shot is «Scrivi tu», with the prompt as the student reads it.
  test "a writing task has the writing frame and the prompt of Scrivi tu; a short answer with no word range keeps the sitting frame" do
    body = JSON.parse(@revision.body_json).merge("kind" => "short_answer", "component" => "short_answer", "prompt" => { "stem_it" => "Racconta." }, "answer_format_it" => "Usa il passato.",
                                                 "words_min" => 20, "words_max" => 60)
    writing = ItemRevision.create!(item: @revision.item, seq: 3, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemInstance.create!(item_revision: writing, seed: 1, display_json: JSON.generate(stem_it: "Racconta."), answer_json: "{}", fingerprint: SecureRandom.hex(8))
    shown = Items::ShotPresentation.call(writing, Items::ShotPresentation.instance(writing, 1), 1)
    assert_equal "writing", shown[:frame]
    assert_equal [ "Racconta.", "Usa il passato.", 20, 60 ], shown[:prompt].to_h.values_at(:stem, :format, :words_min, :words_max)
    plain = ItemRevision.create!(item: @revision.item, seq: 4, body_json: JSON.generate(body.except("words_min", "words_max")), file_sessions_json: "{}")
    ItemInstance.create!(item_revision: plain, seed: 1, display_json: JSON.generate(stem_it: "Riassumi."), answer_json: "{}", fingerprint: SecureRandom.hex(8))
    shown = Items::ShotPresentation.call(plain, Items::ShotPresentation.instance(plain, 1), 1)
    assert_equal [ "sitting", nil ], shown.values_at(:frame, :prompt)
  end
end
