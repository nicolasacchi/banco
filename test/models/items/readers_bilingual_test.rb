require "test_helper"

# D-402, slice 1: every reader of the stem the student saw reads the target layer of a bilingual item (and the one text of a legacy item): the grader's
# frame, the shown math, the overlap texts, the sitting's summary, the teacher's view, the search index and the reminder's leak check.
class ItemsReadersBilingualTest < ActiveSupport::TestCase
  Subject = Struct.new(:key)
  Revision = Struct.new(:body_json)
  Row = Struct.new(:id, :item_revision, :display_json, :answer_json, :errors_json, :solution_json, :hints_json, :accept_json)

  BLANK = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/item_blank.json")))
  CHOICE = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/item_choice.json")))

  def row(item, n = 0)
    inst = item["instances"][n]
    Row.new(n + 1, Revision.new(JSON.generate(item.except("instances"))), JSON.generate(inst["display"]), JSON.generate(inst["answer"]), JSON.generate(inst["errors"]),
            JSON.generate(inst["solution"]), nil, nil)
  end

  test "the grader's frame is read from the target stem, never from the Italian translation" do
    spec = Grading::Spec.from_hash(BLANK.merge("display" => { "stem_en" => "She ___ to school by bus.", "stem_it" => "Lei ___ a scuola in ___ autobus." }, "component" => "normalized_text"))
    frame = Grading::Frame.for_spec(spec)
    assert_equal %w[she], frame.prefix
    assert_equal %w[to school by bus], frame.suffix
    assert_equal "Write the word that fits the gap.", spec.prompt_stem
    assert_includes spec.item_texts, "She ___ to school by bus."
    assert_not_includes spec.item_texts, "Lei ___ a scuola in ___ autobus."
  end

  test "the frame sees an instruction in English or Spanish as an instruction, not as a second blank" do
    %w[Write\ the\ words\ in\ place\ of\ ___ Escribe\ las\ palabras\ en\ lugar\ de\ ___ Escribe\ en\ el\ lugar\ de\ ___ Scrivi\ al\ posto\ di\ ___].each do |line|
      frame = Grading::Frame.from_stem("#{line.tr('\\', ' ')}\n→ My aunt ___ a red car.")
      assert_equal %w[my aunt], frame&.prefix, line
    end
    assert_nil Grading::Frame.from_stem("Fill the gap.\n→ My aunt ___ a red car. ___"), "two blanks that are not an instruction are still no frame"
  end

  test "the math the student was shown is the target stem's" do
    spec = Grading::Spec.from_hash("component" => "expression", "prompt" => { "stem_en" => "Solve $x+1=3$.", "stem_it" => "Risolvi $x+1=3$." }, "display" => { "stem_en" => "Now $2x$." })
    assert_equal [ "x+1=3", "2x" ], spec.stem_expressions
  end

  test "the overlap texts of a display are the target stem and passage, so two translations of one text are one text" do
    texts = Diagnosis::InstanceTexts.call({ "stem_en" => "Tom has a bike.", "stem_it" => "Tom ha una bici.", "passage_en" => "A long text.", "passage_it" => "Un testo lungo.",
                                            "options" => [ { "id" => "o1", "text" => "red", "text_it" => "rossa" } ] })
    assert_equal [ "tom has a bike", "a long text", "red" ], texts[:strong]
    legacy = Diagnosis::InstanceTexts.call({ "stem_it" => "Tom has a bike.", "passage_it" => "A long text.", "options" => [ { "id" => "o1", "text" => "red" } ] })
    assert_equal texts[:strong], legacy[:strong]
  end

  test "the sitting's summary reads the target prompt, keeps its translation and shows the steps of the layer he read" do
    summary = Diagnosis::Summary.allocate
    body = { "kind" => "short_answer", "passage_en" => "Tom has a red bike.", "passage_it" => "Tom ha una bici rossa.", "prompt" => { "stem_en" => "What colour?", "stem_it" => "Che colore?" } }
    instance = Row.new(1, Revision.new("{}"), JSON.generate({ "stem_en" => "Look.", "stem_it" => "Guarda." }))
    assert_equal "Tom has a red bike. What colour? Look.", summary.send(:prompt_text, body, instance)
    assert_equal "Tom ha una bici rossa. Che colore? Guarda.", summary.send(:prompt_translation, body, instance)
    legacy = { "kind" => "short_answer", "passage_it" => "Tom has a red bike.", "prompt" => { "stem_it" => "What colour?" } }
    assert_equal "Tom has a red bike. What colour?", summary.send(:prompt_text, legacy, Row.new(1, nil, "{}"))
    assert_nil summary.send(:prompt_translation, legacy, Row.new(1, nil, "{}"))
  end

  test "the teacher reads a bilingual instance in both layers and a legacy one as before" do
    view = Teacher::InstanceView.new(row(BLANK), JSON.parse(row(BLANK).item_revision.body_json), 1)
    assert_equal "Write the word that fits the gap. — Scrivi la parola che completa lo spazio. She ___ to school by bus. — Lei ___ a scuola in autobus.", view.stem
    assert_equal [ "With she the verb takes -es: goes. — Con she il verbo prende -es: goes." ], view.steps
    assert_equal "goes — goes: lei va a scuola in autobus.", view.final
    assert_equal BLANK["hints_en"].zip(BLANK["hints_it"]).map { |en, it| "#{en} — #{it}" }, view.hints
    assert_equal "With she, the verb takes an ending. — Con she il verbo prende una desinenza.", view.errors.first[:message]

    choice = Teacher::InstanceView.new(row(CHOICE), JSON.parse(row(CHOICE).item_revision.body_json), 1)
    assert_equal "o1: make / do — fare / fare", choice.choices["options"].first
    assert_equal "o1: make / do — fare / fare", choice.key

    legacy_body = { "kind" => "practice_item", "component" => "choice", "prompt" => { "stem_it" => "Scegli." }, "hints_it" => [ "Pensa." ],
                    "error_catalogue" => [ { "code" => "x", "message_it" => "No." } ] }
    legacy = Row.new(1, Revision.new(JSON.generate(legacy_body)), JSON.generate({ "stem_it" => "Dov'è?", "options" => [ { "id" => "o1", "text" => "qui" } ] }), JSON.generate("o1"),
                     JSON.generate([ { "code" => "x", "value" => "o2" } ]), JSON.generate({ "steps" => [ { "text_it" => "Passo." } ], "final" => "qui" }), nil, nil)
    view = Teacher::InstanceView.new(legacy, legacy_body, 1)
    assert_equal [ "Scegli. Dov'è?", [ "Passo." ], "qui", [ "Pensa." ], "No." ], [ view.stem, view.steps, view.final, view.hints, view.errors.first[:message] ]
    assert_equal "o1: qui", view.key
  end

  test "the search index holds both layers of a bilingual item, so the teacher finds it by the Italian words too" do
    body = CHOICE.except("instances")
    text = Search::Builders::Items.item_text(body).join(" ")
    assert_includes text, "Choose the two words"
    assert_includes text, "Scegli le due parole"
    assert_includes text, "compagno di ciascuno"
    assert_includes text, "Which verb is the partner"
    assert_includes text, "Pensa ai nomi"
    instance = Search::Builders::Items.instance_text(body, CHOICE["instances"][0]["display"], Subject.new("english")).join(" ")
    assert_includes instance, "On Saturdays I ___ my bed"
    assert_includes instance, "Il sabato io ___ il letto"
    assert_includes instance, "fare / fare"
    assert_not_includes instance, " en "
    assert_includes Search::Builders::Items.instance_head(body, CHOICE["instances"][0]["display"], Subject.new("english")), "Choose the two words"

    legacy = { "component" => "choice", "prompt" => { "stem_it" => "Scegli." }, "hints_it" => [ "Pensa." ] }
    assert_includes Search::Builders::Items.item_text(legacy), "Scegli."
    assert_equal [ "Scegli.", "Dov'è?", "qui" ], Search::Builders::Items.instance_text(legacy, { "stem_it" => "Dov'è?", "options" => [ { "id" => "o1", "text" => "qui" } ] }, Subject.new("english"))
  end

  test "the reminder never shows a message whose target or Italian layer states the answer" do
    quiet = Practice::Reminder.text_for(row(CHOICE), "en_make_do_swap", ->(_) { "Descrizione." }, [ "make / do" ])
    assert_equal [ "item", "en" ], [ quiet.source, quiet.lang ]
    entry_en = Practice::Reminder.text_for(row(CHOICE), "en_make_do_swap", ->(_) { "Descrizione." }, [ "Look at the nouns" ])
    assert_equal "graph", entry_en.source, "the target layer states it: the graph's description is used"
    entry_it = Practice::Reminder.text_for(row(CHOICE), "en_make_do_swap", ->(_) { "Descrizione." }, [ "compagno di ciascuno" ])
    assert_equal "graph", entry_it.source, "the Italian layer states it: the graph's description is used"
    assert_equal [ "fare / fare", "make / do" ].sort, Practice::Reminder.needles(row(CHOICE)).sort, "the key option in both layers"
  end
