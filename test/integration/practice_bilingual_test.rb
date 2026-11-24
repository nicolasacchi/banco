require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/practice_text_world"

# D-402, slice 1, over the real endpoints: the two golden items of test/fixtures/lang served in practice with both layers, the leak scans on both
# layers, and the rule of the reading passage (its Italian reaches the page only once the exercise is over). A legacy item's replies are the other
# practice tests' business (they are unchanged).
class PracticeBilingualTest < ActionDispatch::IntegrationTest
  include MultiUser
  include PracticeTextWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  LANG = ->(name) { JSON.parse(File.read(Rails.root.join("test/fixtures/lang/#{name}.json"))) }
  SERVED = LANG.("served_item")
  CHOICE = "bil-choice".freeze
  BLANK = "bil-blank".freeze
  BLANK_TWIN = "bil-blank-twin".freeze # the same typical error as BLANK, for the reminder
  PASSAGE_A = "bil-passage-a".freeze
  PASSAGE_B = "bil-passage-b".freeze
  PASSAGE_EN = "Tom has a red bike. He rides it to the park.".freeze
  PASSAGE_IT = "Tom ha una bici rossa. La usa per andare al parco.".freeze
  # A reading text per instance (D-402): three instances on each of two texts, the item holding none of its own (bilingual) or one the instances override (legacy).
  EACH = "bil-passage-each".freeze
  LEGACY_EACH = "leg-passage-each".freeze
  EACH_TEXTS = [ { en: "Amy has a green kite. She flies it on the hill.", it: "Amy ha un aquilone verde. Lo fa volare sulla collina." },
                 { en: "Ben has a grey cat. It sleeps on the sofa.", it: "Ben ha un gatto grigio. Dorme sul divano." } ].freeze
  # What may never be a key of the student's JSON before the answer, on either layer.
  FORBIDDEN_KEYS = %w[answer answers accept errors error_catalogue solution final final_it id_map shown_order verdict rubric model_answer_it grading evidence].freeze

  setup do
    build_text_world
    @bilingual = [ bilingual_item(CHOICE, LANG.("item_choice")), bilingual_item(BLANK, LANG.("item_blank"), own_hints: true),
                   bilingual_item(BLANK_TWIN, LANG.("item_blank")), passage_item(PASSAGE_A), passage_item(PASSAGE_B), each_item(EACH, bilingual: true),
                   each_item(LEGACY_EACH, bilingual: false) ]
    approve_topic!(make_topic(@lesson_revision, { SKILL => [ @sentence, @word, *@bilingual ] }, course: @course))
  end

  # The golden fixture as a revision of the topic's skill with its instances as authored; own_hints: each instance carries the object of its own pair.
  def bilingual_item(key, fixture, own_hints: false)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = fixture.except("instances").merge("skill" => SKILL, "subject" => @subject.key)
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    fixture["instances"].each_with_index do |inst, i|
      hints = own_hints ? JSON.generate({ "hints_en" => fixture["hints_en"], "hints_it" => fixture["hints_it"] }) : nil
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(inst["display"]), answer_json: JSON.generate(inst["answer"]),
                           errors_json: JSON.generate(inst["errors"]), hints_json: hints, solution_json: JSON.generate(inst["solution"]),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  # A reading item whose instances carry their own passage in `display` (three on each of two texts). bilingual: `passage_en` + `passage_it` and no passage
  # in the body; legacy: `passage_it` alone (the English text under its legacy key), the body holding one the instances override.
  def each_item(key, bilingual:)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: "normalized_text", level: 1, expected_seconds: 60 }
    body.merge!(bilingual ? { bilingual: true, prompt: { stem_en: "What colour is it?", stem_it: "Di che colore è?" }, hints_en: [ "Read the first line." ], hints_it: [ "Leggi la prima riga." ] }
                          : { passage_it: "The item's own text, which no instance shows.", prompt: { stem_it: "What colour is it?" }, hints_it: [ "Read the first line." ] })
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    steps = bilingual ? [ { text_en: "The first line says it.", text_it: "La prima riga lo dice." } ] : [ { text_it: "The first line says it." } ]
    6.times do |i|
      text = EACH_TEXTS[i / 3]
      display = bilingual ? { passage_en: text[:en], passage_it: text[:it] } : { passage_it: text[:en] }
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(display), answer_json: JSON.generate("green"), errors_json: "[]",
                           solution_json: JSON.generate(steps: steps, final: "green"), fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  # A text item with a reading passage in both languages (a short answer's shape, served by the practice page for the rule of the passage).
  def passage_item(key)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: @subject.key, skill: SKILL, component: "normalized_text", level: 1,
             expected_seconds: 60, bilingual: true, passage_en: PASSAGE_EN, passage_it: PASSAGE_IT,
             prompt: { stem_en: "What colour is the bike?", stem_it: "Di che colore è la bici?" },
             hints_en: [ "Read the first line." ], hints_it: [ "Leggi la prima riga." ] }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    6.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: "{}", answer_json: JSON.generate("red"), errors_json: "[]",
                           solution_json: JSON.generate(steps: [ { text_en: "The first line says red.", text_it: "La prima riga dice rossa." } ], final: "red", final_it: "red: rossa"),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(key) = post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL, item: key })
  def answer_for(serve, raw) = post_json(OFFICIAL, "/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: raw, source: "text" })
  def hint_for(serve, n) = post_json(OFFICIAL, "/practice/serves/#{serve['serve_id']}/hint", { n: n })
  def solution_for(serve) = post_json(OFFICIAL, "/practice/serves/#{serve['serve_id']}/solution")

  def keys_of(value, found = [])
    case value
    when Hash then value.each { |k, v| found << k.to_s; keys_of(v, found) }
    when Array then value.each { |v| keys_of(v, found) }
    end
    found
  end

  test "the golden blank item is served with both layers, then its hint, its typical error, its reminder and its solution" do
    serve = serve_for(BLANK)
    assert_equal "item", serve["type"]
    part = serve["item"]
    golden = SERVED["blank"]
    assert_equal golden["part"].except("instance_stem_en", "instance_stem_it"), part.except("instance_stem_en", "instance_stem_it")
    shown = LANG.("item_blank")["instances"].map { |i| i["display"].values_at("stem_en", "stem_it") }
    assert_includes shown, part.values_at("instance_stem_en", "instance_stem_it"), "the instance's stem in both layers"
    assert_nil serve["reminder_it"]
    assert_equal [ 3, [] ], [ serve["hints"]["total"], serve["hints"]["shown"] ]

    first = hint_for(serve, 1) # the instance's own pair (an object in item_instances.hints_json)
    assert_equal({ "n" => 1, "total" => 3, "hint_en" => LANG.("item_blank")["hints_en"][0], "hint_it" => LANG.("item_blank")["hints_it"][0] }, first)
    assert_equal golden["hint"], hint_for(serve, 2)
    assert_equal [ 1, 2 ], PracticeServe.find(serve["serve_id"]).events.where(kind: "hint_shown").order(:id).map { |e| JSON.parse(e.payload_json)["n"] }

    slip = JSON.parse(ItemInstance.find(PracticeServe.find(serve["serve_id"]).item_instance_id).errors_json).first["value"]
    wrong = answer_for(serve, slip)
    assert_equal %w[graded typical_error], wrong.values_at("status", "outcome")
    assert_equal golden["feedback"].except("try_number"), wrong.slice(*golden["feedback"].keys).except("try_number")
    assert_equal 1, wrong["try_number"]
    assert_not wrong.key?("passage_it"), "an item with no passage carries none"

    twin = serve_for(BLANK_TWIN)
    assert_equal golden["reminder"], twin.slice("reminder_en", "reminder_it")
    assert_equal "en_missing_third_s", AppEvent.where(kind: "practice_reminder_shown").last.then { |e| JSON.parse(e.payload_json)["code"] }

    shown_solution = solution_for(serve)
    instance_solution = ItemInstance.find(PracticeServe.find(serve["serve_id"]).item_instance_id).then { |i| JSON.parse(i.solution_json) }
    assert_equal instance_solution["steps"].map { |s| s.slice("text_en", "text_it") }, shown_solution["solution"]["steps"]
    assert_equal instance_solution.slice("final", "final_it"), shown_solution["solution"].slice("final", "final_it")
  end

  test "the golden choice item (form material, translate_material: false) is served with the options shuffled and no Italian for the sentence or the options" do
    serve = serve_for(CHOICE)
    part = serve["item"]
    golden = SERVED["choice"]["part"]
    assert_equal golden.except("options", "instance_stem_en", "instance_stem_it"), part.except("options", "instance_stem_en", "instance_stem_it")
    assert_equal %w[o1 o2 o3 o4], part["options"].map { |o| o["id"] }
    stored = LANG.("item_choice")["instances"].find { |i| i["display"]["stem_en"] == part["instance_stem_en"] }
    assert_equal stored["display"]["options"].map { |o| o.slice("text") }.sort_by(&:to_s), part["options"].map { |o| o.slice("text") }.sort_by(&:to_s)
    assert_nil part["instance_stem_it"], "the sentence with its blank is target-only"
    assert_empty part["options"].flat_map(&:keys) & %w[text_it], "no option carries an Italian text"
    assert_includes part["stem_it"], "Scegli", "the instruction keeps its Italian"

    exercises = post_exercises
    entry = exercises.find { |e| e["item"] == CHOICE }
    assert_equal SERVED["choice"]["exercise"], entry.slice("title_en", "title_it")
    legacy = exercises.find { |e| e["item"] == SENTENCE }
    assert_equal [ "title_it" ], legacy.keys.grep(/\Atitle/), "a legacy exercise has the one title"
  end

  def post_exercises
    on(:web, "/practice/exercises?topic=#{TOPIC}", headers: OFFICIAL, remote_addr: EDGE)
    response.parsed_body.fetch("skills").flat_map { |s| s["exercises"] }
  end

  test "leak scan: before the answer neither layer holds the key, the errors, the solution or the Italian of the key" do
    [ BLANK, CHOICE ].each do |key|
      serve = serve_for(key)
      payloads = [ serve, hint_for(serve, 1) ]
      instance = ItemInstance.find(PracticeServe.find(serve["serve_id"]).item_instance_id)
      secrets = [ JSON.parse(instance.answer_json).to_s ]
      solution = JSON.parse(instance.solution_json)
      secrets += [ solution["final"], solution["final_it"], *solution["steps"].flat_map { |s| s.values_at("text_en", "text_it") } ]
      payloads.each do |payload|
        assert_empty keys_of(payload) & FORBIDDEN_KEYS, "#{key}: key or outcome fields in the payload"
        text = payload.to_json
        secrets.each { |secret| refute_includes text, secret.to_json[1..-2], "#{key}: #{secret.inspect} is in the payload" } unless key == CHOICE # a choice shows its options, key included
      end
      assert_empty(payloads.flat_map { |p| keys_of(p) } & %w[answer final_it text_it_key])
    end
  end

  test "the Italian of a reading passage is not on the page until the exercise is over: the answer reply and the solution then carry it" do
    serve = serve_for(PASSAGE_A)
    part = serve["item"]
    assert_equal PASSAGE_EN, part["passage_en"]
    assert_equal "Di che colore è la bici?", part["stem_it"], "the Italian of the question is shown as usual"
    assert_not part.key?("passage_it")
    refute_includes serve.to_json, "bici rossa"
    refute_includes hint_for(serve, 1).to_json, PASSAGE_IT

    wrong = answer_for(serve, "blue")
    assert_equal "unrecognised", wrong["outcome"]
    assert_not wrong.key?("passage_it"), "the serve is still open: no Italian passage"
    refute_includes wrong.to_json, PASSAGE_IT

    right = answer_for(serve, "red")
    assert_includes %w[correct correct_aided], right["outcome"]
    assert_equal PASSAGE_IT, right["passage_it"], "the exercise is over"
    assert_equal PASSAGE_IT, right.dig("solution", "passage_it")

    other = serve_for(PASSAGE_B)
    refute_includes other.to_json, PASSAGE_IT
    shown = solution_for(other)
    assert_equal PASSAGE_IT, shown.dig("solution", "passage_it")
    assert_equal "red: rossa", shown.dig("solution", "final_it")
  end

  test "a bilingual instance's own passage is served in its target language, its Italian only once the exercise is over" do
    serve = serve_for(EACH)
    own = JSON.parse(ItemInstance.find(PracticeServe.find(serve["serve_id"]).item_instance_id).display_json)
    part = serve["item"]
    assert_equal own["passage_en"], part["passage_en"], "the instance's text, not another one"
    assert_not part.key?("passage_it")
    refute_includes serve.to_json, own["passage_it"]
    refute_includes hint_for(serve, 1).to_json, own["passage_it"]

    wrong = answer_for(serve, "blue")
    assert_not wrong.key?("passage_it"), "the serve is still open"
    refute_includes wrong.to_json, own["passage_it"]

    right = answer_for(serve, "green")
    assert_equal own["passage_it"], right["passage_it"], "the exercise is over: the Italian of this instance's text"
    assert_equal own["passage_it"], right.dig("solution", "passage_it")
  end

  test "a bilingual instance's solution asked for carries the Italian of its own passage" do
    serve = serve_for(EACH)
    own = JSON.parse(ItemInstance.find(PracticeServe.find(serve["serve_id"]).item_instance_id).display_json)
    assert_equal own["passage_it"], solution_for(serve).dig("solution", "passage_it")
  end

  test "a legacy instance's own passage overrides the item's and is served as it always was; no reply adds an Italian layer" do
    serve = serve_for(LEGACY_EACH)
    own = JSON.parse(ItemInstance.find(PracticeServe.find(serve["serve_id"]).item_instance_id).display_json)
    part = serve["item"]
    assert_equal own["passage_it"], part["passage_it"]
    assert_not part.key?("lang")
    assert_not part.key?("passage_en")
    refute_includes serve.to_json, "which no instance shows"
    right = answer_for(serve, "green")
    assert_includes %w[correct correct_aided], right["outcome"]
    assert_not right.key?("passage_it")
    assert_not right.fetch("solution", {}).key?("passage_it")
  end

  test "the teacher's topic review shows the catalogue message of a bilingual item in both layers, and a legacy one as it was" do
    on(:web, "/teacher/subjects/#{@subject.key}/topics/#{TOPIC}", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    entry = LANG.("item_blank")["error_catalogue"].first
    both = "#{entry['message_en']} — #{entry['message_it']}"
    assert_includes css_select("p[data-code=en_missing_third_s] q").map(&:text), both
    assert_includes css_select("p[data-code=does_eat] q").map(&:text), SLIP_MESSAGE
  end
end
