require "test_helper"

# D-398: an English typed answer is the same answer with its contractions expanded or not («that's why», «that is why»), through the vetted table
# english/contractions. A possessive is never a verb; Italian, Spanish and every other subject are never expanded.
class GradingContractionsTest < ActiveSupport::TestCase
  Contractions = Grading::Closed::Contractions

  setup { Contractions.reset! }
  teardown { Contractions.reset! }

  def spec(answer, subject: "english", **opts)
    Grading::Spec.from_hash({ "component" => "normalized_text", "subject" => subject, "skill" => "#{subject}.x", "answer" => answer }.merge(opts.stringify_keys))
  end

  def verdict(answer, typed, **opts) = Grading::Closed.grade(spec(answer, **opts), typed).verdict

  def lesson_check(answer, **opts) = { "component" => "normalized_text", "prompt_it" => "Completa.", "answer" => answer }.merge(opts.stringify_keys)

  test "the vetted table is written, and the grader reads it" do
    assert Lessons::VettedData.written?("english/contractions")
    assert Contractions.ready?
  end

  PAIRS = {
    "that's / that is" => [ "that's why", "that is why" ],
    "I'm / I am" => [ "I'm happy", "I am happy" ],
    "don't / do not" => [ "don't", "do not" ],
    "can't / cannot" => [ "can't", "cannot" ],
    "can't / can not" => [ "can't", "can not" ],
    "cannot / can not" => [ "cannot", "can not" ],
    "won't / will not" => [ "won't go", "will not go" ],
    "it's / it is" => [ "it's raining", "it is raining" ],
    "doesn't / does not" => [ "She doesn't know", "She does not know" ],
    "they're / they are" => [ "they're late", "they are late" ],
    "I've / I have" => [ "I've got it", "I have got it" ],
    "I'll / I will" => [ "I'll stay", "I will stay" ],
    "let's / let us" => [ "let's go", "let us go" ],
    "I'd / I would" => [ "I'd like tea", "I would like tea" ]
  }.freeze

  PAIRS.each do |name, (short, long)|
    test "#{name}: the short form and the long form are the same answer, both ways, with a curly apostrophe and any case" do
      assert_equal "correct", verdict(short, long)
      assert_equal "correct", verdict(long, short)
      assert_equal "correct", verdict(long, short.tr("'", "’").upcase)
      assert_equal "correct", verdict(short, short)
    end
  end

  test "a form with two readings is read both ways: it's is it is or it has, I'd is I would or I had" do
    assert_equal [ "it is", "it has" ], Contractions.readings("it's")
    assert_equal "correct", verdict("it is", "it's")
    assert_equal "correct", verdict("it has", "it's")
    assert_equal "correct", verdict("it's", "it has")
    assert_equal "correct", verdict("I would go", "I'd go")
    assert_equal "correct", verdict("I had gone", "I'd gone")
  end

  test "the reading that the key does not have is wrong: it has is not it is, it was is neither" do
    assert_equal "wrong", verdict("it is", "it has")
    assert_equal "wrong", verdict("it's", "it was")
    assert_equal "wrong", verdict("don't", "does not")
    assert_equal "wrong", verdict("I will stay", "I would stay")
    assert_equal "wrong", verdict("can't", "can")
  end

  test "a possessive is kept: 's after a noun is never turned into is or has, and 'd after a noun is never turned into would or had" do
    assert_equal [ "anna's book" ], Contractions.readings("Anna's book")
    assert_equal [ "the dog's bone" ], Contractions.readings("the dog's bone")
    assert_equal [ "anita'd gone" ], Contractions.readings("Anita'd gone")
    assert_equal "wrong", verdict("Anna's book", "Anna is book")
    assert_equal "wrong", verdict("Anna's book", "Anna has book")
    assert_equal "correct", verdict("Anna is here", "Anna's here"), "round 8: the typed 's after a noun is read as the verb the key needs"
    assert_equal "wrong", verdict("Anna was here", "Anna's here")
    assert_equal "correct", verdict("Anna's book", "Anna’s book")
  end

  # Round 4 of the bilingual tooling: an author keeps `accept` short (10 entries), so the 's, 'm and 're forms of a key are never listed; the two-way reading is what accepts them.
  test "'s, 'm and 're: the contracted form of a key's full form is right without accept, and so is the full form of a contracted key" do
    {
      "She is a doctor." => "She's a doctor.", "I am ready." => "I'm ready.", "You are late." => "You're late.",
      "He is at home, and we are here." => "He's at home, and we're here.", "It is cold, and they are in the garden." => "It's cold, and they're in the garden."
    }.each do |long, short|
      assert_equal "correct", verdict(long, short), "#{short} for the key #{long}"
      assert_equal "correct", verdict(short, long), "#{long} for the key #{short}"
      assert_equal "correct", verdict(long, short.tr("'", "’")), "a curly apostrophe"
    end
    framed = spec("She is", display: { "stem_it" => "___ a doctor." })
    assert_equal "correct", Grading::Closed.grade(framed, "She's a doctor.").verdict
    assert_equal "correct", Grading::Closed.grade(spec("I'm", display: { "stem_it" => "___ ready." }), "I am ready.").verdict
  end

  test "'s, 'm and 're: a reading the key does not have is wrong, and a declared error value stays an error when it is neither reading" do
    assert_equal "wrong", verdict("She is a doctor.", "She was a doctor.")
    assert_equal "wrong", verdict("You are late.", "You were late.")
    assert_equal "wrong", verdict("I'm ready.", "I was ready.")
    hit = Grading::Closed.grade(spec("She is a doctor.", errors: [ { "code" => "wrong_tense", "value" => "She was a doctor." } ]), "She was a doctor.")
    assert_equal [ "typical_error", [ "wrong_tense" ] ], [ hit.verdict, hit.error_codes ]
    both = Grading::Closed.grade(spec("She is a doctor.", errors: [ { "code" => "wrong_tense", "value" => "She was a doctor." } ]), "She's a doctor.")
    assert_equal "correct", both.verdict, "the contracted key is the key, not the error"
  end

  # Round 5 of the bilingual tooling: the filler of a gap after a subject starts with the contraction («'s scared»); an author never lists it in accept.
  test "a gap fragment that starts with 's, 'm, 're, 'd is read as its full form against the key, and the key's fragment against the full form" do
    gap = ->(answer, **opts) { spec(answer, display: { "stem_it" => "My friend ___ of deep water." }, **opts) }
    grade = ->(s, typed) { Grading::Closed.grade(s, typed).verdict }
    assert_equal "correct", grade.(gap.("is scared"), "'s scared")
    assert_equal "correct", grade.(gap.("is scared"), "’s scared"), "a curly apostrophe"
    assert_equal "correct", grade.(gap.("is scared"), "is scared")
    assert_equal "correct", grade.(gap.("'s scared"), "is scared"), "the reverse: key «'s scared», answer «is scared»"
    assert_equal "correct", grade.(gap.("'s scared"), "'s scared")
    assert_equal "correct", grade.(gap.("am not hungry"), "'m not hungry")
    assert_equal "correct", grade.(gap.("'m not hungry"), "am not hungry")
    assert_equal "correct", grade.(gap.("are late"), "'re late")
    assert_equal "correct", grade.(gap.("would rather go"), "'d rather go")
    assert_equal "wrong", grade.(gap.("is scared"), "'s afraid")
    assert_equal "wrong", grade.(gap.("is scared"), "'m scared")
    assert_equal "wrong", grade.(gap.("is scared"), "was scared")
    assert_equal "wrong", grade.(gap.("is scared"), "'d scared"), "'d is would or had, never is"
    assert_equal "wrong", grade.(gap.("'s scared", contractions: nil, subject: "spanish"), "is scared"), "another subject is never expanded"
  end

  test "a lesson check of an English lesson reads the fragment of its gap the same way" do
    check = lesson_check("is scared", "prompt_it" => "My friend ___ of deep water.")
    assert Lessons::Checks.grade(check, "'s scared", subject: "english").right?
    assert Lessons::Checks.grade(check, "is scared", subject: "english").right?
    assert Lessons::Checks.grade(lesson_check("'m not hungry", "prompt_it" => "I ___ today."), "am not hungry", subject: "english").right?
    assert Lessons::Checks.grade(check, "'s scared", subject: "spanish").wrong?, "another subject never expands"
    assert Lessons::Checks.grade(check, "'s afraid", subject: "english").wrong?
  end

  test "'s as a fragment is has only when the key says has: «'s gone» is not «is gone» for a key «has gone», and a noun's 's is still a possessive" do
    assert_equal [ "is scared", "has scared" ], Contractions.readings("'s scared")
    assert_equal [ "anna's scared" ], Contractions.readings("Anna's scared"), "only the first word is a fragment"
    assert_equal "correct", verdict("has gone", "'s gone")
    assert_equal "correct", verdict("is gone", "'s gone")
    assert_equal "wrong", verdict("was gone", "'s gone")
    assert_equal "wrong", verdict("Anna is gone", "Anna 's gone")
  end

  # Round 8: «'s» is «is» and «has»; the key decides, and the other reading being a declared error value does not make the answer an error.
  test "'s is the reading the key needs: a declared error value that is the OTHER reading does not turn it into an error" do
    gap = ->(answer, error, **opts) { spec(answer, display: { "stem_it" => "She ___ a cold." }, errors: [ { "code" => "wrong_aux", "value" => error } ], **opts) }
    grade = ->(s, typed) { Grading::Closed.grade(s, typed) }
    has = gap.("has got", "is got")
    assert_equal "correct", grade.(has, "'s got").verdict, "the fragment, key has got, error is got"
    assert_equal "correct", grade.(has, "She's got a cold.").verdict, "the sentence written in full"
    assert_equal "correct", grade.(has, "She has got a cold.").verdict
    assert_equal [ "typical_error", [ "wrong_aux" ] ], grade.(has, "is got").then { |r| [ r.verdict, r.error_codes ] }, "the error written out stays an error"
    assert_equal [ "typical_error", [ "wrong_aux" ] ], grade.(has, "She is got a cold.").then { |r| [ r.verdict, r.error_codes ] }
    is = spec("is tired", display: { "stem_it" => "She ___ today." }, errors: [ { "code" => "wrong_aux", "value" => "has tired" } ])
    assert_equal "correct", grade.(is, "'s tired").verdict, "key is tired, error has tired"
    assert_equal "correct", grade.(is, "She's tired today").verdict
    assert_equal "typical_error", grade.(is, "has tired").verdict
    assert_equal "wrong", grade.(spec("was tired", display: { "stem_it" => "She ___ today." }), "'s tired").verdict, "neither reading is the key"
  end

  test "'s after a noun, typed in full, is read as the verb the key needs («My sister's got a cold»); the key and the accept entries never are" do
    gap = spec("has got", display: { "stem_it" => "My sister ___ a cold." }, errors: [ { "code" => "wrong_aux", "value" => "is got" } ])
    assert_equal "correct", Grading::Closed.grade(gap, "My sister's got a cold.").verdict
    assert_equal "correct", Grading::Closed.grade(gap, "my sister’s got a cold").verdict
    assert_equal "typical_error", Grading::Closed.grade(gap, "My sister is got a cold.").verdict
    assert_not_equal "correct", Grading::Closed.grade(spec("had", display: { "stem_it" => "My sister ___ a cold." }), "My sister's got a cold.").verdict, "neither reading is the key"
    assert_equal "correct", verdict("My sister has got a cold", "My sister's got a cold")
    assert_equal "wrong", verdict("Anna's book", "Anna is book"), "a possessive key is never read as a verb"
  end

  test "a declared error value that is the same reading as the key's reading is still an error, and a reading that is an error never makes an answer right" do
    errors = [ { "code" => "wrong_aux", "value" => "is scared" } ]
    accept = spec("has scared", errors: errors, accept: [ "'s scared" ])
    assert_equal "typical_error", Grading::Closed.grade(accept, "is scared").verdict, "the accept entry 's scared does not accept «is scared»"
    assert_equal "correct", Grading::Closed.grade(accept, "'s scared").verdict
    assert_equal "correct", Grading::Closed.grade(accept, "has scared").verdict
    other = spec("was scared", display: { "stem_it" => "My friend ___ of deep water." }, errors: [ { "code" => "wrong_tense", "value" => "has scared" } ])
    hit = Grading::Closed.grade(other, "'s scared")
    assert_equal [ "typical_error", [ "wrong_tense" ] ], [ hit.verdict, hit.error_codes ], "the key has neither reading: the error reading is an error"
  end

  test "its and whose have no apostrophe: they are never read as a verb" do
    assert_equal [ "its cover" ], Contractions.readings("its cover")
    assert_equal "wrong", verdict("its cover", "it is cover")
  end

  test "the rule works through accept, the declared errors and the whole sentence of the blank" do
    assert_equal "correct", verdict("do not go", "don't go", accept: [ "did not go" ])
    assert_equal "correct", verdict("go", "didn't go", accept: [ "did not go" ])
    hit = Grading::Closed.grade(spec("It works", errors: [ { "code" => "wrong_aux", "value" => "It doesn't work" } ]), "It does not work")
    assert_equal [ "typical_error", [ "wrong_aux" ] ], [ hit.verdict, hit.error_codes ]
    framed = spec("isn't", display: { "stem_it" => "She ___ here." })
    assert_equal "correct", Grading::Closed.grade(framed, "She is not here.").verdict
    assert_equal "correct", Grading::Closed.grade(spec("is not", display: { "stem_it" => "She ___ here." }), "She isn't here").verdict
  end

  test "the same rule grades a lesson check of an English lesson, and only for English" do
    check = lesson_check("that's why")
    assert Lessons::Checks.grade(check, "that is why", subject: "english").right?
    assert Lessons::Checks.grade(lesson_check("that is why"), "That's why!", subject: "english").right?
    assert Lessons::Checks.grade(lesson_check("won't"), "will not", subject: "english").right?
    assert Lessons::Checks.grade(check, "that has why", subject: "english").right?, "'s after that is is or has: either reading fits the key's"
    assert Lessons::Checks.grade(lesson_check("Anna's book"), "Anna is book", subject: "english").wrong?
    assert Lessons::Checks.grade(check, "that is why", subject: "italian").wrong?
    assert Lessons::Checks.grade(check, "that is why", subject: "spanish").wrong?
    assert Lessons::Checks.grade(check, "that is why").wrong?
    assert Lessons::Checks.grade(check.merge("contractions" => "en"), "that is why", subject: "history").right?, "the option written in the check still works"
  end

  test "the validators read an accept and an error value as the grader does" do
    on = Contractions.option("english", nil)
    assert Grading::Closed::Text.same_answer?("do not go", "don't go", contractions: on)
    assert_not Grading::Closed::Text.same_answer?("do not go", "don't go", contractions: Contractions.option("italian", nil))
    assert_not Grading::Closed::Text.same_answer?("Anna's book", "Anna is book", contractions: on)
    assert_not Grading::Closed::Text.same_answer?("'s got", "is got", contractions: on), "round 8: the accept entry 's got does not swallow the error is got"
    assert_not Grading::Closed::Text.same_answer?("she's tired", "she has tired", contractions: on)
    assert Grading::Closed::Text.same_answer?("it is cold", "it's cold", contractions: on), "a true clash: the error value would be graded right"
    assert Grading::Closed::Text.same_answer?("'s got", "'s got", contractions: on)
  end

  test "Italian, Spanish and the other subjects are never expanded" do
    assert_equal "wrong", verdict("c'è", "ci è", subject: "italian")
    assert_equal "wrong", verdict("dov'è", "dove è", subject: "italian")
    assert_equal "correct", verdict("dov'è", "dov’è", subject: "italian")
    assert_equal "wrong", verdict("don't", "do not", subject: "spanish")
    assert_equal "wrong", verdict("it's", "it is", subject: "history")
    assert_equal "wrong", verdict("it is", "it's", subject: "geo")
    assert_nil Grading::Spec.from_hash({ "component" => "normalized_text", "subject" => "italian", "answer" => "x" }).contractions
    assert_nil Grading::Spec.from_hash({ "component" => "normalized_text", "skill" => "spanish.verbs", "answer" => "x" }).contractions
    assert_equal "en", Grading::Spec.from_hash({ "component" => "normalized_text", "skill" => "english.verbs", "answer" => "x" }).contractions
  end

  test "a case-sensitive item stays case-sensitive after the expansion: Doesn't is Does not, I'd is I would" do
    assert_equal [ "Does not have" ], Contractions.readings("Doesn't have", case_sensitive: true)
    assert_equal [ "does not have" ], Contractions.readings("Doesn't have")
    assert_equal [ "I would", "I had" ], Contractions.readings("I'd", case_sensitive: true)
    assert_equal [ "It is", "It has" ], Contractions.readings("It's", case_sensitive: true)
    assert_equal "correct", verdict("Does not have", "Doesn't have", case_sensitive: true)
    assert_equal "correct", verdict("doesn't have", "does not have", case_sensitive: true)
    assert_equal "correct", verdict("I would go", "I'd go", case_sensitive: true)
    assert_equal "wrong", verdict("doesn't have", "Doesn't have", case_sensitive: true)
    assert_equal "wrong", verdict("doesn't have", "Does not have", case_sensitive: true)
    assert_equal "wrong", verdict("it's here", "It is here", case_sensitive: true)
    assert_equal "correct", verdict("doesn't have", "Doesn't have"), "case is folded when the item does not ask for it"
    assert_not Grading::Closed::Text.same_answer?("doesn't have", "Doesn't have", case_sensitive: true, contractions: "en")
    assert Grading::Closed::Text.same_answer?("doesn't have", "Doesn't have", contractions: "en")
  end

  test "another component of an English item is not touched" do
    choice = Grading::Spec.from_hash({ "component" => "choice", "subject" => "english", "answer" => "o1" })
    assert_nil choice.contractions
  end

  test "the option helper: the author's value first, else en for english, else nothing" do
    assert_equal "en", Contractions.option("english")
    assert_equal "en", Contractions.option("history", "en")
    assert_nil Contractions.option("italian")
    assert_nil Contractions.option(nil)
    assert_nil Contractions.option("spanish", "")
  end
end