end

# D-402, the teacher's tools: the grading vector a correction prints, the instance block of an attempt, and the error catalogue of the item card.
class ItemsTeacherToolsBilingualTest < ActiveSupport::TestCase
  Revision = Struct.new(:id, :body_json, :item)
  Item = Struct.new(:key)
  Row = Struct.new(:id, :item_revision, :display_json, :answer_json, :errors_json, :solution_json, :hints_json, :accept_json, :fingerprint)
  Shown = Struct.new(:body, :answer) do
    def words(raw) = raw
  end

  BLANK = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/item_blank.json")))

  def row
    inst = BLANK["instances"][0]
    Row.new(7, Revision.new(3, JSON.generate(BLANK.except("instances")), Item.new("bil-blank")), JSON.generate(inst["display"]), JSON.generate(inst["answer"]),
            JSON.generate(inst["errors"]), JSON.generate(inst["solution"]), nil, nil, "fp")
  end

  test "a grading vector of a bilingual item carries the stem in both layers, so the grader's frame reads the target one" do
    item = Teacher::GradingVectors.allocate.send(:item_of, row)
    assert_equal({ "stem_en" => "Write the word that fits the gap.", "stem_it" => "Scrivi la parola che completa lo spazio." }, item["prompt"])
    assert_equal %w[stem_en stem_it], item["display"].keys.grep(/stem/)
    spec = Grading::Spec.from_hash(item.merge("component" => "normalized_text"))
    assert_equal "Write the word that fits the gap.", spec.prompt_stem
    assert_equal %w[she], Grading::Frame.for_spec(spec).prefix
  end

  test "a grading vector of a legacy item keeps its one stem" do
    legacy = BLANK.except("instances").merge("prompt" => { "stem_it" => "Scrivi." }).except("hints_en", "hints_it")
    legacy_row = row.dup.tap { |r| r.item_revision = Revision.new(3, JSON.generate(legacy), Item.new("k")); r.display_json = JSON.generate({ "stem_it" => "She ___ home." }) }
    assert_equal({ "stem_it" => "Scrivi." }, Teacher::GradingVectors.allocate.send(:item_of, legacy_row)["prompt"])
  end

  test "the matched errors of an attempt carry the message in both layers; a legacy one keeps message_it alone" do
    shown = Shown.new(BLANK.except("instances"), "goes")
    block = Attempts::InstanceBlock.call(row, shown, "go", [ "en_missing_third_s", "nope" ])
    assert_equal [ { code: "en_missing_third_s", message_en: "With she, the verb takes an ending.", message_it: "Con she il verbo prende una desinenza." }, { code: "nope" } ],
                 block[:matched_errors]

    legacy_body = BLANK.except("instances").merge("error_catalogue" => [ { "code" => "x", "message_it" => "No." } ])
    legacy = Attempts::InstanceBlock.call(row, Shown.new(legacy_body, "goes"), "go", [ "x" ])
    assert_equal [ { code: "x", message_it: "No." } ], legacy[:matched_errors]
  end

  test "the item card's catalogue shows target and Italian, a legacy catalogue its one message" do
    html = ApplicationController.render(inline: '<% catalogue.each do |e| %><q><%= Items::Text.both_of(e, "message") %></q><% end %>',
                                        locals: { catalogue: BLANK["error_catalogue"] + [ { "code" => "x", "message_it" => "Rileggi." } ] })
    assert_includes html, "<q>With she, the verb takes an ending. — Con she il verbo prende una desinenza.</q>"
    assert_includes html, "<q>Rileggi.</q>"
  end
end
