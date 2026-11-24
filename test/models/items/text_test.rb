require "test_helper"

# D-402: Items::Text is the one reader of the text the student sees. A bilingual hash is read in its target language, a legacy one as it always was.
class ItemsTextTest < ActiveSupport::TestCase
  CHOICE = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/item_choice.json")))

  test "a bilingual prompt reads as its target text and keeps its Italian one tap away" do
    prompt = CHOICE["prompt"]
    assert_equal prompt["stem_en"], Items::Text.stem(prompt)
    assert_equal prompt["stem_it"], Items::Text.translation(prompt, "stem")
    assert_equal "en", Items::Text.lang(prompt, "stem")
    assert_equal "#{prompt['stem_en']} — #{prompt['stem_it']}", Items::Text.both_of(prompt, "stem")
  end

  test "a legacy prompt reads as its one text, with no translation and no language" do
    prompt = { "stem_it" => "Scegli la parola." }
    assert_equal "Scegli la parola.", Items::Text.stem(prompt)
    assert_nil Items::Text.translation(prompt, "stem")
    assert_nil Items::Text.lang(prompt, "stem")
    assert_equal "Scegli la parola.", Items::Text.both_of(prompt, "stem")
    assert_equal({ stem_it: "Scegli la parola." }, Items::Text.pair(prompt, "stem"))
  end

  test "the pair keeps the names of the author in the served keys" do
    assert_equal({ instance_stem_en: "She ___ to school by bus.", instance_stem_it: "Lei ___ a scuola in autobus." },
                 Items::Text.pair({ "stem_en" => "She ___ to school by bus.", "stem_it" => "Lei ___ a scuola in autobus." }, "stem", "instance_stem"))
    assert_equal({ title_it: nil }, Items::Text.pair({}, "stem", "title"))
  end

  test "the readers of the other fields: stems, hints, messages, steps, a spanish pair" do
    entry = CHOICE["error_catalogue"][0]
    assert_equal entry["message_en"], Items::Text.message(entry)
    assert_equal CHOICE["hints_en"], Items::Text.hints(CHOICE)
    assert_equal CHOICE["instances"][0]["solution"]["steps"][0]["text_en"], Items::Text.step(CHOICE["instances"][0]["solution"]["steps"][0])
    assert_equal %w[Hola Ciao], Items::Text.stems({ "prompt" => { "stem_es" => "Hola", "stem_it" => "Ciao" } }, { "stem_it" => "Ciao" })
    assert_equal "es", Items::Text.lang({ "stem_es" => "Hola", "stem_it" => "Ciao" }, "stem")
  end

  test "both layers on one line only when there is a different translation" do
    assert_equal "a", Items::Text.both("a", nil)
    assert_equal "a", Items::Text.both("a", "")
    assert_equal "7", Items::Text.both("7", "7")
    assert_equal "make / do — fare / fare", Items::Text.option_both({ "text" => "make / do", "text_it" => "fare / fare" })
    assert_equal "make / do", Items::Text.option_both({ "id" => "o1", "text" => "make / do" })
    assert_equal "goes — va", Items::Text.final_both({ "final" => "goes", "final_it" => "va" })
  end

  test "the keys of a passage that exist: the Italian one only for the pair" do
    assert_equal({ "passage_it" => "Il testo." }, Items::Text.passage_keys({ "passage_it" => "Il testo.", "stem_it" => "x" }))
    assert_equal({ "passage_en" => "The text.", "passage_it" => "Il testo." }, Items::Text.passage_keys({ "passage_en" => "The text.", "passage_it" => "Il testo." }))
    assert_equal "The text.", Items::Text.passage({ "passage_en" => "The text.", "passage_it" => "Il testo." })
    assert_equal({}, Items::Text.passage_keys(nil))
  end
end
