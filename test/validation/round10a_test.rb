require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/lesson2_fixtures"

# Tooling round 10, slice A (D-408): the tiles' accepted orders (E-TILE-ACCEPT-FORM), the word count of a target-language sentence (a clock time written with a dot, a.m. and p.m.
# before a capital, the opening of a span), and the item shots' queue (lost requests, the lane of their own, the Chrome slots). Each rule has its false positive and the true positive it keeps.
class Round10aTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/lang")
  F = Lesson2Fixtures
  V = ValidationFixtures
  VB = Validation::Bilingual
  TO = Lessons::Blocks::TileOrder

  def en = DIR.join("lesson_en_figures.md").read
  def es = DIR.join("lesson_es_figures.md").read
  def check(md, subject) = Validation::LessonChecks.call(md, subject: subject, context: F.context(subject))
  def found(outcome, *codes) = outcome.findings.select { |f| codes.include?(f.code) }
  def golden(name) = JSON.parse(DIR.join(name).read)

  def tiles(*texts, lang: "en") = texts.each_with_index.map { |t, i| { "id" => (97 + i).chr, "text_#{lang}" => t } }

  # ---- E-TILE-ACCEPT-FORM ---------------------------------------------------------------------------------------------------------

  test "an accepted order that puts the capital tile after another, or the full-stop tile before another, is E-TILE-ACCEPT-FORM; the key and an order that keeps both in place are not" do
    sentence = tiles("When the bus arrived,", "we were waiting", "in the rain.")
    problems = ->(**o) { TO.form_problems({ "tiles" => sentence, "answer" => %w[a b c] }.merge(o.transform_keys(&:to_s))) }
    assert_empty problems.call, "the key is a sentence"
    assert_empty problems.call(accept: [ %w[a b c] ]), "the key as an accepted order"
    both = problems.call(accept: [ %w[c a b] ])
    assert_equal 2, both.size
    assert(both.any? { |m| m.include?('"in the rain."') && m.include?("must be the last") })
    assert(both.any? { |m| m.include?('"When the bus arrived,"') && m.include?("must be the first") })
    # lower-case tiles with no final stop: any order is a sentence
    plain = tiles("when the bus arrived", "we were waiting", "in the rain")
    assert_empty TO.form_problems({ "tiles" => plain, "answer" => %w[a b c], "accept" => [ %w[c a b] ] })
    # the stop tile moved but the capital stays first: only the stop is told
    assert_equal 1, problems.call(accept: [ %w[a c b] ]).size
  end

  test "a name, I and a word of no list keep their capital anywhere; a capital in the middle of the key is a name; an error value is not an accepted order" do
    named = tiles("Picasso died", "in 1973")
    assert_empty TO.form_problems({ "tiles" => named, "answer" => %w[a b], "accept" => [ %w[b a] ] }), "Picasso is not in the frequency lists: a name"
    first_person = tiles("I", "was born", "in Malaga")
    assert_empty TO.form_problems({ "tiles" => first_person, "answer" => %w[a b c], "accept" => [ %w[b a c] ] })
    middle = tiles("we met", "Anna", "yesterday")
    assert_empty TO.form_problems({ "tiles" => middle, "answer" => %w[a b c], "accept" => [ %w[b a c] ] }), "the key does not open with a capital tile: «Anna» is a name"
    errors = { "tiles" => tiles("Mi hermano", "está cansado", "hoy", lang: "es"), "answer" => %w[a b c], "errors" => [ { "answer" => %w[c a b] } ] }
    assert_empty TO.form_problems(errors), "a declared error is no accepted order"
    assert_empty TO.form_problems({ "tiles" => tiles("Ciao", "mondo"), "answer" => %w[a b], "accept" => [ %w[b a] ] }.merge("tiles" => [ { "id" => "a", "text_it" => "Ciao" }, { "id" => "b", "text_it" => "mondo" } ])),
                 "Italian tiles are not read"
  end

  test "«mi hermano está cansado Hoy» and «in the rain. When the bus arrived» are refused in a lesson's tiles check" do
    md = en.sub("::: check select\n", <<~MD + "::: check select\n")
      ::: check tiles
      prompt_en: "Build the sentence."
      prompt_it: "Costruisci la frase."
      tiles:
        - {id: a, text_en: "When the bus arrived,"}
        - {id: b, text_en: "we were waiting"}
        - {id: c, text_en: "in the rain."}
      answer: [a, b, c]
      accept:
        - [c, a, b]
      explain_en: "The sentence starts with a capital and ends with a full stop."
      explain_it: "La frase comincia con la maiuscola e finisce con il punto."
      :::

    MD
    bad = found(check(md, "english"), "E-TILE-ACCEPT-FORM")
    assert_equal 2, bad.size, bad.map(&:message).inspect
    assert_equal [ "accept" ], bad.map { |f| f.field.split("/").last }.uniq
    fixed = md.sub("- [c, a, b]", "- [a, c, b]").sub('"in the rain."', '"in the rain"').sub('"When the bus arrived,"', '"when the bus arrived,"')
    assert_empty found(check(fixed, "english"), "E-TILE-ACCEPT-FORM")
  end

  def ordering_item(words, accept: nil)
    item = golden("item_choice.json").merge("component" => "ordering")
    item["prompt"] = { "stem_en" => "Put the words in order to build the sentence.", "stem_it" => "Metti le parole in ordine per costruire la frase." }
    item["instances"].each_with_index do |inst, i|
      ids = words.each_index.map { |k| "e#{k + 1}" }
      inst["display"] = { "stem_en" => "Build the sentence #{i + 1}.", "elements" => words.each_with_index.map { |w, k| { "id" => ids[k], "text" => w } } }
      inst["answer"] = ids
      inst["errors"] = [ { "code" => "en_make_do_swap", "value" => ids.reverse } ]
      inst["accept"] = accept if accept
      inst["solution"] = { "steps" => [ { "text_en" => "The subject comes first.", "text_it" => "Il soggetto viene prima." } ], "final" => words.join(" ") }
    end
    item
  end

  def run_item(item)
    Validation::Rules.with(practice: { min_static_instances: 2, min_instances_per_code: 1 }) do
      context = Validation::Context.new(subject: "english", skill: ->(key) { { "key" => key, "errors" => [ { "code" => "en_make_do_swap", "implicates" => [] } ] } }, graph_present: true,
                                        source_line: ->(_, _) { nil }, reference_body: ->(_) { nil })
      Validation::ItemRunner.new(files: V.files_for(item), context: context, grandfathered: false).call
    end
  end

  test "an ordering instance of word tiles: an accepted order with the capital or the full stop in the middle is E-TILE-ACCEPT-FORM" do
    words = [ "When the bus arrived,", "we were waiting", "in the rain." ]
    bad = run_item(ordering_item(words, accept: [ %w[e3 e1 e2] ])).findings.select { |f| f.code == "E-TILE-ACCEPT-FORM" }
    assert_equal %w[/instances/0/accept /instances/0/accept /instances/1/accept /instances/1/accept], bad.map(&:field)
    ok = run_item(ordering_item([ "when the bus arrived,", "we were waiting", "in the rain" ], accept: [ %w[e3 e1 e2] ])).findings.select { |f| f.code == "E-TILE-ACCEPT-FORM" }
    assert_empty ok
  end

  # ---- the word count --------------------------------------------------------------------------------------------------------------

  def long(text, lang = "en") = VB.target_report(lang, text, level: false)[:long]

  test "a clock time written with a dot is one word, like 10:00; a decimal that is no hour stays two" do
    assert_equal 15, long("We wake up at 10.00 every day and then we go to school on foot")
    assert_equal 15, long("We wake up at 10:00 every day and then we go to school on foot")
    assert_equal 1, Validation::Readability.count_words("10.00")
    assert_equal 1, Validation::Readability.count_words("7.30")
    assert_equal 1, Validation::Readability.count_words("0.15")
    assert_equal 2, Validation::Readability.count_words("25.00"), "no such hour"
    assert_equal 2, Validation::Readability.count_words("10.75"), "no such minute"
    assert_equal 3, Validation::Readability.count_words("12.1.3"), "a number with two dots is no time"
  end

  test "a.m. and p.m. close a sentence when a capital follows, as a.C. does; before a lower-case word they do not; e.g. never does" do
    sentences = ->(text) { VB.target_sentences(VB.sentence_text(text)) }
    assert_equal [ "The party ends at 10.00 p.m.", "They go home." ], sentences.("The party ends at 10.00 p.m. They go home.")
    assert_equal [ "It starts at 8 p.m. and ends at 10 p.m." ], sentences.("It starts at 8 p.m. and ends at 10 p.m.")
    assert_equal [ "It starts at 8 p.m. and ends at 10 p.m.", "Then we go home." ], sentences.("It starts at 8 p.m. and ends at 10 p.m. Then we go home.")
    assert_equal [ "Bring food, e.g. Pizza or cake." ], sentences.("Bring food, e.g. Pizza or cake.")
    assert_equal 7, long("The party ends at 10.00 p.m. They all go home now and sleep")
    assert_equal 6, long("The party ends at 10.00 p.m. They go home"), "the longest sentence, not the sum"
  end

  test "the opening of a span is markup, not a word: [[g:term]] and [[time:words]] count the words inside" do
    assert_equal 3, Validation::Readability.count_words("Una [[g:sillaba]] è")
    assert_equal 5, Validation::Readability.count_words("We eat [[g:fair trade]] now")
    assert_equal 2, Validation::Readability.count_words("[[en|it:Come on]]")
    assert_equal 9, long("We eat [[g:pizza]] and cake at the party today")
  end

  # ---- the item shots' queue --------------------------------------------------------------------------------------------------------

  test "the shots have a Chrome lane of their own and the lanes have as many threads as there are slots" do
    queues = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true).dig("production", "workers")
    lane = ->(name) { queues.find { |w| Array(w["queues"]).include?(name) } }
    assert_equal "chrome_shots", RenderItemRevisionJob.new.queue_name
    assert_equal 1, lane.("chrome_shots")["threads"]
    assert_not_equal lane.("chrome"), lane.("chrome_shots"), "not the lane of the validations and the lesson renders"
    assert_equal Validation::ChromeRunner::SLOTS, lane.("chrome")["threads"] + lane.("chrome_shots")["threads"]
    assert_equal 3, Validation::ChromeRunner::SLOTS
    %w[ValidateItemRevisionJob RenderLessonRevisionJob ValidatePageRevisionJob].each { |name| assert_equal "chrome", name.constantize.new.queue_name }
    assert_equal 1, lane.("chrome_shots")["processes"]
  end

  test "the recurring task that expires the lost shot requests is configured" do
    recurring = YAML.safe_load_file(Rails.root.join("config/recurring.yml"), aliases: true)["production"]
    assert_equal "ExpireLostItemRendersJob", recurring.dig("expire_lost_item_renders", "class")
  end
end
