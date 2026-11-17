require "test_helper"
require Rails.root.join("db/migrate/20261117120000_add_physical_education_subject")

# D-344: Scienze motorie, the twelfth subject: theory only, no entry test. The row comes from the migration (an existing database) and from the
# seeds (a new one); every list of subjects accepts its key.
class PhysicalEducationSubjectTest < ActiveSupport::TestCase
  KEY = "physical_education".freeze
  SCHEMAS = %w[skill_graph lesson item blueprint topic course].freeze

  def migrate_up = ActiveRecord::Migration.suppress_messages { AddPhysicalEducationSubject.new.up }

  test "the seeds create Scienze motorie as the twelfth subject, after chemistry" do
    load Rails.root.join("db/seeds.rb")
    subject = Subject.find_by!(key: KEY)
    assert_equal "Scienze motorie", subject.name_it
    assert_equal 12, subject.position
    assert_equal "Chimica", Subject.find_by!(key: "chemistry").read_attribute(:name_it)
    assert_equal 11, Subject.find_by!(key: "chemistry").position
  end

  test "the migration inserts the row when it is absent and leaves it alone when it is there" do
    assert_nil Subject.find_by(key: KEY)
    migrate_up
    subject = Subject.find_by!(key: KEY)
    assert_equal [ "Scienze motorie", 12 ], [ subject.name_it, subject.position ]
    assert_not_nil subject.created_at
    migrate_up
    assert_equal 1, Subject.where(key: KEY).count
    assert_equal subject.id, Subject.find_by!(key: KEY).id
  end

  test "the migration cannot be rolled back: subjects is append-only" do
    assert_raises(ActiveRecord::IrreversibleMigration) { AddPhysicalEducationSubject.new.down }
  end

  test "it is the only subject with no entry test, and the scope leaves it out" do
    migrate_up
    Subject.create!(key: "math", name_it: "Matematica", position: 1)
    assert_not Subject.find_by!(key: KEY).entry_test?
    assert Subject.find_by!(key: "math").entry_test?
    assert_equal %w[math], Subject.with_entry_test.pluck(:key)
    assert_not_includes Diagnosis::Rules::V1::SUBJECTS, KEY, "no blueprint can be written for it"
  end

  # Every subject enum and key pattern of the schemas names it, next to chemistry.
  def walk(node, &block)
    case node
    when Hash then block.call(node) && node.each_value { |v| walk(v, &block) }
    when Array then node.each { |v| walk(v, &block) }
    end
  end

  test "the JSON schemas accept the key in every subject enum and every skill-key pattern" do
    SCHEMAS.each do |name|
      seen = 0
      walk(JSON.parse(Rails.root.join("config/banco/schemas/#{name}.json").read)) do |node|
        if node["enum"].is_a?(Array) && node["enum"].include?("chemistry")
          assert_includes node["enum"], KEY, "#{name}: a subject enum"
          seen += 1
        end
        if node["pattern"].is_a?(String) && node["pattern"].include?("|chemistry)")
          assert node["pattern"].include?("|#{KEY})"), "#{name}: a skill-key pattern"
          assert_match Regexp.new(node["pattern"]), "#{KEY}.bones-and-joints"
          seen += 1
        end
        true
      end
      assert_operator seen, :>, 0, name
    end
  end

  test "a topic of the subject passes the topic schema" do
    doc = { "schema" => "banco.topic/1", "schema_version" => 1, "subject" => KEY, "key" => "lezione.#{KEY}.bones-and-joints", "lesson_revision" => "latest",
            "practice" => [ { "skill" => "#{KEY}.bones-and-joints", "items" => [ { "item" => "#{KEY}-p-a", "revision" => "latest" }, { "item" => "#{KEY}-p-b", "revision" => "latest" } ] } ] }
    findings = Validation::Findings.new
    assert Validation::SchemaCheck.call("topic", doc, findings), findings.map(&:message).to_s
  end

  test "the palette, the icons and the accent of the subject exist, in both themes" do
    assert_includes Lessons::Palette.subjects, KEY
    assert_equal %w[cause purpose time], Lessons::Palette.subject_roles(KEY).keys
    assert_equal "dumbbell", YAML.safe_load_file(Rails.root.join("config/banco/icons.yml")).dig("ui", "subject-physical-education")
    css = Rails.root.join("app/assets/stylesheets/lesson_roles.css").read
    assert_equal 3, css.scan("--accent-physical_education:").size, "cream, dark, and the dark theme of a dark-preferring browser"
    assert_includes StudentUiHelper::SUBJECT_ICONS, KEY
    assert_includes SearchHelper::SUBJECTS, KEY
  end

  test "the lessons of the subject name no foreign language" do
    assert_not Lessons::Lang.taught?(KEY, "en")
    assert_not Lessons::Lang.taught?(KEY, "es")
    assert_not Lessons::Lang.taught?(KEY, "la")
  end
end
