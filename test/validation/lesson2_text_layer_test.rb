require "test_helper"
require_relative "../support/lesson2_fixtures"

# T2, the text layer (D-281, WAVE2 1.11): language spans and target-language keys with the lint split, the cloze exemption, W-LANG-LEVEL,
# code spans, the glossary. The checks run on the parsed body of base.md changed after parsing, for the subject named.
class Lesson2TextLayerTest < ActiveSupport::TestCase
  F = Lesson2Fixtures

  def run_checks(subject = "english")
    findings = Validation::Findings.new
    parsed = F.check(F.read("base.md")).parsed
    parsed.body = Marshal.load(Marshal.dump(parsed.body))
    yield parsed.body
    Validation::Lesson2Checks::Run.new(parsed, subject, F.context("math"), findings).call
    findings
  end

  def text_card(body, *texts)
    block = ->(t, n) { { "n" => n, "type" => "text", "line" => 40 + n, "text_it" => t } }
    body["cards"][1]["blocks"] = texts.each_with_index.map { |t, i| block.call(t, i + 1) } + body["cards"][1]["blocks"].reject { |b| b["type"] == "text" }
  end

  def codes(findings, code) = findings.select { |f| f.code == code }

  test "a language span is plain English in an english lesson and E-LESSON-LANG in a math lesson" do
    ok = run_checks("english") { |b| text_card(b, "Dì [[en:When I arrive, I will call you.]] a Luca.") }
    assert_empty codes(ok, "E-LESSON-LANG")
    bad = run_checks("math") { |b| text_card(b, "Dì [[en:When I arrive, I will call you.]] a Luca.") }
    assert_equal 1, codes(bad, "E-LESSON-LANG").size
    assert_match(/does not teach English/, codes(bad, "E-LESSON-LANG").first.message)
    es = run_checks("english") { |b| text_card(b, "Dì [[es:Cuando llegue, te llamo.]] a Luca.") }
    assert_equal 1, codes(es, "E-LESSON-LANG").size, "english does not teach Spanish"
    la = run_checks("history") { |b| text_card(b, "Il [[la:princeps]] governa.") }
    assert_empty codes(la, "E-LESSON-LANG")
  end

  test "the Italian lint skips the words of a span and a role span of a language subject; the target set applies to them" do
    long = Array.new(30) { "word" }.join(" ")
    ok = run_checks("english") { |b| text_card(b, "Leggi [[en:#{long}.]] ora.") }
    sentence = codes(ok, "E-READ").select { |f| f.detail[:rule].to_s.start_with?("target_sentence_words") }
    assert_equal 1, sentence.size, "a 30-word English sentence breaks the target-language set (12)"
    assert_not codes(ok, "E-READ").any? { |f| f.detail[:rule].to_s.start_with?("sentence_length") }, "and not the Italian set"
    role = run_checks("english") { |b| text_card(b, "[[time:#{long}]] e basta.") }
    assert codes(role, "E-READ").any? { |f| f.detail[:rule].to_s.start_with?("target_sentence_words") }
    italian = run_checks("english") { |b| text_card(b, "[[time|it:#{long}]] e basta.") }
    assert codes(italian, "E-READ").any? { |f| f.detail[:rule].to_s.start_with?("sentence_length") }, "|it makes the role span Italian again"
    assert_not codes(italian, "E-READ").any? { |f| f.detail[:rule].to_s.start_with?("target_sentence_words") }
  end

  test "W-LANG-LEVEL names words outside the first 3000, the glossary and teaches_en" do
    hard = run_checks("english") { |b| text_card(b, "Guarda [[en:The quokka is ubiquitous.]] ora.") }
    assert_equal 1, codes(hard, "W-LANG-LEVEL").size
    assert_includes codes(hard, "W-LANG-LEVEL").first.message, "quokka"
    assert_includes codes(hard, "W-LANG-LEVEL").first.message, "ubiquitous"
    taught = run_checks("english") do |b|
      b["teaches_en"] = %w[quokka]
      b["glossary"] = [ { "term_it" => "ubiquitous", "def_it" => "Che si trova ovunque." } ]
      text_card(b, "Guarda [[en:The quokka is ubiquitous.]] ora.")
    end
    assert_empty codes(taught, "W-LANG-LEVEL")
    easy = run_checks("english") { |b| text_card(b, "Guarda [[en:When I get home, I'll call you.]] ora.") }
    assert_empty codes(easy, "W-LANG-LEVEL"), "contractions and inflected forms are looked up by their plain form"
    names = run_checks("english") { |b| text_card(b, "Guarda [[en:Then Luca called Maria.]] ora.") }
    assert_empty codes(names, "W-LANG-LEVEL"), "a capitalised word inside a sentence is a name"
  end

  test "a key _en, _es or _la holds that language: taught by the subject, not Italian, one language per figure" do
    dialogue = ->(key, text) { { "n" => 7, "type" => "dialogue", "line" => 50, "title_it" => "Due amici", "speakers" => [ { "id" => "t", "name" => "Tom" } ], "lines" => [ { "speaker" => "t", key => text, "gloss_it" => "Ciao" }, { "speaker" => "t", key => text, "gloss_it" => "Ciao" } ] } }
    fine = run_checks("english") { |b| b["cards"][1]["blocks"] << dialogue.call("text_en", "See you soon.") }
    assert_empty codes(fine, "E-LESSON-LANG")
    wrong = run_checks("english") { |b| b["cards"][1]["blocks"] << dialogue.call("text_es", "Hasta pronto.") }
    assert_equal 2, codes(wrong, "E-LESSON-LANG").size
    italian = run_checks("english") { |b| b["cards"][1]["blocks"] << dialogue.call("text_en", "Il gatto è sul tavolo.") }
    assert codes(italian, "E-LESSON-LANG").any? { |f| f.message.include?("Italian") }
    two = run_checks("english") do |b|
      b["cards"][1]["blocks"] << { "n" => 7, "type" => "diagram", "line" => 50, "diagram" => { "type" => "sentence", "alt_it" => "Una frase con due lingue.", "text_en" => "Hello there", "parts" => [ { "text_en" => "Hello", "role" => "subject" }, { "text_es" => "hola", "role" => "verb" } ] } }
    end
    assert codes(two, "E-LESSON-LANG").any? { |f| f.message.include?("one language besides Italian") }
  end

  test "the cloze cue after the gap is not an answer in the prompt (D-110 in lessons); the bare answer still is" do
    check = ->(prompt) { { "n" => 7, "type" => "check", "line" => 50, "component" => "normalized_text", "prompt_it" => prompt, "answer" => "get" } }
    cloze = run_checks("english") { |b| b["cards"][1]["blocks"] << check.call("Completa: When I ___ (get) home, I call you.") }
    assert_empty codes(cloze, "W-CHECK-ANSWER-IN-PROMPT")
    leak = run_checks("english") { |b| b["cards"][1]["blocks"] << check.call("Completa: When I get home, I call you.") }
    assert_equal 1, codes(leak, "W-CHECK-ANSWER-IN-PROMPT").size
  end

  test "a glossary word must be in the glossary, a term is listed once, and the definitions shown under a card count as apparatus" do
    glossary = [ { "term_it" => "promulgazione", "def_it" => "Il capo dello Stato firma la legge e la rende valida." } ]
    ok = run_checks("math") { |b| b["glossary"] = glossary; text_card(b, "La [[g:promulgazione]] chiude l'iter.") }
    assert_empty codes(ok, "E-LESSON-BLOCK").select { |f| f.message.include?("glossary") }
    unknown = run_checks("math") { |b| b["glossary"] = glossary; text_card(b, "La [[g:firma]] chiude l'iter.") }
    assert_equal 1, codes(unknown, "E-LESSON-BLOCK").select { |f| f.message.include?("not a term of the lesson's glossary") }.size
    twice = run_checks("math") { |b| b["glossary"] = glossary + glossary }
    assert codes(twice, "E-LESSON-BLOCK").any? { |f| f.message.include?("twice") }
    heavy = run_checks("math") do |b|
      b["glossary"] = (1..12).map { |i| { "term_it" => "termine#{('a'.ord + i).chr}", "def_it" => Array.new(22, "pari").join(" ") + "." } }
      text_card(b, b["glossary"].map { |g| "Vedi [[g:#{g['term_it']}]]." }.join(" "))
    end
    assert codes(heavy, "E-LESSON-APPARATUS-WORDS").any?, "twelve definitions of 30 words open under one card are over the apparatus budget"
  end

  test "Lessons::Lexicon looks words up by their plain form" do
    %w[visit visits visited visiting call called calling stopped quickly don't].each { |w| assert Lessons::Lexicon.known?("en", w), w }
    assert_not Lessons::Lexicon.known?("en", "quokka")
    %w[casa casas llamar].each { |w| assert Lessons::Lexicon.known?("es", w), w }
    assert Lessons::Lexicon.known?("la", "anything"), "no list for Latin: nothing to warn"
  end

  test "E-CHEM-SYMBOL: every symbol inside \\ce and \\mathrm is an element symbol, case-exact" do
    good = run_checks("chemistry") { |b| text_card(b, "Scrivi $\\ce{2H2 + O2 -> 2H2O}$ e $\\ce{Fe^{3+} + 3OH^- -> Fe(OH)3 v}$ con $\\pu{25 kJ/mol}$ e $\\mathrm{NaCl}$.") }
    assert_empty codes(good, "E-CHEM-SYMBOL")
    assert_empty codes(good, "E-LESSON-MARKUP")
    bad = run_checks("chemistry") { |b| text_card(b, "Scrivi $\\ce{Xx2 + Hcl}$ ora.") }
    assert_equal %w[Hcl Xx], codes(bad, "E-CHEM-SYMBOL").map { |f| f.detail[:symbol] }.sort
    case_wrong = run_checks("biology") { |b| text_card(b, "Scrivi $\\ce{NACL}$ ora.") }
    assert_equal %w[A L], codes(case_wrong, "E-CHEM-SYMBOL").map { |f| f.detail[:symbol] }.sort, "NACL is N, A, C, L: A and L are not symbols"
    math = run_checks("math") { |b| text_card(b, "Scrivi $\\ce{H2O}$ ora e $\\mathrm{kJ}$.") }
    assert_equal 1, codes(math, "E-LESSON-MARKUP").select { |f| f.message.include?("chemistry and biology") }.size
    assert_empty codes(math, "E-CHEM-SYMBOL"), "a unit in a math lesson is not an element symbol"
    units = run_checks("chemistry") { |b| text_card(b, "Vale $\\mathrm{kJ/mol}$, $\\mathrm{Hz}$ e $\\mathrm{L}$.") }
    assert_empty codes(units, "E-CHEM-SYMBOL")
    block = run_checks("chemistry") { |b| b["cards"][1]["blocks"] << { "n" => 7, "type" => "math", "line" => 50, "tex" => "\\ce{Xy + H2}" } }
    assert_equal 1, codes(block, "E-CHEM-SYMBOL").size, "a math block is read too"
  end

  test "Lessons::ChemSymbols has the 118 symbols and reads the table when T7 has written it" do
    assert_equal 118, Lessons::ChemSymbols::FALLBACK.size
    assert_equal 118, Lessons::ChemSymbols::FALLBACK.uniq.size
    assert Lessons::ChemSymbols.known?("Fe")
    assert_not Lessons::ChemSymbols.known?("FE")
    if Lessons::VettedData.written?("chem/elements")
      assert_equal Lessons::ChemSymbols::FALLBACK.sort, Lessons::VettedData.table("chem/elements")["elements"].map { |e| e["symbol"] }.sort
    end
  end
end
