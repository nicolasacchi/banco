require "test_helper"

# D-339: the whole sentence written around a `___` blank. The cases of the production stems are also in
# test/fixtures/grading/vectors.json (frame-*); this file holds the frame itself and the rules around it.
class FrameTest < ActiveSupport::TestCase
  SCHOOL = "«La mia scuola non ha una biblioteca.» → My school ___ a library.".freeze

  def frame(stem) = Grading::Frame.from_stem(stem)

  def text(answer, given, stem: SCHOOL, **opts)
    spec = Grading::Spec.new(component: "normalized_text", subject: "english", answer: answer,
                             display: { "stem_it" => stem }, **opts)
    Grading::Closed.grade(spec, given)
  end

  test "the frame is the line with the blank, after the last arrow, without the label before the last colon" do
    f = frame(SCHOOL)
    assert_equal %w[my school], f.prefix
    assert_equal %w[a library], f.suffix

    f = frame("Frase: My parents eat meat.\n\nNegativa: My parents ___ meat.")
    assert_equal %w[my parents], f.prefix
    assert_equal %w[meat], f.suffix

    f = frame("Traduci → «Hai fame?» → Are you ___?")
    assert_equal %w[are you], f.prefix
    assert_empty f.suffix

    f = frame("Cambia il soggetto con Lucy: Lucy ___ her best.") # an instruction of any length before the colon is not the sentence
    assert_equal %w[lucy], f.prefix
    assert_equal %w[her best], f.suffix
  end

  test "a blank-first sentence has only a suffix" do
    f = frame("___ your grandparents over 80?")
    assert_empty f.prefix
    assert_equal %w[your grandparents over 80], f.suffix
  end

  test "a bracketed cue after the blank and the markup of the stem are not words of the sentence" do
    f = frame("Completa: [[en:When I ___ (get) home, I will call you.]]")
    assert_equal %w[when i], f.prefix
    assert_equal %w[home i will call you], f.suffix
  end

  test "no frame without exactly one blank or without a word besides it" do
    assert_nil frame("My school has a library.")
    assert_nil frame("My ___ ___ a library.")
    assert_nil frame("___")
    assert_nil frame("Scrivi ___ qui\nE poi ___ lì")
    assert_nil frame(nil)
  end

  test "part: the words between the prefix and the suffix as typed, else nil" do
    f = frame(SCHOOL)
    assert_equal "doesn't have", f.part("My school doesn't have a library")
    assert_equal "Doesn’t  have", f.part("  my SCHOOL Doesn’t  have a Library. ")
    assert_equal "has not got any", f.part("My school has not got any a library")
    assert_nil f.part("My school a library")           # nothing between
    assert_nil f.part("doesn't have")
    assert_nil f.part("My school doesn't have a book")
    assert_nil f.part("Our school doesn't have a library")
  end

  test "words compare without punctuation and with the accent direction ignored" do
    f = frame("Lei ___ perché?")
    assert_equal "è", f.part("Lei è perchè")
  end

  test "shared words counts the frame's own words, a word one letter off included" do
    f = frame("My cousins ___ 13.")
    assert_equal 2, f.shared_words("My cousin is thirteen years old.")
    assert_equal 1, f.shared_words("My brother is thirteen")
    assert_equal 0, f.shared_words("is")
  end

  # ---- through Grading::Closed ----------------------------------------------------------------------------------

  test "a whole sentence is graded on its part; normalized is the normalized part, not the sentence" do
    result = text("doesn't have", "My school doesn’t have a library.")
    assert_equal "correct", result.verdict
    assert_equal "full_sentence", result.observation
    assert_equal "doesn’t have", result.answer_part
    assert_equal "doesn't have", result.normalized
    assert_equal "doesn't have", result.to_attributes[:normalized]
    assert_not_includes result.to_attributes.keys, :answer_part
    assert_not_includes result.to_attributes.keys, :observation
  end

  test "the part follows the item's rules: accept, case policy, accents, declared errors" do
    assert_equal "correct", text("doesn't have", "My school does not have a library", accept: [ "does not have" ]).verdict
    assert_equal "wrong", text("doesn't have", "My school Doesn't have a library", case_sensitive: true).verdict
    assert_equal "correct", text("perché", "Lei perchè è", stem: "Lei ___ è").verdict

    declared = text("doesn't have", "My school don't have a library", errors: [ { "code" => "wrong_auxiliary", "value" => "don't have" } ])
    assert_equal "typical_error", declared.verdict
    assert_equal [ "wrong_auxiliary" ], declared.error_codes
    assert_equal "full_sentence", declared.observation
    assert_equal "don't have", declared.answer_part
  end

  test "the accent slip of the part is still found inside a whole sentence" do
    result = text("perché", "Lei perche è", stem: "Lei ___ è")
    assert_equal "typical_error", result.verdict
    assert_equal [ "it_accents" ], result.error_codes
    assert_equal "full_sentence", result.observation
  end

  test "a plain part answer is graded as before and carries no observation" do
    result = text("doesn't have", "Doesn't have.")
    assert_equal "correct", result.verdict
    assert_nil result.observation
    assert_nil result.answer_part
    assert_equal "wrong", text("doesn't have", "has not").verdict
  end

  test "the blank typed as it is is refused whichever the rest" do
    result = text("doesn't have", "My school ___ a library.")
    assert_predicate result, :invalid?
    assert_equal "blank_copied", result.invalid_code
    assert_equal "Al posto di ___ scrivi le parole che mancano.", result.message_it
    assert_equal "blank_copied", text("doesn't have", "___").invalid_code
  end

  test "a long answer that shares the frame's words without fitting it is not_in_frame" do
    result = text("There is", "In my neighborhood there is a supermarket.", stem: "___ a supermarket in my street.")
    assert_equal "not_in_frame", result.invalid_code
    assert_equal "Scrivi solo le parole che vanno al posto di ___.", result.message_it
    assert_equal "not_in_frame", text("are", "My cousin is thirteen years old.", stem: "My cousins ___ 13.").invalid_code
  end

  test "a long answer is not_in_frame only past the longest accepted answer plus one word" do
    # the key has 4 words: a 5 word answer is still graded (wrong), a 6 word answer sharing two frame words is refused
    stem = "My school ___ a library."
    assert_equal "wrong", text("has not got any", "My school has not got", stem: stem).verdict
    assert_equal "not_in_frame", text("has not got any", "My school has not got a big library there", stem: stem).invalid_code
    assert_equal "wrong", text("is", "Our house has a big garden there", stem: stem).verdict # shares only one word
  end

  test "an answer longer than the key that shares fewer than two frame words stays wrong" do
    assert_equal "wrong", text("are", "We are thirteen years old", stem: "My cousins ___ 13.").verdict
  end

  test "a stem without a blank, a binary profile and a non text component are unchanged" do
    assert_equal "wrong", text("is", "My school ___ a library.", stem: "My school has a library.").verdict
    binary = Grading::Spec.new(component: "normalized_text", subject: "computer_science", answer: "1010",
                               profile: { "name" => "binary", "width" => 4, "leading_zeros" => "optional" },
                               display: { "stem_it" => "Scrivi ___ in binario" })
    assert_equal "correct", Grading::Closed.grade(binary, "1010").verdict
  end

  test "an item whose key is a whole sentence keeps it: the typed key is right as it stands" do
    result = text("Tom is tall", "Tom is tall", stem: "Tom ___ tall")
    assert_equal "correct", result.verdict
    assert_nil result.observation
    assert_equal "tom is tall", result.normalized
  end

  test "an empty answer is still empty" do
    assert_equal "empty", text("doesn't have", "  ").invalid_code
  end

  test "a lesson check grades the whole sentence around the blank of its prompt" do
    check = { "component" => "normalized_text", "prompt_it" => "Completa: [[en:When I ___ (get) home, I will call you.]]",
              "answer" => "get", "errors" => [ { "answer" => "will get", "code" => "future_in_time_clause" } ] }

    right = Lessons::Checks.grade(check, "When I get home, I will call you.", nil, subject: "english")
    assert_equal "right", right.verdict
    assert_equal "get", right.normalized

    assert_equal "right", Lessons::Checks.grade(check, "get", nil, subject: "english").verdict
    hit = Lessons::Checks.grade(check, "When I will get home, I will call you.", nil, subject: "english")
    assert_equal "wrong", hit.verdict
    assert_equal "future_in_time_clause", hit.code

    copied = Lessons::Checks.grade(check, "When I ___ home, I will call you.", nil, subject: "english")
    assert_predicate copied, :invalid?
    assert_equal "blank_copied", copied.code
    assert_equal Grading::Result.message("blank_copied"), copied.message_it
  end

  # ---- D-352: what the student was shown, and the whole sentence compared with the key's -----------------------------

  def item(answer, display: {}, prompt_stem: nil, **opts)
    Grading::Spec.from_hash({ "component" => "normalized_text", "subject" => "english", "answer" => answer, "display" => display,
                              "prompt" => prompt_stem && { "stem_it" => prompt_stem } }.merge(opts.stringify_keys))
  end

  test "fill puts a filler in the blank; an apostrophe form joins the word before it" do
    f = frame("→ My aunt ___ a red car.")
    assert_equal "My aunt has a red car.", f.fill("has")
    assert_equal "My aunt's got a red car.", f.fill("'s got")
    assert_equal "Do you speak German?", frame("Domanda: ___ German?").fill("Do you speak")
  end

  test "the frame is read from the instance's stem, else from the item's own stem, and a line that only names the blank is no blank" do
    shown = item("has", display: { "stem_it" => "→ My aunt ___ a red car." }, prompt_stem: "Scrivi le parole che vanno al posto di ___")
    assert_equal %w[my aunt], Grading::Frame.for_spec(shown).prefix

    in_prompt = item("Do you speak", display: { "stem_it" => "«Parli tedesco?»" }, prompt_stem: "Domanda: ___ German?")
    assert_equal %w[german], Grading::Frame.for_spec(in_prompt).suffix

    two = item("has", display: { "stem_it" => "My aunt ___ a car." }, prompt_stem: "Completa: My uncle ___ a bike.")
    assert_equal %w[my aunt], Grading::Frame.for_spec(two).prefix # the instance's own stem has one blank: it is the sentence
    both_in_prompt = item("has", display: { "stem_it" => "Traduci." }, prompt_stem: "My ___ ___ a car.")
    assert_nil Grading::Frame.for_spec(both_in_prompt)
    assert_nil Grading::Frame.for_spec(item("has", display: { "stem_it" => "Scrivi le parole che vanno al posto di ___" }))
    assert_nil Grading::Frame.for_spec(item("has"))
  end

  test "the whole sentence with the key or an accepted value in the blank is right whatever the case, the punctuation and the apostrophes" do
    s = item("has got", accept: [ "'s got" ], display: { "stem_it" => "→ My aunt ___ a red car." })
    assert_equal "correct", Grading::Closed.grade(s, "my aunt, HAS got a red car!").verdict
    assert_equal "correct", Grading::Closed.grade(s, "My aunt’s got a red car.").verdict
    assert_equal "correct", Grading::Closed.grade(s, "has got").verdict
    wrong = Grading::Closed.grade(s, "My aunt have got a red car.")
    assert_equal [ "wrong", "full_sentence", "have got" ], [ wrong.verdict, wrong.observation, wrong.answer_part ]
  end

  test "with contractions en a contraction written out in the whole sentence is right (the table is the test fixture's)" do
    Grading::Closed::Contractions.table = JSON.parse(Rails.root.join("test/fixtures/lesson2/contractions_table.json").read).fetch("contractions")
    s = item("won't pass", contractions: "en", display: { "stem_it" => "Negativa: She ___ the test." })
    result = Grading::Closed.grade(s, "She will not pass the test.")
    assert_equal [ "correct", "full_sentence" ], [ result.verdict, result.observation ]
  ensure
    Grading::Closed::Contractions.reset!
  end

  test "a wrong filler in the frame keeps its error code; two blanks or none leave the answer as typed" do
    s = item("has", errors: [ { "code" => "agreement", "value" => "have" } ], display: { "stem_it" => "→ My aunt ___ a red car." })
    hit = Grading::Closed.grade(s, "My aunt have a red car.")
    assert_equal [ "typical_error", [ "agreement" ] ], [ hit.verdict, hit.error_codes ]
    two = item("has", display: { "stem_it" => "My aunt ___ a red car.\nMy uncle ___ a blue bike." })
    assert_equal "wrong", Grading::Closed.grade(two, "My aunt has a red car.").verdict
    none = item("has", display: { "stem_it" => "Completa la frase." })
    assert_equal "wrong", Grading::Closed.grade(none, "My aunt has a red car.").verdict
  end

  test "a sentence in the item's own prompt is a frame when the instance shows none" do
    s = item("Do you speak", display: { "stem_it" => "«Parli tedesco?»" }, prompt_stem: "Domanda: ___ German?")
    result = Grading::Closed.grade(s, "do you speak german")
    assert_equal [ "correct", "full_sentence" ], [ result.verdict, result.observation ]
  end

  test "the diagnosis still refuses the two new codes" do
    assert_includes Diagnosis::AnswerRecorder::STILL_REFUSED, "blank_copied"
    assert_includes Diagnosis::AnswerRecorder::STILL_REFUSED, "not_in_frame"
  end

  test "both codes are in the registry's grader codes and have a message" do
    codes = YAML.load_file(Rails.root.join("config/banco/error_codes.yml")).fetch("grader_codes")
    %w[blank_copied not_in_frame].each do |code|
      assert codes.key?(code), code
      assert I18n.exists?("grading.messages.#{code}", :it), code
    end
  end
end
