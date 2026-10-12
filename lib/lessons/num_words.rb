# frozen_string_literal: true

module Lessons
  # NumWords: An Italian amount in words, as written on a cheque, with its accepted variants and the typical wrong ones.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-2, track T8): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/num_words.js and both run test/fixtures/lesson2/amount_words.json (like Lessons::Num and lesson/num.js).
  module NumWords
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "amount" => "amount(text)",
      "variants" => "variants(text)",
      "wrong_forms" => "wrong_forms(text)"
    }.freeze

    module_function

    # The canonical words of an amount ('1240,50' is 'milleduecentoquaranta/50').
    def amount(text)
      raise NotBuilt, "Lessons::NumWords.amount is not built yet (T8, w2-2)"
    end

    # The forms a grader accepts for an amount.
    def variants(text)
      raise NotBuilt, "Lessons::NumWords.variants is not built yet (T8, w2-2)"
    end

    # The typical wrong forms, by name.
    def wrong_forms(text)
      raise NotBuilt, "Lessons::NumWords.wrong_forms is not built yet (T8, w2-2)"
    end
  end
end
