require "test_helper"

# D-386: a number written with a unit word that the item itself uses is graded on its number («2 minuti» when the item says «minuti»);
# a word the item does not use is refused with a message that names it. % and «percento» keep D-317; the item's own `unit` keeps D-107.
class NumberUnitWordsTest < ActiveSupport::TestCase
  STEM = "Il discorso dura quanti minuti? Conta i secondi e scrivi il risultato in minuti."
  FORMAT = "Scrivi il numero, senza l'unità."

  def spec(answer: 2, texts: [ STEM, FORMAT ], **opts)
    Grading::Spec.new(component: "number", answer: answer, item_texts: texts, **opts)
  end

  def grade(raw, **opts) = Grading::Closed::Numbers.grade(spec(**opts), raw)

  test "the item's own unit word is dropped: the number is graded, singular or plural, spaced, glued or after a letter" do
    [ "2 minuti", "2minuti", "2  Minuti", "2 minuto", "2 minuti.", "n = 2 minuti", "2\u00A0minuti" ].each do |raw|
      r = grade(raw)
      assert_equal "correct", r.verdict, raw
      assert_equal "2", r.normalized, raw
    end
    assert_equal "correct", grade("2,5 minuti", answer: "5/2").verdict
    assert_equal "correct", grade("x = 2 minuti").verdict
  end

  test "the word is the item's in its answer format or its solution too" do
    assert_equal "correct", grade("2 metri", texts: [ "Quanto è lungo?", "Scrivi il numero, per esempio 3 metri." ]).verdict
    assert_equal "correct", grade("2 ore", texts: [ "Quante ore dorme?" ]).verdict
    assert_equal "correct", grade("2 ora", texts: [ "Quante ore dorme?" ]).verdict
    assert_equal "correct", grade("2 euro", texts: [ "Il libro costa $2$ euro." ]).verdict
    assert_equal "correct", grade("2 anni", texts: [ "Quanti anni passano?" ]).verdict
  end

  test "a wrong number with the item's word stays wrong, and a declared error stays that error" do
    assert_equal "wrong", grade("3 minuti").verdict
    r = grade("5 minuti", errors: [ { "code" => "twice", "value" => 5 } ])
    assert_equal [ "typical_error", [ "twice" ] ], [ r.verdict, r.error_codes ]
  end

  test "a word the item does not use is refused and named" do
    [ [ "2 metri", "metri" ], [ "2metri", "metri" ], [ "2 m", "m" ], [ "n = 2 chili", "chili" ] ].each do |raw, word|
      r = grade(raw)
      assert_predicate r, :invalid?, raw
      assert_equal [ "extra_word", word ], [ r.invalid_code, r.invalid_detail ], raw
      assert_equal "Scrivi solo il numero, senza «#{word}».", r.message_it, raw
    end
    I18n.with_locale(:en) { assert_equal "Write only the number, without «metri».", grade("2 metri").message_it }
  end

  test "a word that only stands next to a number in the stem is not a unit" do
    assert_predicate grade("2 più", texts: [ "Quanto fa 3 più 4?" ]), :invalid?
    assert_equal "extra_word", grade("2 più", texts: [ "Quanto fa 3 più 4?" ]).invalid_code
    assert_predicate grade("2 minuti", texts: [ "Quanto fa $3 + 4$?" ]), :invalid?
  end

  test "a bare number, % and percento are unchanged" do
    assert_equal "correct", grade("2").verdict
    assert_equal "wrong", grade("3").verdict
    assert_equal "correct", grade("2%").verdict
    assert_equal "correct", grade("2 percento").verdict
    assert_equal "correct", grade("2 Per cento").verdict
    assert_equal "unreadable_number", grade("3,5,5").invalid_code
    assert_equal "unreadable_number", grade("%").invalid_code
    assert_equal "unreadable_number", grade("minuti").invalid_code
  end

  test "an item without texts refuses any word, as before the number words" do
    r = Grading::Closed::Numbers.grade(Grading::Spec.new(component: "number", answer: 2), "2 minuti")
    assert_equal [ "extra_word", "minuti" ], [ r.invalid_code, r.invalid_detail ]
  end

  test "the recorder's word: the item's unit word the answer carried, nil otherwise" do
    s = spec
    assert_equal "minuti", Grading::Closed::Numbers.own_unit_word(s, "2 minuti")
    assert_equal "minuti", Grading::Closed::Numbers.own_unit_word(s, "n = 2 minuti")
    assert_nil Grading::Closed::Numbers.own_unit_word(s, "2")
    assert_nil Grading::Closed::Numbers.own_unit_word(s, "2 metri")
    assert_nil Grading::Closed::Numbers.own_unit_word(s, "2%")
    assert_nil Grading::Closed::Numbers.own_unit_word(spec(unit: "minuti"), "2 minuti") # the item's declared unit is dropped by its own rule
  end

  test "the spec reads the stems, the answer format and the solution of an instance" do
    spec = Grading::Spec.from_hash("component" => "number", "answer" => 2, "prompt" => { "stem_it" => "Quanti minuti?" },
                                   "answer_format_it" => "Solo il numero.", "display" => { "stem_it" => "Dura 2 secondi." },
                                   "solution" => { "steps" => [ { "text_it" => "Conto i metri." } ], "final" => "2 minuti" })
    assert_equal [ "Quanti minuti?", "Dura 2 secondi.", "Solo il numero.", "Conto i metri.", "2 minuti" ], spec.item_texts
  end
end
