require "test_helper"

# The readability lint (E-READ rules, E-PHRASE, E-MESSAGE and the W- warnings).
class ReadabilityTest < ActiveSupport::TestCase
  def lint(text, role: :text)
    findings = Validation::Findings.new
    Validation::Readability.lint(text, field: "/t", role: role, findings: findings)
    findings
  end

  def rules(text, **opts) = lint(text, **opts).select { |f| f.code == "E-READ" }.map { |f| f.detail[:rule] }

  test "a plain Italian instruction passes with no finding" do
    assert_empty lint("Calcola il **perimetro** del rettangolo. I lati misurano $3$ cm e $5$ cm.", role: :stem).to_a
  end

  test "a sentence over 25 words is E-READ sentence_length" do
    long = ([ "parola" ] * 26).join(" ") + "."
    assert_equal %w[sentence_length], rules(long)
    assert_empty rules(([ "parola" ] * 25).join(" ") + ".")
  end

  test "an instruction over 60 words is E-READ stem_length even in short sentences" do
    stem = ([ "Una frase breve di sei parole." ] * 11).join(" ")
    assert_includes rules(stem, role: :stem), "stem_length"
    assert_not_includes rules(stem, role: :text), "stem_length"
  end

  test "a dotted abbreviation such as a.C. counts as one word (D-155)" do
    era = "Il 509 a.C. segna la fine della monarchia, il 27 a.C. la nascita dell'impero e il 476 d.C. la caduta dell'impero romano d'Occidente."
    assert_equal 23, era.gsub(Validation::Readability::DOTTED, "x").scan(Validation::Readability::WORD).size
    filler = ([ "parola" ] * 12).join(" ")
    assert_empty rules("#{filler} nel 509 a.C. e nel 27 a.C. e nel 44 a.C. poi.")  # 12 + 12 = 24 words, 30 counted per letter
    assert_equal %w[sentence_length], rules(([ "parola" ] * 26).join(" ") + " a.C.")
  end

  test "abbreviations do not split sentences" do
    assert_empty rules("Usa i numeri primi, ad es. 2 e 3, ecc. e poi scegli.")
  end

  test "the era abbreviations a.C., d.C. and sec. do not split a sentence" do
    msg = "Hai preso le centinaia senza aggiungere 1. Il 350 a.C. e il 350 d.C. sono nel IV secolo."
    assert_not_includes lint(msg, role: :message).map(&:code), "E-MESSAGE"
    assert_not_includes lint("Il sec. IV d.C. fu lungo. Il 44 a.C. è prima.", role: :message).map(&:code), "E-MESSAGE"
    # the content agent's report: a lowercase word after a.C. keeps the sentence whole
    assert_not_includes lint("Hai messo prima il fatto con la data a.C. più piccola. Avanti Cristo, più grande è il numero, più antico è il fatto.", role: :message).map(&:code), "E-MESSAGE"
    assert_empty lint("Nel 509 a.C. finisce la monarchia e nasce la Repubblica romana.", role: :text).select { |f| f.code == "E-READ" }
    # a capital after the era abbreviation, or the end of the text, still ends the sentence
    assert_includes lint("Accadde nel 44 a.C. Poi nel 10 d.C. Poi altro.", role: :message).map(&:code), "E-MESSAGE"
  end

  test "the dotted school abbreviations m.c.m., M.C.D. and C.E. do not split a message" do
    msg = "Per il m.c.m. ogni fattore primo va preso con l'esponente più alto. L'esponente più basso si usa per il M.C.D. dei numeri."
    assert_not_includes lint(msg, role: :message).map(&:code), "E-MESSAGE"
    assert_not_includes lint("Controlla la C.E. della frazione. Poi semplifica.", role: :message).map(&:code), "E-MESSAGE"
    assert_includes lint("Il m.c.m. è uno. Il M.C.D. è due. Il resto è tre.", role: :message).map(&:code), "E-MESSAGE"
  end

  test "ALL-CAPS words of 3 or more letters are errors except acronyms and Roman numerals" do
    assert_equal %w[all_caps], rules("Leggi con ATTENZIONE la consegna.")
    assert_empty rules("Calcola l'IVA nel secolo XVIII.")
    assert_empty rules("Vale SI o NO.")
  end

  test "markup outside the allowed set" do
    assert_equal %w[markup], rules("Scrivi *in corsivo* la parola.")
    assert_equal %w[markup], rules("Scrivi _in corsivo_ la parola.")
    assert_equal %w[markup], rules("Vai a <b>capo</b>.")
    assert_equal %w[markup], rules("# Titolo\nTesto.")
    assert_equal %w[markup], rules("- uno\n- due")
    assert_empty rules("1. uno\n2. due")
    assert_empty rules("Una parola in **grassetto**.")
    assert_empty rules("Il valore $a_1 * b_2$ resta.")
  end

  test "emoji" do
    assert_equal %w[emoji], rules("Bravo \u{1F600}")
    assert_equal %w[emoji], rules("Fatto ✅")
  end

  test "arrows are not emoji, real pictographs still are (D-095)" do
    assert_equal [], rules("Dopo l'istruzione x \u2190 x + 1, quanto vale x?")
    assert_equal [], rules("Va da A \u2192 B.")
    assert_equal %w[emoji], rules("Fatto \u2B50")
  end

  test "the whole arrows block is allowed except the emoji-capable return arrows (D-127)" do
    assert_equal [], rules("erba \u2192 cavallette \u2192 rane")
    assert_equal [], rules("A \u21D2 B, C \u21D4 D, 2H + O \u21CC H")
    assert_equal [], rules("x \u21A6 y")
    assert_equal %w[emoji], rules("Indietro \u21A9")
  end

  test "the programme's star markers are not emoji, other pictographs still are (D-148)" do
    assert_equal [], rules("La riga \u2605 del programma e la riga \u2606.")
    assert_equal %w[emoji], rules("Fatto \u2603")
    assert_equal %w[emoji], rules("Bravo \u2705")
  end

  test "DDT is an allowed acronym (D-104)" do
    assert_equal [], rules("La fattura accompagna il DDT della merce.")
  end

  test "computer science acronyms are allowed (D-114)" do
    assert_equal [], rules("Ogni carattere ASCII occupa 1 byte; un colore RGB usa tre byte, come un file CSV.")
  end

  test "spreadsheet function names are not all-caps words (D-095)" do
    assert_equal [], rules("Usa SOMMA(A1:A3) e CONTA.SE per contare.")
    assert_equal %w[all_caps], rules("Questo è ASSOLUTAMENTE vero.")
    assert_equal %w[all_caps], rules("Basta. ECCO. Poi vai.")
  end

  test "bold spans: at most 3 spans of at most 4 words" do
    assert_equal %w[bold_spans], rules("**a** e **b** e **c** e **d**.")
    assert_equal %w[bold_span_length], rules("Una **frase con cinque parole qui** sola.")
    assert_empty rules("**a** e **b** e **c**.")
  end

  test "banned phrases are E-PHRASE" do
    f = lint("Scrivi la risposta che cercano.")
    assert_equal [ "E-PHRASE" ], f.map(&:code)
    assert_equal [ "E-PHRASE" ], lint("Il risultato è verificato.").map(&:code)
  end

  test "banned phrases match whole words only (D-105)" do
    assert_empty lint("La lezione di nuoto è un servizio.").map(&:code)
    assert_empty lint("Una lezione costa 20 euro.").map(&:code)
    assert_equal [ "E-PHRASE" ], lint("Lo dice a lezione.").map(&:code)
  end

  test "the suffix -es. ends a sentence; es. (esempio) still does not (D-110)" do
    text = "Dopo s, sh, ch, x, z e in go e do si aggiunge -es. Dopo consonante + y la y diventa -ies, dopo vocale + y si aggiunge -s; have diventa has."
    assert_not_includes lint(text, role: :message).map(&:code), "E-READ"
    long = "Ecco una frase di esempio con " + ([ "parola" ] * 14).join(" ") + ", es. questa e il resto della frase che continua ancora un poco."
    assert_includes lint(long, role: :text).map(&:code), "E-READ"
  end

  test "a message of more than two sentences is E-MESSAGE" do
    assert_includes lint("Primo passo. Secondo passo. Terzo passo.", role: :message).map(&:code), "E-MESSAGE"
    assert_not_includes lint("Primo passo. Secondo passo.", role: :message).map(&:code), "E-MESSAGE"
  end

  test "warnings: absolute word, negative stem, decimal point, self-certification, Gulpease" do
    assert_includes lint("Il risultato è sempre positivo.").map(&:code), "W-ABSOLUTE"
    assert_not_includes lint("Il minore fa da solo gli atti di ordinaria amministrazione.").map(&:code), "W-ABSOLUTE"
    assert_includes lint("Solo il tutore firma. Lei fa da sola.").map(&:code), "W-ABSOLUTE"
    assert_not_includes lint("Da un giorno solo non si conosce il clima. Una volta sola basta.").map(&:code), "W-ABSOLUTE"
    assert_not_includes lint("Hai chiamato bioma un solo ambiente. Qui c'è una sola specie.").map(&:code), "W-ABSOLUTE"
    assert_not_includes lint("I carboidrati formano strutture, non danno solo energia. Non solo energia.").map(&:code), "W-ABSOLUTE"
    assert_includes lint("Non è vero. Solo il tutore firma.").map(&:code), "W-ABSOLUTE"
    assert_includes lint("Firma un atto solo se è presente il tutore.").map(&:code), "W-ABSOLUTE"
    assert_includes lint("Quale frase non è corretta?", role: :stem).map(&:code), "W-NEGATIVE-STEM"
    assert_not_includes lint("Quando è vera «non ($x$ è pari e $y$ è dispari)»?", role: :stem).map(&:code), "W-NEGATIVE-STEM"
    assert_not_includes lint("Nella frase «Io rimasi fuori, perciò non vidi niente», quale parola può prendere il posto di «perciò»?", role: :stem).map(&:code), "W-NEGATIVE-STEM"
    assert_not_includes lint("Nella frase “Io non vidi niente”, quale parola va al posto di “non”?", role: :stem).map(&:code), "W-NEGATIVE-STEM"
    assert_includes lint("Quale frase non è corretta? «Sì»", role: :stem).map(&:code), "W-NEGATIVE-STEM"
    assert_not_includes lint("Quale frase non è corretta?", role: :text).map(&:code), "W-NEGATIVE-STEM"
    assert_includes lint("Il prezzo è 3.5 euro.").map(&:code), "W-DECIMAL-POINT"
    assert_empty lint("Il prezzo è 1.000 euro.").select { |f| f.code == "W-DECIMAL-POINT" }
    assert_includes lint("Ho verificato il calcolo.").map(&:code), "W-SELF-CERT"
    hard = ([ "Paradigmaticamente incontrovertibilmente costituzionalizzabile" ] * 9).join(" ") + "."
    assert_includes lint(hard).map(&:code), "W-GULPEASE"
    assert_includes lint(hard, role: :passage).map(&:code), "W-PASSAGE-READABILITY"
  end

  test "lint_document reads only keys that end in _it, and skips quotes" do
    findings = Validation::Findings.new
    doc = { "prompt" => { "stem_it" => "Leggi con ATTENZIONE.", "quote" => { "ref" => "x", "text" => "TESTO ORIGINALE IN MAIUSCOLO" } },
            "options" => [ { "id" => "o1", "text" => "TESTO DELLA LINGUA" } ],
            "error_catalogue" => [ { "message_it" => "Uno. Due. Tre." } ] }
    Validation::Readability.lint_document(doc, "", findings)
    assert_equal [ [ "E-MESSAGE", "/error_catalogue/0/message_it" ], [ "E-READ", "/prompt/stem_it" ] ].sort, findings.map { |f| [ f.code, f.field ] }.sort
  end

  test "lint_document skips the keys it is told to (target-language text, D-112)" do
    doc = { "passage_it" => "The BBC says that " + ([ "very" ] * 30).join(" ") + ".", "stem_it" => "Leggi il testo." }
    findings = Validation::Findings.new
    Validation::Readability.lint_document(doc, "", findings, skip: %w[passage_it])
    assert_empty findings.to_a
    linted = Validation::Findings.new
    Validation::Readability.lint_document(doc, "", linted)
    assert_includes linted.map(&:code), "E-READ"
  end
end
