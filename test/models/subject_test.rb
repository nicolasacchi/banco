require "test_helper"

# D-343: three subjects have another name at the student's school. The table is append-only, so the column keeps the seed name and
# Subject#name_it reads the locale (config/locales/subjects.it.yml) first.
class SubjectTest < ActiveSupport::TestCase
  SCHOOL_NAMES = { "chemistry" => "Scienze integrate – Chimica", "biology" => "Scienze integrate – Biologia", "geography" => "Geografia economica" }.freeze
  SEED_NAMES = { "math" => "Matematica", "italian" => "Italiano", "english" => "Inglese", "spanish" => "Spagnolo", "history" => "Storia",
                 "law_economics" => "Diritto ed economia", "business" => "Economia aziendale", "computer_science" => "Informatica",
                 "chemistry" => "Chimica", "biology" => "Biologia", "geography" => "Geografia" }.freeze

  setup do
    SEED_NAMES.each_with_index { |(key, name), i| Subject.create!(key: key, name_it: name, position: i + 1) }
  end

  test "chemistry, biology and geography answer the name of the school, the column keeps the seed name" do
    SCHOOL_NAMES.each do |key, name|
      subject = Subject.find_by!(key: key)
      assert_equal name, subject.name_it, key
      assert_equal SEED_NAMES.fetch(key), subject.read_attribute(:name_it), "#{key}: the column is the seed name"
    end
  end

  test "every other subject answers the column" do
    Subject.where.not(key: SCHOOL_NAMES.keys).each do |subject|
      assert_equal SEED_NAMES.fetch(subject.key), subject.name_it, subject.key
    end
  end

  test "the search helper names a subject the way the model does" do
    names = Subject.all.to_h { |s| [ s.key, s.name_it ] }
    assert_equal "Geografia economica", names["geography"]
    helper = Object.new.extend(SearchHelper)
    SCHOOL_NAMES.merge("math" => "Matematica").each { |key, name| assert_equal name, helper.search_subject_name(key), key }
  end
end
