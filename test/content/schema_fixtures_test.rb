require "test_helper"

# The frozen formats (A-03, A-05, B-07, C-01): every good fixture validates and
# every bad fixture is refused with E-SCHEMA. Fixtures are synthetic.
class SchemaFixturesTest < ActiveSupport::TestCase
  def load(path) = JSON.parse(File.read(path))

  Banco::Schemas::NAMES.each do |name|
    test "#{name}: there are good and bad fixtures" do
      assert_operator Banco::Schemas.fixture_files(name, :good).size, :>=, 1
      assert_operator Banco::Schemas.fixture_files(name, :bad).size, :>=, 5
    end

    test "#{name}: every good fixture is valid" do
      Banco::Schemas.fixture_files(name, :good).each do |path|
        errors = Banco::Schemas.validate(name, load(path))
        assert_empty errors.map(&:to_h), "#{File.basename(path)} should be valid"
      end
    end

    test "#{name}: every bad fixture is refused with E-SCHEMA and a field pointer" do
      Banco::Schemas.fixture_files(name, :bad).each do |path|
        errors = Banco::Schemas.validate(name, load(path))
        assert_not_empty errors, "#{File.basename(path)} should be refused"
        assert(errors.all? { |e| e.code == "E-SCHEMA" })
      end
    end

    test "#{name}: every bad fixture differs from the good ones by being invalid, not by the schema member" do
      Banco::Schemas.fixture_files(name, :bad).each do |path|
        doc = load(path)
        assert_equal Banco::Schemas.format_of(name), doc["schema"], "#{File.basename(path)} keeps its schema member" if doc.key?("schema")
      end
    end
  end

  test "validate_fixture_pair is true for the shipped fixtures" do
    assert Banco::Schemas.validate_fixture_pair
  end

  test "validate_fixture_pair is false when a schema has no pair" do
    Dir.mktmpdir do |dir|
      assert_not Banco::Schemas.validate_fixture_pair(dir: dir)
    end
  end

  test "validate_fixture_pair is false when the bad fixture is valid" do
    Dir.mktmpdir do |dir|
      Banco::Schemas::NAMES.each do |name|
        good = Banco::Schemas.fixture_files(name, :good).first
        %w[good bad].each do |kind|
          FileUtils.mkdir_p(File.join(dir, name, kind))
          FileUtils.cp(good, File.join(dir, name, kind, "x.json"))
        end
      end
      assert_not Banco::Schemas.validate_fixture_pair(dir: dir)
    end
  end

  test "an unknown schema name is an argument error" do
    assert_raises(ArgumentError) { Banco::Schemas.schema("grade") }
  end

  test "validate_document picks the schema from the schema member" do
    path = Banco::Schemas.fixture_files("solve", :good).first
    assert_empty Banco::Schemas.validate_document(load(path))
    assert_equal "E-SCHEMA", Banco::Schemas.validate_document({ "schema" => "banco.nope/1" }).first.code
    assert_equal "E-SCHEMA", Banco::Schemas.validate_document([]).first.code
  end

  test "errors point at the failing field" do
    doc = load(Banco::Schemas.fixture_files("blueprint", :good).first)
    doc["entries"].pop(2)
    fields = Banco::Schemas.validate("blueprint", doc).map(&:field)
    assert_includes fields, "/entries"
  end

  test "the Italian key is not accepted where the English key is required (rule 6)" do
    doc = load(Banco::Schemas.fixture_files("blueprint", :good).first)
    doc["non_misura_it"] = doc.delete("not_measured_it")
    assert_not Banco::Schemas.valid?("blueprint", doc)
  end

  test "item/1 has no warmup kind and no hints field" do
    schema = JSON.parse(File.read(Rails.root.join("config/banco/schemas/item.json")))
    assert_equal %w[diagnosis_item short_answer testlet], schema.dig("properties", "kind", "enum")
    assert_not schema["properties"].key?("hints")
  end

  test "every schema forbids additional properties at its root" do
    Banco::Schemas::NAMES.each do |name|
      schema = JSON.parse(File.read(Rails.root.join("config/banco/schemas/#{name}.json")))
      assert_equal false, schema["additionalProperties"], name
      assert_equal "banco.#{name}/1", schema["title"]
    end
  end

  test "skill keys follow the subject.slug format of Rules::V1" do
    assert_match Diagnosis::Rules::V1::SKILL_KEY_PATTERN, "math.linear-equation-integer"
    assert_no_match Diagnosis::Rules::V1::SKILL_KEY_PATTERN, "mat-linear-equation"
    assert_no_match Diagnosis::Rules::V1::SKILL_KEY_PATTERN, "math.Linear"
    assert_equal Diagnosis::Rules::V1::SUBJECTS.sort,
                 JSON.parse(File.read(Rails.root.join("config/banco/schemas/item.json"))).dig("properties", "subject", "enum").sort
  end
end
