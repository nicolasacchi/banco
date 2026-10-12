# frozen_string_literal: true

module Lessons
  # Verbs: english/verbs lookups and the contraction table.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T3): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/verbs.js and both run test/fixtures/lesson2/verbs.json (like Lessons::Num and lesson/num.js).
  module Verbs
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "lookup" => "lookup(base)",
      "family_mark" => "family_mark(verb)",
      "expand_contractions" => "expand_contractions(text)"
    }.freeze

    module_function

    # A verb of english/verbs: base, past and participle variants.
    def lookup(base)
      raise NotBuilt, "Lessons::Verbs.lookup is not built yet (T3, w2-1)"
    end

    # The mark of a verb in its family: same_forms, vowel, participle_from_base, participle_from_past.
    def family_mark(verb)
      raise NotBuilt, "Lessons::Verbs.family_mark is not built yet (T3, w2-1)"
    end

    # A text with its contractions expanded (english/contractions), for both sides of a typed answer.
    def expand_contractions(text)
      raise NotBuilt, "Lessons::Verbs.expand_contractions is not built yet (T3, w2-1)"
    end
  end
end
