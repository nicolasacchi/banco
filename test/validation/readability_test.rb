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

  test "abbreviations do not split sentences" do
    assert_empty rules("Usa i numeri primi, ad es. 2 e 3, ecc. e poi scegli.")
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

  test "a message of more than two sentences is E-MESSAGE" do
    assert_includes lint("Primo passo. Secondo passo. Terzo passo.", role: :message).map(&:code), "E-MESSAGE"
    assert_not_includes lint("Primo passo. Secondo passo.", role: :message).map(&:code), "E-MESSAGE"
  end

  test "warnings: absolute word, negative stem, decimal point, self-certification, Gulpease" do
    assert_includes lint("Il risultato è sempre positivo.").map(&:code), "W-ABSOLUTE"
    assert_not_includes lint("Il minore fa da solo gli atti di ordinaria amministrazione.").map(&:code), "W-ABSOLUTE"
    assert_includes lint("Solo il tutore firma. Lei fa da sola.").map(&:code), "W-ABSOLUTE"
    assert_includes lint("Quale frase non è corretta?", role: :stem).map(&:code), "W-NEGATIVE-STEM"
    assert_not_includes lint("Quando è vera «non ($x$ è pari e $y$ è dispari)»?", role: :stem).map(&:code), "W-NEGATIVE-STEM"
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
end
