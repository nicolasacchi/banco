# frozen_string_literal: true

module Lessons
  # Words: The split notation shared by paradigm and word_parts (| stem and ending, [..] changed letters, + attached piece), Spanish syllables and stress.
  # Contract stub of W2-0 (WAVE2 1.10, batch w2-1, track T3): the signatures below are frozen; the bodies are the track's. The JS twin is
  # app/javascript/lesson/lib/words.js and both run test/fixtures/lesson2/spanish_words.json (like Lessons::Num and lesson/num.js).
  module Words
    NotBuilt = Class.new(NotImplementedError)
    # name => signature (Ruby)
    SIGNATURES = {
      "split" => "split(notation)",
      "syllables_es" => "syllables_es(word)",
      "stress_es" => "stress_es(word)",
      "tilde_ok" => "tilde_ok?(word)",
      "present" => "present(verb, pattern)"
    }.freeze

    module_function

    # A form in split notation as pieces with their marks; the marks removed give the word.
    def split(notation)
      raise NotBuilt, "Lessons::Words.split is not built yet (T3, w2-1)"
    end

    # The syllables of a Spanish word.
    def syllables_es(word)
      raise NotBuilt, "Lessons::Words.syllables_es is not built yet (T3, w2-1)"
    end

    # The 1-based index of the stressed syllable.
    def stress_es(word)
      raise NotBuilt, "Lessons::Words.stress_es is not built yet (T3, w2-1)"
    end

    # Whether the written tilde (or its absence) follows the stress rule.
    def tilde_ok?(word)
      raise NotBuilt, "Lessons::Words.tilde_ok? is not built yet (T3, w2-1)"
    end

    # W2-2: the six present forms by pattern; spanish/verbs is the truth and the engine only cross-checks regular and stem-changing rows.
    def present(verb, pattern)
      raise NotBuilt, "Lessons::Words.present is not built yet (T3, w2-1)"
    end
  end
end
