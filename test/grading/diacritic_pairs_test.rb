require "test_helper"

# D-403, round 9: a diacritic that makes ANOTHER word is not an accent slip (D-296), and a number with its currency or percent sign is one form.
class DiacriticPairsTest < ActiveSupport::TestCase
  def text(answer, given, subject: "spanish", **opts)
    Grading::Closed.grade(Grading::Spec.new(component: "normalized_text", subject: subject, answer: answer, **opts), given)
  end

  test "an accent that turns a Spanish word into another is wrong, not a slip" do
    r = text("Estudio porque tengo un examen", "Estudio porqué tengo un examen")
    assert_equal "wrong", r.verdict
    assert_empty r.error_codes
    {
      "qué" => "que", "cómo" => "como", "cuándo" => "cuando", "dónde" => "donde", "él" => "el", "tú" => "tu", "sí" => "si", "mí" => "mi",
      "sé" => "se", "dé" => "de", "más" => "mas"
    }.each do |accented, bare|
      assert_equal "wrong", text(bare, accented).verdict, "#{accented} for #{bare}"
      assert_equal "wrong", text(accented, bare).verdict, "#{bare} for #{accented}"
    end
    assert_equal "wrong", text("Dime cómo estás", "Dime como estás").verdict, "the missing mark of a word inside a sentence"
  end

  test "the grave typed for the acute is still the right word, and a right answer is right" do
    assert_equal "correct", text("porqué", "porquè").verdict
    assert_equal "correct", text("Estudio porque tengo un examen", "estudio porque tengo un examen.").verdict
  end

  test "a declared error value wins over the other-word rule" do
    errors = [ { "code" => "es_causal_porque_spelling", "value" => "porqué" } ]
    r = text("porque", "porqué", errors: errors)
    assert_equal [ "typical_error", [ "es_causal_porque_spelling" ] ], [ r.verdict, r.error_codes ]
    assert_equal({ kind: "error", value: "porqué", code: "es_causal_porque_spelling" }, r.matched)
  end

  test "every other accent slip stays a slip" do
    r = text("periódico", "periodico")
    assert_equal [ "typical_error", [ "es_accents" ] ], [ r.verdict, r.error_codes ]
    assert_equal "es_accents", text("Está en el periódico", "Está en el periodico").error_codes.first
    assert_equal "es_accents", text("está", "esta", paradigm_forms: []).error_codes.first
  end

  test "a missing mark on a listed word is wrong even when a near miss would have been allowed" do
    r = text("Estudio porque", "Estudio porqué", spelling_policy: "near")
    assert_equal "wrong", r.verdict
  end

  test "Italian e for è is a different word; a missing accent elsewhere is still a slip" do
    assert_equal "wrong", text("è", "e", subject: "italian").verdict
    assert_equal "wrong", text("Lui è qui", "Lui e qui", subject: "italian").verdict
    assert_equal "wrong", text("là", "la", subject: "italian").verdict
    assert_equal "wrong", text("la", "là", subject: "italian").verdict
    assert_equal "wrong", text("dà", "da", subject: "italian").verdict
    assert_equal "wrong", text("sì", "si", subject: "italian").verdict
    assert_equal "wrong", text("né", "ne", subject: "italian").verdict
    assert_equal "wrong", text("lì", "li", subject: "italian").verdict
    assert_equal "wrong", text("sé", "se", subject: "italian").verdict
    assert_equal [ "it_accents" ], text("perché", "perche", subject: "italian").error_codes
    assert_equal [ "it_accents" ], text("città", "citta", subject: "italian").error_codes
    assert_equal [ "it_apostrophe_accent" ], text("è", "e'", subject: "italian").error_codes, "an apostrophe typed for the accent is the usual way to write it"
  end

  test "an Italian pair does not apply to Spanish and the other way round" do
    assert_equal "es_accents", text("está", "esta", subject: "spanish").error_codes.first
    assert_equal [ "it_accents" ], text("più", "piu", subject: "italian").error_codes
    assert_equal [ "typical_error", [ "it_accents" ] ], [ text("tú", "tu", subject: "italian").verdict, text("tú", "tu", subject: "italian").error_codes ]
  end

  test "a number and its currency or percent sign are the same with or without the space, on both sides" do
    assert_equal "correct", text("8 €", "8€", subject: "math").verdict
    assert_equal "correct", text("8€", "8 €", subject: "math").verdict
    assert_equal "correct", text("20%", "20 %", subject: "math").verdict
    assert_equal "correct", text("20 %", "20%", subject: "math").verdict
    assert_equal "correct", text("12,50 $", "12,50$", subject: "math").verdict
    assert_equal "correct", text("£3", "£3", subject: "math").verdict
    assert_equal "correct", text("3 £", "3£", subject: "math").verdict
    assert_equal "correct", text("Cuesta 8 €", "cuesta 8€.", subject: "spanish").verdict
    assert_equal "8 €", Grading::Closed::Text.normalize("8€")
    assert_equal "8 €", Grading::Closed::Text.normalize("8  €")
    assert_equal "wrong", text("8 €", "9€", subject: "math").verdict
    assert_equal "wrong", text("8 €", "8", subject: "math").verdict
  end
end
