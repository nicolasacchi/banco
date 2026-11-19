require "test_helper"

# D-375, «Novità»: the curated entries of config/banco/changelog.yml. The file is valid, every student entry has its English twin, the student's text has
# no decision number and no jargon, every decision it names is in the index, the audience filter and the order, and the schema's refusals one by one.
class ChangelogEntriesTest < ActiveSupport::TestCase
  E = Changelog::Entries

  GOOD = {
    "id" => "my-entry", "date" => Date.new(2026, 11, 19), "audience" => [ "student" ], "kind" => "software",
    "title_it" => "Un titolo", "body_it" => "Una frase. Un'altra frase.", "title_en" => "A title", "body_en" => "A sentence. Another sentence."
  }.freeze

  def errors_of(**changes)
    drop = changes.delete(:drop) || []
    entry = GOOD.merge(changes).except(*drop)
    E.errors({ "entries" => [ entry ] })
  end

  def assert_refused(pattern, **changes)
    found = errors_of(**changes)
    assert found.any? { |e| e.match?(pattern) }, "expected a problem like #{pattern.inspect}, got #{found.inspect}"
  end

  # ---- the real file ----------------------------------------------------------------------------------

  test "the file is valid and every entry reads" do
    assert_empty E.errors(YAML.safe_load_file(E::DEFAULT_PATH, permitted_classes: [ Date ], aliases: false))
    assert_operator E.all.size, :>=, 25
    assert_equal E.all.map(&:id).uniq, E.all.map(&:id)
  end

  test "every student entry has its English twin, no decision number and no jargon in what he reads" do
    student = E.for(:student)
    assert_operator student.size, :>=, 15
    student.each do |entry|
      assert entry.title_en.present? && entry.body_en.present?, entry.id
      [ entry.title_it, entry.body_it, entry.title_en, entry.body_en ].each do |text|
        assert_no_match(E::DECISION_IN_TEXT, text, entry.id)
        assert_no_match(E::JARGON, text, entry.id)
      end
    end
  end

  test "every decision an entry names is in the decisions index, and the days are not in the future" do
    numbers = Updates.changes.map { |row| row[:number] }
    E.all.each do |entry|
      entry.decisions.each { |d| assert_includes numbers, d, "#{entry.id} names #{d}" }
      assert_operator entry.date, :<=, Date.current, entry.id
    end
  end

  test "every link is a page of the app: the student's for a student entry, the teacher's for the teacher" do
    web = Rails.application.routes.routes.select { |r| r.verb == "GET" || r.verb.blank? }
    E.all.select(&:link).each do |entry|
      path = entry.link
      matched = web.any? { |route| route.path.to_regexp.match?(path) } || path == "/"
      assert matched, "#{entry.id} links to #{path}, which no route serves"
      assert_not path.start_with?("/teacher"), "#{entry.id}: the student cannot open #{path}" if entry.student?
    end
  end

  test "the backfill covers the decisions of 17 to 19 November, D-350 to D-373" do
    named = E.all.flat_map(&:decisions)
    (350..373).each { |n| assert_includes named, "D-#{n}", "no entry names D-#{n}" }
    assert_includes E.for(:teacher).flat_map(&:decisions), "D-368"
    assert_includes E.for(:student).map(&:id), "my-schemas"
  end

  test "an entry is for the student, the teacher or both; the teacher's list holds every entry" do
    assert_equal E.all.select { |e| e.audience.include?("student") }, E.for(:student)
    assert_equal E.all, E.for(:teacher)
    assert E.for(:student).none? { |e| e.audience == [ "teacher" ] }
    assert E.all.any? { |e| e.audience == [ "teacher" ] }
    assert_raises(ArgumentError) { E.for(:operator) }
  end

  test "newest first, and the later in the file first on the same day" do
    text = <<~YAML
      entries:
        - {id: first-one, date: 2026-11-17, audience: [student], kind: software, title_it: "A", body_it: "Uno.", title_en: "A", body_en: "One."}
        - {id: second-one, date: 2026-11-19, audience: [student], kind: software, title_it: "B", body_it: "Due.", title_en: "B", body_en: "Two."}
        - {id: third-one, date: 2026-11-19, audience: [teacher], kind: fix, title_it: "C", body_it: "Tre."}
    YAML
    assert_equal %w[third-one second-one first-one], E.parse(text).map(&:id)
    assert_equal %w[third-one second-one], E.since(E.parse(text), Date.new(2026, 11, 18)).map(&:id)
  end

  test "the English twin is for a student reading in English; the teacher's text is Italian" do
    entry = E.all.find { |e| e.id == "my-schemas" }
    assert_equal "I miei schemi", entry.title(:it)
    assert_equal "My summaries", entry.title(:en)
    teacher_only = E.all.find { |e| e.audience == [ "teacher" ] }
    assert_equal teacher_only.title_it, teacher_only.title(:en), "no English twin: the Italian is what there is"
  end

  test "the file path can be pointed at another file, and a broken file raises with every problem" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "changelog.yml")
      File.write(path, "entries: []\n")
      saved = E.path
      begin
        E.path = path
        assert_empty E.all
        File.write(path, "entries:\n  - {id: x}\n")
        E.reset!
        error = assert_raises(E::Invalid) { E.all }
        assert_match(/needs date/, error.message)
        assert_match(/needs title_it/, error.message)
      ensure
        E.path = saved
        E.reset!
      end
    end
  end

  # ---- the schema ---------------------------------------------------------------------------------------

  test "a good entry has no problem" do
    assert_empty errors_of
    assert_empty errors_of("audience" => [ "teacher" ], "kind" => "fix", "decisions" => [ "D-366" ], "topics" => [ "ripasso.math.demo" ], "link" => "/teacher/grading",
                           "title_en" => nil, "body_en" => nil)
  end

  test "the file is a mapping with a list of entries and nothing else" do
    assert_not_empty E.errors([])
    assert_not_empty E.errors({ "entries" => [], "more" => 1 })
    assert_not_empty E.errors({ "entries" => {} })
    assert_not_empty E.errors({ "entries" => [ "x" ] })
  end

  test "required keys, unknown keys, the id, the day" do
    %w[id date audience kind title_it body_it].each { |key| assert_refused(/needs #{key}/, drop: [ key ]) }
    assert_refused(/unknown key "mood"/, "mood" => "happy")
    assert_refused(/id is lower case/, "id" => "Bad Id")
    assert_refused(/date is a day/, "date" => "2026-11-19")
    assert_includes E.errors({ "entries" => [ GOOD, GOOD ] }).join, "used twice"
  end

  test "audience and kind are closed lists" do
    assert_refused(/audience is a list/, "audience" => "student")
    assert_refused(/audience is a list/, "audience" => [])
    assert_refused(/audience is a list/, "audience" => [ "parent" ])
    assert_refused(/audience is a list/, "audience" => [ "student", "student" ])
    assert_refused(/kind is one of/, "kind" => "feature")
  end

  test "the English twin is required for the student and comes in a pair" do
    assert_refused(/needs title_en and body_en/, drop: %w[title_en body_en])
    assert_refused(/needs title_en and body_en/, "audience" => [ "student", "teacher" ], drop: %w[title_en body_en])
    assert_refused(/come together/, "audience" => [ "teacher" ], drop: [ "body_en" ])
    assert_empty errors_of("audience" => [ "teacher" ], drop: %w[title_en body_en])
  end

  test "a body is one to three short sentences and a title is short" do
    assert_refused(/1 to 3 short sentences \(it has 4\)/, "body_it" => "Uno. Due. Tre. Quattro.")
    assert_refused(/body_en is 1 to 3/, "body_en" => "One. Two. Three. Four.")
    assert_refused(/title_it is at most/, "title_it" => "x" * 71)
    assert_refused(/body_it is at most/, "body_it" => "Una frase #{'lunga ' * 70}.")
    assert_empty errors_of("body_it" => "Che bello! Davvero? Sì.")
  end

  test "the student's text has no decision number, no jargon and no blame" do
    assert_refused(/no decision number/, "body_it" => "Lo dice la D-366.")
    assert_refused(/no decision number/, "title_en" => "As in D-366")
    assert_refused(/jargon \(API\)/, "body_it" => "Usa l'API nuova.")
    assert_refused(/jargon \(token\)/, "body_en" => "A new token.")
    assert_refused(/reads as blaming/, "body_it" => "Hai sbagliato prima.")
    # the teacher's text may name a decision and talk about the API
    assert_empty errors_of("audience" => [ "teacher" ], "body_it" => "Vedi D-366 e l'API.", drop: %w[title_en body_en])
  end

  test "decisions, topics and the link are checked in form" do
    assert_refused(/decisions is a list/, "decisions" => "D-366")
    assert_refused(/decisions is a list/, "decisions" => [ "366" ])
    assert_refused(/decisions is a list/, "decisions" => [])
    assert_refused(/topics is a list/, "topics" => [ "not a topic" ])
    assert_refused(/link is a path/, "link" => "schemas")
    assert_refused(/link is a path/, "link" => "https://example.org/")
    assert_empty errors_of("topics" => [ "ripasso.math.demo" ], "link" => "/topics/ripasso.math.demo/schema")
  end

  test "how sentences are counted" do
    assert_equal 1, E.sentences("Una sola frase.")
    assert_equal 2, E.sentences("Per esempio x = 37/5 al posto di 37/5. Conta il valore: se è giusto, è giusto.")
    assert_equal 2, E.sentences("Vedi «Giuste: 3 su 5». Non ti diciamo quali.")
    assert_equal 1, E.sentences("Senza punto")
  end
end
