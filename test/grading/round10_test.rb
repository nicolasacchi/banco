require "test_helper"

# Tooling round 10, slice A (D-408): the grader's contractions and subject pronouns, the near miss on an inflection ending. The end-to-end cases are the `r10-*` vectors of
# test/fixtures/grading/vectors.json and the `inflection-*` ones of near_text.json; this file holds what a vector cannot say (the readings, the practice outcome).
class GradingRound10Test < ActiveSupport::TestCase
  Contractions = Grading::Closed::Contractions
  Pronouns = Grading::Closed::SubjectPronouns

  def spec(answer, subject: "english", **opts)
    Grading::Spec.from_hash({ "component" => "normalized_text", "subject" => subject, "skill" => "#{subject}.x", "answer" => answer }.merge(opts.stringify_keys))
  end

  def verdict(s, typed) = Grading::Closed.grade(s, typed).verdict

  test "n't expands only after the auxiliary of standard English: amn't and ain't stay as typed" do
    assert_equal [ "she is not here" ], Contractions.readings("she isn't here")
    assert_equal [ "i do not know" ], Contractions.readings("I don't know")
    assert_equal [ "amn't" ], Contractions.readings("amn't")
    assert_equal [ "i amn't going" ], Contractions.readings("I amn't going")
    assert_equal [ "ain't" ], Contractions.readings("ain't")
    assert_equal [ "will not" ], Contractions.readings("won't")
    assert_equal [ "cannot", "can not" ], Contractions.readings("can't")
    %w[isn't aren't wasn't weren't doesn't don't didn't hasn't haven't hadn't couldn't wouldn't shouldn't mustn't needn't mightn't daren't].each do |word|
      assert_equal [ "#{word.delete_suffix("n't")} not" ], Contractions.readings(word), word
    end
    assert_equal "wrong", verdict(spec("I am not going to buy it"), "I amn't going to buy it")
  end

  test "a text that starts with a suffix is a fragment only when the gap has a word before it" do
    assert_equal [ "is scared", "has scared" ], Contractions.readings("'s scared")
    assert_equal [ "is coming" ], Contractions.readings("'s coming")
    assert_equal [ "'re late" ], Contractions.readings("'re late", fragment: false)
    assert_equal [ "'s coming" ], Contractions.readings("'s coming", fragment: false)
    after_subject = spec("is coming", display: { "stem_it" => "Jack ___ to the party." })
    opening = spec("is coming", display: { "stem_it" => "___ Jack coming to the party?" })
    assert_equal "correct", verdict(after_subject, "'s coming")
    assert_equal "wrong", verdict(opening, "'s coming")
    assert_equal "wrong", verdict(spec("Is", display: { "stem_it" => "___ Jake going to play?" }), "'s")
    assert_equal "wrong", verdict(spec("are", display: { "stem_it" => "___ you ready?" }), "'re")
    assert_equal "correct", verdict(spec("Is", display: { "stem_it" => "___ Jake going to play?" }), "Is")
  end

  test "'s is has only before a past participle or got, in the typed text, the key and the frame's words after the gap" do
    assert_equal [ "emma is a bad cold" ], Contractions.readings("Emma's a bad cold", typed: true) - [ "emma's a bad cold" ]
    assert_equal [ "she is got", "she has got" ], Contractions.readings("she's got")
    assert_equal [ "she is gone", "she has gone" ], Contractions.readings("she's gone")
    assert_equal [ "she is just finished", "she has just finished" ], Contractions.readings("she's just finished")
    assert_equal [ "it is a cold" ], Contractions.readings("it's a cold")
    assert_equal [ "it is", "it has" ], Contractions.readings("it's"), "nothing after it: the sentence may go on after the gap"
    assert_equal [ "it is" ], Contractions.readings("it's", after: %w[a bad cold])
    assert_equal [ "it is", "it has" ], Contractions.readings("it's", after: %w[gone home])
    full = spec("has", display: { "stem_it" => "Emma ___ a bad cold." })
    assert_equal "wrong", verdict(full, "'s"), "the filler «'s» before «a bad cold» is is"
    assert_equal "correct", verdict(spec("has", display: { "stem_it" => "Emma ___ gone home." }), "'s")
    assert_equal "correct", verdict(spec("has got", display: { "stem_it" => "Emma ___ a bad cold." }), "'s got")
  end

  test "a wrong inflection ending is wrong with its practice outcome, never «forse un errore di battitura»" do
    instance = ->(s, typed) { Practice::Instances.near_kind(s, "wrong", typed) }
    assert_nil instance.(spec("wants"), "want")
    assert_nil instance.(spec("belongs"), "belong")
    assert_nil instance.(spec("me encanta", subject: "spanish"), "me encantan")
    assert_equal :typo, instance.(spec("neighborhood"), "neiborhood")
    assert_equal :typo, instance.(spec("belongs"), "belogns")
    # the grader's own near miss (spelling_policy near) says the same
    near = ->(answer, typed, **o) { verdict(spec(answer, spelling_policy: "near", **o), typed) }
    assert_equal "wrong", near.("belongs", "belong")
    assert_equal "near_miss", near.("belongs", "belogns")
    assert_equal "wrong", near.("me encanta", "me encantan", subject: "spanish")
    assert_equal "near_miss", near.("Cartagine", "Cartagina", subject: "history"), "another subject has no list of endings"
  end

  test "the subject pronoun of a Spanish verb gap: the person of the key is read from its first words" do
    {
      "he ido" => %i[yo], "has ido" => %i[tu], "ha ido" => %i[el], "hemos escrito" => %i[nos], "habéis ido" => %i[vos], "han ido" => %i[ellos],
      "me he duchado" => %i[yo], "te has duchado" => %i[tu], "se ha duchado" => %i[el], "se han duchado" => %i[ellos], "nos hemos duchado" => %i[nos],
      "no he ido" => %i[yo], "lo he visto" => %i[yo], "hablo" => %i[yo], "hablas" => %i[tu], "habla" => %i[el], "hablamos" => %i[nos], "habláis" => %i[vos], "hablan" => %i[ellos],
      "voy" => %i[yo], "fue" => %i[el], "somos" => %i[nos], "fuimos" => %i[nos], "comió" => %i[el], "viví" => %i[yo]
    }.each { |key, persons| assert_equal persons, Pronouns.persons(key), key }
    assert_empty Pronouns.persons("")
    assert Pronouns.agrees?("yo", "he ido")
    assert Pronouns.agrees?("ella", "se ha duchado")
    assert_not Pronouns.agrees?("ellos", "se ha duchado")
    assert_not Pronouns.agrees?("tú", "he ido")
    assert_not Pronouns.agrees?("el", "ha ido"), "«el» is the article, not a pronoun"
  end

  test "the pronoun is accepted only in Spanish, only as the first word, never after a subject, and wrong in the wrong person" do
    key = spec("he ido", subject: "spanish")
    assert_equal "correct", verdict(key, "yo he ido")
    assert_equal "correct", verdict(key, "Yo he ido.")
    assert_equal "wrong", verdict(key, "tú he ido")
    assert_equal "wrong", verdict(key, "ido yo he")
    assert_equal "wrong", verdict(spec("he ido", subject: "italian"), "yo he ido")
    assert_equal "correct", verdict(spec("han ido", subject: "spanish", accept: [ "se han ido" ]), "ellas han ido")
    nobody = spec("hemos escrito", subject: "spanish", display: { "stem_it" => "Nosotros ___ una carta." })
    assert_equal "wrong", verdict(nobody, "nosotros hemos escrito"), "the frame has its subject before the gap"
    today = spec("he ido", subject: "spanish", display: { "stem_it" => "Hoy ___ al cine." })
    assert_equal "correct", verdict(today, "yo he ido"), "a time word before the gap is no subject"
    sentence = spec("he ido", subject: "spanish", display: { "stem_it" => "___ al cine." })
    assert_equal "correct", verdict(sentence, "Yo he ido al cine.")
  end
end
