require "test_helper"

# D-356: the student's interface is also English. Every student-facing Italian locale file has an English twin with the same keys (and the
# same %{names}), so a key added on one side and forgotten on the other fails here, not on the student's screen. What stays Italian on
# purpose has no twin: the figures' vocabulary (lesson_chart, lesson_time, lesson_words, lesson_graph, lesson_docs, lesson_maps,
# lesson_science, lesson_computing), the error pages, and everything of the teacher.
class LocaleParityTest < ActiveSupport::TestCase
  LOCALES = Rails.root.join("config/locales")

  # it file => en file; `skip` are the Italian subtrees that the English UI never reads (the refusal pages have no student language).
  TWINS = {
    "it.yml" => { en: "en.yml", skip: %w[errors] },
    "course.it.yml" => { en: "course.en.yml" },
    "comments.it.yml" => { en: "comments.en.yml" },
    "search.it.yml" => { en: "search.en.yml" },
    "lesson_pages.it.yml" => { en: "lesson_pages.en.yml" },
    "lesson.it.yml" => { en: "lesson.en.yml" },
    "lesson_text.it.yml" => { en: "lesson_text.en.yml" },
    "lesson_checks.it.yml" => { en: "lesson_checks.en.yml" },
    "grading.it.yml" => { en: "grading.en.yml" },
    "privacy.it.yml" => { en: "privacy.en.yml" }
  }.freeze

  # Strings that are the same in both languages: a name, a menu word («Privacy»), the voice samples that each speak their own language.
  SAME = %w[student.menu.label student.menu.bar_default diagnosis.preferences.languages.it diagnosis.preferences.languages.en lesson2.menu
            lesson2.voices.sentences.it lesson2.voices.sentences.en lesson2.voices.sentences.es
            student.menu.privacy teacher.menu.privacy privacy.settings_links.privacy account.privacy_link comments.place.privacy].freeze

  def leaves(node, path = [], out = {})
    case node
    when Hash then node.each { |key, value| leaves(value, path + [ key.to_s ], out) }
    when Array then node.each_with_index { |value, index| leaves(value, path + [ index.to_s ], out) }
    else out[path.join(".")] = node
    end
    out
  end

  def read(file, locale, skip: [])
    leaves(YAML.load_file(LOCALES.join(file)).fetch(locale.to_s)).reject { |key, _| skip.any? { |prefix| key.start_with?("#{prefix}.") } }
  end

  def names(text) = text.to_s.scan(/%\{(\w+)\}/).flatten.sort

  TWINS.each do |it_file, twin|
    test "#{it_file}: every key has an English twin, no more, with the same %{names}" do
      it = read(it_file, :it, skip: twin.fetch(:skip, []))
      en = read(twin.fetch(:en), :en)
      assert_empty it.keys - en.keys, "keys of #{it_file} missing in #{twin.fetch(:en)}"
      assert_empty en.keys - it.keys, "keys of #{twin.fetch(:en)} that #{it_file} does not have"
      assert_empty it.keys.reject { |key| names(it[key]) == names(en[key]) }, "interpolations differ"
    end

    test "#{it_file}: the English is a translation, not a copy" do
      it = read(it_file, :it, skip: twin.fetch(:skip, []))
      en = read(twin.fetch(:en), :en)
      copied = it.keys.select { |key| it[key].is_a?(String) && it[key] == en[key] && it[key].match?(/\p{L}{3}/) } - SAME
      assert_empty copied, "texts still in Italian in #{twin.fetch(:en)}"
      assert_empty en.keys.select { |key| en[key].is_a?(String) && en[key].strip.empty? }, "empty English text"
    end
  end

  test "subjects: the English names cover every subject of the seeds, and the Italian overrides are a subset" do
    keys = Rails.root.join("db/seeds.rb").read.scan(/\[\s*"([a-z_]+)",\s*"[^"]+"\s*\]/).flatten
    assert_equal 12, keys.size
    en = read("subjects.en.yml", :en)
    assert_empty keys.map { |key| "subjects.display_name_it.#{key}" } - en.keys
    assert_empty read("subjects.it.yml", :it).keys - en.keys
  end

  test "the lesson cover's subject names exist for every subject in both languages" do
    keys = Subject::WITHOUT_ENTRY_TEST + %w[math italian english spanish history geography law_economics business computer_science biology chemistry]
    twin = read("lesson.en.yml", :en)
    keys.each { |key| assert twin.key?("lesson2.subject.#{key}"), key }
  end

  test "warm-up: every task has its English words, and a matching's words cover its right column" do
    tasks = YAML.safe_load_file(Rails.root.join("config/banco/warmup.yml")).fetch("tasks")
    words = YAML.safe_load_file(Rails.root.join("config/banco/warmup.en.yml")).fetch("tasks")
    assert_equal tasks.map { |t| t["id"] }.sort, words.keys.sort
    tasks.each do |task|
      assert words[task["id"]]["prompt_it"].present?, task["id"]
      right = task.dig("display", "right")
      assert_equal right.map { |o| o["id"] }.sort, words[task["id"]].fetch("right").keys.sort, task["id"] if right
    end
  end

  test "every language of the preferences is an available locale with its own file and its name in the settings" do
    assert_equal Diagnosis::Preferences::LANGUAGES.sort, I18n.available_locales.map(&:to_s).sort
    Diagnosis::Preferences::LANGUAGES.each do |language|
      assert LOCALES.join("#{language}.yml").exist?, language
      assert read("it.yml", :it).key?("diagnosis.preferences.languages.#{language}"), language
    end
  end
end
