require "test_helper"
require "open3"

# W2-0 (WAVE2 1.9): the 15 vetted data tables have their JSON Schemas; the tables themselves are content and arrive with their tracks.
class LessonDataTest < ActiveSupport::TestCase
  TABLES = %w[bio/cell_parts bio/sizes chem/elements chem/molecules chem/substances chem/terms computer_science/program_vb english/contractions english/verbs
              geo/countries geo/names geo/stations history/places network/kinds spanish/verbs].freeze

  # T5 and T6 add tables of their own beside the contract's (D-271): the recipes of the ancient regions, the second table of the places, and
  # the second table of the stations.
  T5_EXTRA = %w[history/places_expected history/regions].freeze
  T6_EXTRA = %w[geo/stations_expected].freeze

  test "the 15 tables of the plan have a schema, each a valid JSON Schema that names its track and says a second table is compared" do
    assert_equal (TABLES + T5_EXTRA + T6_EXTRA).sort, Lessons::VettedData.names
    (TABLES + [ "history/regions" ]).each do |name|
      schema = Lessons::VettedData.schema(name)
      assert JSONSchemer.valid_schema?(schema), name
      meta = Lessons::VettedData.meta(name)
      assert_equal name, meta["name"]
      assert_match(/\AT\d+[ab]?\z/, meta["track"], name)
      assert meta["used_by"].any?, name
      assert_equal true, meta["second_table"], name unless T5_EXTRA.include?(name)
      assert_includes [ 1, 2 ], schema.dig("properties", "version", "const"), name
      assert_equal false, schema["additionalProperties"], name
    end
  end

  test "the schemas hold what the plan says of the rows: sources, the 118 elements, twelve months, six present forms, seven changes of state" do
    assert_equal 118, Lessons::VettedData.schema("chem/elements").dig("properties", "elements", "minItems")
    assert_includes Lessons::VettedData.schema("chem/elements").dig("properties", "elements", "items", "required"), "source"
    assert_equal 12, Lessons::VettedData.schema("geo/stations").dig("properties", "stations", "additionalProperties", "properties", "temp", "minItems")
    assert_equal %w[el ellos nosotros tu vosotros yo], Lessons::VettedData.schema("spanish/verbs").dig("properties", "verbs", "additionalProperties", "properties", "forms", "required").sort
    assert_equal 7, Lessons::VettedData.schema("chem/terms").dig("properties", "changes", "required").size
  end

  test "a schema accepts a small valid table and refuses one that lacks a required member" do
    good = { "version" => 1, "kinds" => { "owes" => { "label_it" => "deve", "icon" => "hand-coins", "arrow" => "solid" } }, "what" => { "goods" => { "label_it" => "merce", "icon" => "package" } } }
    assert_empty Lessons::VettedData.errors("network/kinds", good)
    assert_not_empty Lessons::VettedData.errors("network/kinds", good.merge("kinds" => { "owes" => { "label_it" => "deve" } }))
    assert_not_empty Lessons::VettedData.errors("chem/terms", { "version" => 1, "changes" => {} })
  end

  test "a table that has not been written is nil, the compiler has nothing to do and is clean" do
    TABLES.each do |name|
      next if Lessons::VettedData.written?(name)

      assert_nil Lessons::VettedData.table(name), name
    end
    assert_nil Lessons::VettedData.row("chem/elements", "elements", "H", id_field: "symbol") unless Lessons::VettedData.written?("chem/elements")
    out, status = Open3.capture2e(Rails.root.join("bin/build-lesson-data").to_s, "--check")
    assert status.success?, out
  end
end
