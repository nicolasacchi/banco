require "test_helper"

# D-402: Banco::Schemas::Bilingual.derive adds the `_en`/`_es` siblings, the R2 keys and the marker `bilingual` for english and spanish, and for
# no other subject. A subject that does not teach a language is checked against the files as they were: nothing it was refused is accepted.
class BancoSchemasBilingualTest < ActiveSupport::TestCase
  S = Banco::Schemas
  DIR = Rails.root.join("test/fixtures/lang")

  def item(name = "item_choice") = JSON.parse(DIR.join("#{name}.json").read)

  def front_matter(name) = YAML.safe_load(DIR.join(name).read[/\A---\n(.*?)\n---/m, 1])

  def messages(errors) = errors.map(&:message).join(" | ")

  # ---- the derivation -----------------------------------------------------------------------------------------------------

  test "derive adds the target siblings of every _it property with the same subschema, and not for the teacher's keys" do
    base = S.read("item")
    derived = S::Bilingual.derive(base, "item")
    step = derived.dig("$defs", "step", "properties")
    assert_equal base.dig("$defs", "step", "properties", "text_it"), step["text_en"]
    assert_equal base.dig("$defs", "step", "properties", "text_it"), step["text_es"]
    assert_equal base.dig("properties", "hints_it"), derived.dig("properties", "hints_en")
    assert_equal base.dig("properties", "passage_it"), derived.dig("properties", "passage_en")
    assert_equal base.dig("$defs", "catalogue_entry", "properties", "message_it"), derived.dig("$defs", "catalogue_entry", "properties", "message_en")
    %w[description_it choice_only_reason_it].each do |key|
      assert_not derived.dig("$defs", "catalogue_entry", "properties").key?(key.sub("_it", "_en")), key
    end
    assert_not derived.dig("properties", "choice_only_reason_en")
    assert_equal %w[required], derived.dig("$defs", "catalogue_entry").keys & %w[required], "nothing becomes required"
    assert_equal base.dig("$defs", "catalogue_entry", "required"), derived.dig("$defs", "catalogue_entry", "required")
  end

  test "derive adds the R2 twins of the item keys that hold the subject's language, and only those" do
    derived = S::Bilingual.derive(S.read("item"), "item")
    assert_equal derived.dig("$defs", "id_text", "properties", "text"), derived.dig("$defs", "id_text", "properties", "text_it")
    assert_equal derived.dig("$defs", "quote", "properties", "text"), derived.dig("$defs", "quote", "properties", "text_it")
    assert_equal derived.dig("$defs", "table", "properties", "rows"), derived.dig("$defs", "table", "properties", "rows_it")
    assert_equal derived.dig("$defs", "table", "properties", "header"), derived.dig("$defs", "table", "properties", "header_it")
    assert_equal derived.dig("$defs", "solution", "properties", "final"), derived.dig("$defs", "solution", "properties", "final_it")
    assert_nil derived.dig("$defs", "quote", "properties", "ref_it")
  end

  test "derive puts the marker in the item, the lesson front matter and body, a course topic entry, the topic and the skill graph" do
    {
      "item" => [ "properties" ], "topic" => [ "properties" ], "skill_graph" => [ "properties" ],
      "lesson" => [ %w[$defs front_matter2 properties], %w[$defs body2 properties] ], "course" => [ %w[$defs topic_entry properties] ]
    }.each do |name, paths|
      derived = S::Bilingual.derive(S.read(name), name)
      Array(paths.first.is_a?(Array) ? paths : [ paths ]).each do |path|
        assert_equal "boolean", derived.dig(*path, "bilingual", "type"), "#{name} #{path.join('/')}"
        assert_not S.read(name).dig(*path).key?("bilingual"), "#{name}: the file is not changed"
      end
    end
  end

  test "an item of english or spanish may list the words it teaches (teaches_en, teaches_es); no other subject may" do
    derived = S::Bilingual.derive(S.read("item"), "item")
    %w[teaches_en teaches_es].each { |key| assert_equal "array", derived.dig("properties", key, "type") }
    assert_not S.read("item").fetch("properties").key?("teaches_en"), "the file is not changed"
    item = JSON.parse(Rails.root.join("test/fixtures/lang/item_choice.json").read)
    assert_empty S.validate("item", item.merge("teaches_en" => %w[gap verb]))
    assert_not_empty S.validate("item", item.merge("teaches_en" => "gap"))
    assert_not_empty S.validate("item", item.merge("subject" => "math", "teaches_en" => %w[gap]))
  end

  test "derive does not change what it was given, and the schema of a subject without a language is the file" do
    base = S.read("item")
    copy = Marshal.load(Marshal.dump(base))
    S::Bilingual.derive(base, "item")
    assert_equal copy, base
    assert_equal base, S.read("item", bilingual: false)
    assert_not_equal base, S.read("item", bilingual: true)
    assert_same S.schema("item"), S.for_subject("item", "math")
    assert_same S.schema("item"), S.for_subject("item", nil)
    assert_same S.schema("item", bilingual: true), S.for_subject("item", "english")
    assert_same S.schema("item", bilingual: true), S.for_subject("item", "spanish")
  end

  test "derive reaches the figures of a lesson: a reference to the diagram schema is derived too" do
    block = { "n" => 3, "type" => "diagram", "diagram" => { "type" => "sentence", "alt_it" => "La frase.", "alt_en" => "The sentence.", "text_en" => "She reads",
                                                         "parts" => [ { "id" => "s", "text_en" => "She", "role" => "subject" } ] } }
    ref = ->(subject) { S.for_subject("lesson", subject).ref("#/$defs/block") }
    assert_empty ref.("english").validate(block).to_a
    caption = block.deep_merge("diagram" => { "caption_it" => "La frase.", "caption_en" => "The sentence." })
    assert_empty ref.("english").validate(caption).to_a
    assert_not_empty ref.("math").validate(caption).to_a
  end

  # ---- the fixtures validate for english and spanish ---------------------------------------------------------------------

  test "the golden items are valid for english, and not for the file as it is" do
    %w[item_choice item_blank].each do |name|
      assert_empty S.validate("item", item(name)).map(&:to_h), name
      assert_not_empty S.schema("item").validate(item(name)).to_a, "#{name}: the file alone refuses them"
    end
  end

  test "the golden lessons' front matter is valid for english and spanish" do
    assert_empty S.validate_front_matter(front_matter("lesson_en.md")).map(&:to_h)
    assert_empty S.validate_front_matter(front_matter("lesson_es.md")).map(&:to_h)
  end

  test "a text block, a check and a try of a bilingual lesson are valid blocks for english" do
    projected = JSON.parse(DIR.join("projected_lesson.json").read)
    ref = S.for_subject("lesson", "english").ref("#/$defs/block")
    text, check = projected["cards"][0]["blocks"]
    assert_empty ref.validate(text).to_a
    # the options of a check that says translate_material: false have no Italian: the derived schema asks for the target text, not for `text_it`
    assert_empty ref.validate(check.merge("answer" => "o1")).to_a
  end

  # ---- a subject without a language is refused what it was refused -------------------------------------------------------

  test "an item of another subject is refused the flag and every _en sibling, as before" do
    doc = item.merge("subject" => "math")
    doc["instances"][0]["display"]["options"][0]["text_it"] = "fare / fare"
    found = S.validate("item", doc)
    assert_match(/\/bilingual/, messages(found))
    assert_match(/\/translate_material/, messages(found), "the marker of the form material is for the language subjects too")
    assert_match(/\/prompt\/stem_en/, messages(found))
    assert_match(/message_en/, messages(found))
    assert_match(/\/instances\/0\/display\/options\/0\/text_it/, messages(found), "an R2 twin as well")
    assert_equal S.schema("item").validate(doc).map { |e| e["error"] }, found.map(&:message), "exactly the errors of the file as it is"
  end

  test "an item of english refuses what the siblings do not allow: an unknown key and a sibling of a teacher's key" do
    doc = item
    doc["description_en"] = "x"
    doc["error_catalogue"][0]["description_en"] = "x"
    assert_match(/description_en/, messages(S.validate("item", doc)))
  end

  test "the lesson front matter of another subject is refused the flag and the siblings" do
    found = S.validate_front_matter(front_matter("lesson_en.md").merge("subject" => "math"))
    assert_match(/\/bilingual/, messages(found))
    assert_match(/title_en/, messages(found))
    assert_match(/goals_en/, messages(found))
    assert_match(/term_en/, messages(found))
  end

  test "a course topic entry, a topic and a skill graph: the marker and the siblings are for english and spanish only" do
    entry = { "key" => "ripasso.english.can", "kind" => "ripasso", "title_it" => "I modali", "title_en" => "Modals", "term" => 1, "minutes" => 30,
              "skills" => [ "english.modals-can" ], "after" => [], "bilingual" => true }
    course = ->(subject) { { "schema" => "banco.course/1", "schema_version" => 1, "subject" => subject, "skills" => [], "topics" => [ entry ] } }
    assert_no_match(/bilingual|title_en/, messages(S.validate("course", course.("english"))))
    assert_match(/bilingual/, messages(S.validate("course", course.("math"))))
    assert_match(/title_en/, messages(S.validate("course", course.("math"))))

    topic = ->(subject) { { "schema" => "banco.topic/1", "schema_version" => 1, "subject" => subject, "bilingual" => true, "intro_it" => "Ciao.", "intro_en" => "Hello." } }
    assert_no_match(/bilingual|intro_en/, messages(S.validate("topic", topic.("spanish"))))
    assert_match(/bilingual/, messages(S.validate("topic", topic.("history"))))
    assert_match(/intro_en/, messages(S.validate("topic", topic.("history"))))

    graph = ->(subject) { { "schema" => "banco.skill_graph/1", "schema_version" => 1, "subject" => subject, "bilingual" => true, "skills" => [] } }
    assert_no_match(/\/bilingual/, messages(S.validate("skill_graph", graph.("english"))))
    assert_match(/\/bilingual/, messages(S.validate("skill_graph", graph.("italian"))))
    label = { "schema" => "banco.skill_graph/1", "schema_version" => 1, "subject" => "english", "skills" => [ { "label_en" => "Modals" } ] }
    assert_no_match(/label_en/, messages(S.validate("skill_graph", label)))
    assert_match(/label_en/, messages(S.validate("skill_graph", label.merge("subject" => "math"))))
  end

  test "every existing good fixture still validates and every bad one still fails, derivation or not" do
    S::NAMES.each do |name|
      S.fixture_files(name, :good).each { |path| assert_empty S.schema(name).validate(JSON.parse(File.read(path))).to_a, path }
    end
    assert S.validate_fixture_pair
  end
end
