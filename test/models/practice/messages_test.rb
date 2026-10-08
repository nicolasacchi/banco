require "test_helper"
require_relative "../../support/practice_engine_helper"

# The sentences the student reads from the engine (A9.4): every code has one, and nothing is generated.
class PracticeMessagesTest < ActiveSupport::TestCase
  include PracticeEngineHelper

  test "every form violation that the expression checker can name has a sentence" do
    source = Rails.root.join("app/javascript/grader/checker.mjs").read
    codes = source.scan(/v\.add\('([a-z_]+)'\)/).flatten.uniq
    assert_operator codes.size, :>=, 10
    assert_empty codes - Practice::Messages::FORM_IT.keys
  end

  test "the form message falls back to practice.form for an unknown violation" do
    assert_equal I18n.t("practice.form"), Practice::Messages.form([ "mystery" ])
    assert_equal I18n.t("practice.form"), Practice::Messages.form([])
    assert_equal Practice::Messages::FORM_IT["not_lowest_terms"], Practice::Messages.form([ "not_lowest_terms", "zero_term" ])
  end

  test "every outcome has a message, and a closing failure says second_wrong" do
    Practice::Outcome::OUTCOMES.each { |o| assert Practice::Messages.feedback(o).present?, o.to_s }
    %i[unrecognised form near_miss].each do |o|
      assert_equal I18n.t("practice.second_wrong"), Practice::Messages.feedback(o, closing: true)
    end
    assert_equal "Hai sbagliato un segno.", Practice::Messages.feedback(:typical_error, typical: "Hai sbagliato un segno.", closing: true)
    assert_equal I18n.t("practice.unrecognised"), Practice::Messages.feedback(:typical_error)
    assert_equal I18n.t("practice.unrecognised_no_hint"), Practice::Messages.feedback(:unrecognised, hint: false)
    refute_includes I18n.t("practice.unrecognised_no_hint"), "aiuto"
  end

  test "notes: accents and a declared form" do
    assert_equal I18n.t("practice.accents_note"), Practice::Messages.note("orthography_slip")
    assert_equal Practice::Messages::FORM_IT["not_lowest_terms"], Practice::Messages.note("wrong_form_declared", violations: [ "not_lowest_terms" ])
    assert_nil Practice::Messages.note("correct")
  end

  test "every why code of the fold has a sentence with its parameters" do
    states = [ fold([]), fold([ try_at ]), fold(demonstrating_tries), fold([], seed: seed_of("to_recover")), fold([], seed: seed_of("to_learn")),
               fold([], seed: seed_of("demonstrated")), fold([], seed: seed_of("demonstrated", implied: true)),
               fold(demonstrating_tries + [ try_at(day: 3, outcome: :unrecognised) ]),
               fold(demonstrating_tries + [ try_at(day: 30, serve: 900) ]) ]
    assert_equal %i[consolidated demonstrated in_study not_seen seed_demonstrated seed_implied seed_to_learn seed_to_recover to_review],
                 states.map { |s| s.why[:code] }.uniq.sort
    states.each { |s| assert_no_match(/translation missing|%\{/, Practice::Messages.why_it(s.why)) }
  end

  test "the sentences of the spec" do
    assert_equal "Corrette senza aiuto: 3 su 3, in 1 giorni su 2.", Practice::Messages.why_it(code: :in_study, n: 3, d: 1)
    assert_equal "Dimostrata il 13/10/2026: corrette senza aiuto in 2 giorni diversi.", Practice::Messages.why_it(code: :demonstrated, date: Date.new(2026, 10, 13), days: 2)
    assert_equal "Un errore senza aiuto il 02/11/2026: servono 2 corrette per tornare consolidata.",
                 Practice::Messages.why_it(code: :to_review, date: Date.new(2026, 11, 2), previous: "consolidated")
    assert_equal "Dimostrata nella diagnosi del 02/11/2026.", Practice::Messages.why_it(code: :seed_demonstrated, date: Date.new(2026, 11, 2))
    assert_equal %w[Non\ ancora\ vista Da\ riprendere Da\ imparare In\ studio Dimostrata Consolidata Da\ ripassare], Practice::Rules::V1::STATES.map { |s| Practice::Messages.state_it(s) }
  end

  test "the locale texts keep the reading rules: no italics, no emphasis, no emoji" do
    texts = I18n.t("practice").values + I18n.t("why").values + I18n.t("today").values.grep(String)
    texts.each do |t|
      next unless t.is_a?(String)

      assert_no_match(/[*_]{1,2}\w|\p{Extended_Pictographic}/, t)
      assert_not_equal t, t.upcase, t
    end
  end
end
