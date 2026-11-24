require "test_helper"

# D-402, slice 1: the golden items of test/fixtures/lang served through Items::Part, Practice::Payload, Practice::Messages and Practice::Reminder, a
# legacy item served as before, the passage rule (the Italian of a reading passage reaches the page only after the answer) and the sitting's presenter.
class ItemsPartBilingualTest < ActiveSupport::TestCase
  Subject = Struct.new(:key) do
    def name_it = "Inglese"
  end
  Served = Struct.new(:item_instance, :shown_order_json, :diagnosis_event_id)
  Revision = Struct.new(:body_json)
  Instance = Struct.new(:item_revision, :hints_json, :solution_json, :display_json, :answer_json, :accept_json)

  ITEMS = { "choice" => "item_choice", "blank" => "item_blank" }.freeze
  SERVED = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/served_item.json")))

  def item(name) = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/#{ITEMS.fetch(name)}.json")))

  # The instance as the page shows it: the stored display with the options in the order of the golden serve (it is shuffled and re-keyed in the
  # real path; the shuffle moves text_it with its option, which the golden options show).
  def display_of(name, body)
    display = body["instances"][0]["display"].dup
    display["options"] = SERVED[name]["part"]["options"] if SERVED[name]["part"]["options"]
    display
  end

  def instance_of(name, body, n: 0, hints: nil)
    inst = body["instances"][n]
    Instance.new(Revision.new(JSON.generate(body.except("instances"))), hints && JSON.generate(hints), JSON.generate(inst["solution"]), JSON.generate(inst["display"]))
  end

  def json(value) = JSON.parse(value.to_json)

  ITEMS.each_key do |name|
    test "the golden #{name} item is served as the contract says" do
      body = item(name)
      golden = SERVED.fetch(name)
      part = Items::Part.new(subject: Subject.new("english")).call(body, body["component"], display_of(name, body))
      assert_equal golden["part"], json(part)
      assert_equal "en", part[:lang]
      assert_nil part[:passage_it]

      instance = instance_of(name, body)
      hint = golden["hint"]
      assert_equal hint, json(Practice::Payload.hint(instance, hint["n"]))
      assert_equal golden["solution"], json(Practice::Payload.solution(instance))

      code = golden["feedback"]["error_code"]
      entry = Practice::Instances.catalogue_entry(instance, code)
      keys = Practice::Messages.feedback_keys(:typical_error, entry)
      assert_equal golden["feedback"].slice("message_en", "message_it"), json(keys)

      line = Practice::Reminder.text_for(instance, code, ->(_) { nil }, [])
      assert_equal golden["reminder"], json(line.payload)
      assert_equal "item", line.source
    end
  end

  test "form material is served with no Italian, whatever is stored; a translated choice keeps the Italian of its sentence and options" do
    body = item("choice")
    display = display_of("choice", body)
    display = display.merge("stem_it" => "Il sabato io ___ il letto.", "options" => display["options"].map { |o| o.merge("text_it" => "fare") })
    part = Items::Part.new(subject: Subject.new("english")).call(body, "choice", display)
    assert_nil part[:instance_stem_it]
    assert_equal "On Saturdays I ___ my bed and then I ___ the shopping with Dad.", part[:instance_stem_en]
    assert_empty part[:options].flat_map(&:keys) & %w[text_it]
    assert_equal body["prompt"]["stem_it"], part[:stem_it], "the instruction keeps its Italian"
    sub = Items::Text.inherit_material(body, { "id" => "a", "prompt" => {} })
    assert_equal false, sub["translate_material"], "a sub item of a testlet inherits the marker"

    translated = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/item_choice_translated.json")))
    shown = Items::Part.new(subject: Subject.new("english")).call(translated, "choice", translated["instances"][0]["display"])
    assert_equal "Il sabato io ___ il letto e poi io ___ la spesa con papà.", shown[:instance_stem_it]
    assert_equal [ "fare / fare" ] * 4, shown[:options].map { |o| o["text_it"] }
  end

  test "the chrome sentences stay one sentence in the page's language, whatever the item" do
    body = item("choice")
    assert_equal({ message_it: I18n.t("practice.correct") }, Practice::Messages.feedback_keys(:correct, body["error_catalogue"][0]))
    assert_equal({ message_it: I18n.t("practice.unrecognised") }, Practice::Messages.feedback_keys(:unrecognised, nil))
    assert_equal({ message_it: I18n.t("practice.unrecognised") }, Practice::Messages.feedback_keys(:typical_error, { "code" => "x" }), "no message: the page's own sentence")
  end

  test "a hint of an instance with its own pair, and of a legacy item with its own list" do
    body = item("blank")
    own = { "hints_en" => [ "One.", "Two." ], "hints_it" => [ "Uno.", "Due." ] }
    instance = instance_of("blank", body, hints: own)
    assert_equal({ n: 2, total: 2, hint_en: "Two.", hint_it: "Due." }, Practice::Payload.hint(instance, 2))
    assert_equal({ n: 1, hint_en: "One.", hint_it: "Uno." }, Practice::Payload.hint_entry(instance, 1))
    assert_equal %w[One. Two.], Practice::Instances.hints(instance)

    legacy = Instance.new(Revision.new(JSON.generate({ "hints_it" => [ "Da scegliere." ] })), JSON.generate([ "Propria." ]))
    assert_equal({ n: 1, total: 1, hint_it: "Propria." }, Practice::Payload.hint(legacy, 1))
    assert_equal({ n: 1, hint_it: "Propria." }, Practice::Payload.hint_entry(legacy, 1))
    item_level = Instance.new(Revision.new(JSON.generate({ "hints_it" => [ "Da scegliere." ] })), nil)
    assert_equal({ n: 1, total: 1, hint_it: "Da scegliere." }, Practice::Payload.hint(item_level, 1))
    assert_equal [], Practice::Instances.hints(Instance.new(Revision.new("{}"), "[]"))
  end

  test "a legacy item is served exactly as before: no lang, no sibling" do
    body = { "component" => "choice", "prompt" => { "stem_it" => "Scegli." }, "answer_format_it" => "Un solo.", "steps_it" => [ "Leggi." ],
             "error_catalogue" => [ { "code" => "x", "message_it" => "Rileggi." } ] }
    display = { "stem_it" => "She ___ home.", "options" => [ { "id" => "o1", "text" => "goes" } ] }
    part = Items::Part.new(subject: Subject.new("english")).call(body, "choice", display)
    assert_equal({ component: "choice", stem_it: "Scegli.", instance_stem_it: "She ___ home.", options: [ { "id" => "o1", "text" => "goes" } ],
                   answer_format_it: "Un solo.", steps_it: [ "Leggi." ] }, part)

    instance = Instance.new(Revision.new(JSON.generate(body)), nil, JSON.generate(steps: [ { text_it: "Passo.", math: "1" } ], final: "goes"))
    assert_equal({ steps: [ { text_it: "Passo.", math: "1" } ], final: "goes" }, Practice::Payload.solution(instance))
    assert_equal({ message_it: "Rileggi." }, Practice::Messages.feedback_keys(:typical_error, body["error_catalogue"][0]))
    line = Practice::Reminder.text_for(instance, "x", ->(_) { nil }, [])
    assert_equal({ reminder_it: "Rileggi." }, line.payload)
  end

  test "the passage of a bilingual item reaches the page in its target language only, its Italian after the answer" do
    body = { "component" => "short_answer", "passage_en" => "Tom has a red bike.", "passage_it" => "Tom ha una bici rossa.",
             "prompt" => { "stem_en" => "What colour is the bike?", "stem_it" => "Di che colore è la bici?" } }
    part = Items::Part.new(subject: Subject.new("english")).call(body, "short_answer", {})
    assert_equal "Tom has a red bike.", part[:passage_en]
    assert_equal "Di che colore è la bici?", part[:stem_it], "the Italian of the instructions and the question is shown as usual"
    assert_not_includes part.to_json, "bici rossa", "the Italian passage is not in the part"
    assert_not part.key?(:passage_it)

    after = Items::Part.new(subject: Subject.new("english"), after_answer: true).call(body, "short_answer", {})
    assert_equal "Tom ha una bici rossa.", after[:passage_it]

    instance = Instance.new(Revision.new(JSON.generate(body)), nil, JSON.generate(steps: [], final: "red"))
    assert_equal({ passage_it: "Tom ha una bici rossa." }, Practice::Payload.passage(instance))
    assert_equal "Tom ha una bici rossa.", Practice::Payload.solution(instance)[:passage_it]
  end

  test "the passage of a legacy item is served as it always was, and no reply adds one" do
    body = { "component" => "short_answer", "passage_it" => "Tom has a red bike.", "prompt" => { "stem_it" => "What colour?" } }
    assert_equal "Tom has a red bike.", Items::Part.new(subject: Subject.new("english")).call(body, "short_answer", {})[:passage_it]
    instance = Instance.new(Revision.new(JSON.generate(body)), nil, JSON.generate(steps: [], final: "red"))
    assert_equal({}, Practice::Payload.passage(instance))
    assert_not Practice::Payload.solution(instance).key?(:passage_it)
  end

  test "a bilingual instance's own passage overrides the item's: the target text in the part, its Italian only after the answer" do
    body = { "component" => "normalized_text", "bilingual" => true, "passage_en" => "The item's text.", "passage_it" => "Il testo dell'esercizio.",
             "prompt" => { "stem_en" => "What colour is the bike?", "stem_it" => "Di che colore è la bici?" } }
    own = { "passage_en" => "Tom has a red bike.", "passage_it" => "Tom ha una bici rossa." }
    part = Items::Part.new(subject: Subject.new("english")).call(body, "normalized_text", own.merge("stem_en" => "It is ___.", "stem_it" => "È ___."))
    assert_equal "Tom has a red bike.", part[:passage_en]
    assert_equal "en", part[:lang]
    assert_not part.key?(:passage_it)
    assert_not_includes part.to_json, "bici rossa"
    assert_not_includes part.to_json, "The item's text"

    after = Items::Part.new(subject: Subject.new("english"), after_answer: true).call(body, "normalized_text", own)
    assert_equal [ "Tom has a red bike.", "Tom ha una bici rossa." ], after.values_at(:passage_en, :passage_it)

    # an instance with none of its own reads the item's
    assert_equal "The item's text.", Items::Part.new(subject: Subject.new("english")).call(body, "normalized_text", {})[:passage_en]

    instance = Instance.new(Revision.new(JSON.generate(body)), nil, JSON.generate(steps: [], final: "red"), JSON.generate(own))
    assert_equal({ passage_it: "Tom ha una bici rossa." }, Practice::Payload.passage(instance))
    assert_equal "Tom ha una bici rossa.", Practice::Payload.solution(instance)[:passage_it]
    own_less = Instance.new(Revision.new(JSON.generate(body)), nil, JSON.generate(steps: [], final: "red"), "{}")
    assert_equal({ passage_it: "Il testo dell'esercizio." }, Practice::Payload.passage(own_less))
  end

  test "a legacy instance's own passage_it overrides the item's, served as before" do
    body = { "component" => "normalized_text", "passage_it" => "The item's text.", "prompt" => { "stem_it" => "What colour?" } }
    part = Items::Part.new(subject: Subject.new("english")).call(body, "normalized_text", { "passage_it" => "Tom has a red bike." })
    assert_equal "Tom has a red bike.", part[:passage_it]
    assert_nil part[:lang]
    assert_equal "The item's text.", Items::Part.new(subject: Subject.new("english")).call(body, "normalized_text", {})[:passage_it]
    instance = Instance.new(Revision.new(JSON.generate(body)), nil, JSON.generate(steps: [], final: "red"), JSON.generate("passage_it" => "Tom has a red bike."))
    assert_equal({}, Practice::Payload.passage(instance), "a legacy passage has no Italian layer to add")
  end

  test "the sitting's presenter serves the golden items, and a bilingual testlet's passage without its Italian" do
    body = item("choice")
    stored = body["instances"][0]["display"]
    shuffled = Diagnosis::Rekey.call(display: stored, component: "choice", answer: "o1", seed: "golden")
    instance = Instance.new(Revision.new(JSON.generate(body.except("instances"))), nil, nil, JSON.generate(stored), JSON.generate("o1"), nil)
    payload = Diagnosis::ItemPresenter.new(served: Served.new(instance, shuffled.shown_order.to_json, 1), number: 1, subject: Subject.new("english")).as_json
    item = json(payload[:item])
    assert_equal "diagnosis_item", item["kind"]
    assert_equal SERVED["choice"]["part"].except("options"), item.except("kind", "options")
    assert_equal %w[o1 o2 o3 o4], item["options"].map { |o| o["id"] }
    assert_equal stored["options"].map { |o| o.slice("text", "text_it") }.sort_by(&:to_s), item["options"].map { |o| o.slice("text", "text_it") }.sort_by(&:to_s),
                 "the shuffle moves the Italian with its option"

    testlet = { "kind" => "testlet", "passage_en" => "Tom has a red bike.", "passage_it" => "Tom ha una bici rossa.",
                "sub_items" => [ { "id" => "s1", "component" => "choice", "prompt" => { "stem_en" => "Which colour?", "stem_it" => "Quale colore?" } } ] }
    sub = { "sub_items" => [ { "id" => "s1", "display" => { "options" => [ { "id" => "o1", "text" => "red", "text_it" => "rossa" } ] } } ] }
    instance = Instance.new(Revision.new(JSON.generate(testlet)), nil, nil, JSON.generate(sub), JSON.generate({ "s1" => "o1" }), nil)
    served = Diagnosis::ItemPresenter.new(served: Served.new(instance, JSON.generate({ "s1" => { "options" => [ "o1" ] } }), 2), number: 1, subject: Subject.new("english")).as_json[:item]
    assert_equal "en", served[:lang]
    assert_equal "Tom has a red bike.", served[:passage_en]
    assert_not_includes served.to_json, "bici rossa"
    assert_equal "Quale colore?", served[:sub_items][0][:stem_it]
    assert_equal "en", served[:sub_items][0][:lang]
  end
end
