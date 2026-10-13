# frozen_string_literal: true

module Lessons
  module Diagrams
    # word_parts (WAVE2 2.6, T3): words split into pieces, with the syllables and the stressed one. `view: decode` (pieces and what each means) and
    # `view: syllables` (pieces, syllables, stress) are final in W2-1; `history` is a W2-2 draft. A word is written in split notation under
    # form_it | form_en | form_es | form_la (the key names the language; one language per figure, E-LESSON-LANG); the marks removed are the word.
    # The Spanish syllables and the stressed syllable are computed by Lessons::Words and never written (if they are, they must agree); for the other
    # languages the author gives `syllables` and `stress`. A Spanish word whose tilde breaks the rule cannot be drawn (a tilde where the stress needs
    # none, or "darselo" where the voice stays on dar). The browser twin is lesson/diagrams/words/word_parts.js; both run
    # test/fixtures/diagrams/types/word_parts.json.
    module WordParts
      extend Contract

      FORM_KEYS = %w[form_it form_en form_es form_la].freeze
      LANG_OF = { "form_it" => "it", "form_en" => "en", "form_es" => "es", "form_la" => "la" }.freeze
      # which subjects teach which target language (E-LESSON-LANG); Latin and Italian forms are allowed wherever pieces of words are taught
      TEACHES = { "en" => %w[english], "es" => %w[spanish] }.freeze
      NEUTRAL_ALT = "Parole divise in pezzi o in sillabe: tocca quello che la domanda chiede."
      STRIP_TILDE = ->(text) { text.tr("áéíóú", "aeiou") }

      class << self
        def caps = Validation::Rules.get(:lesson2, :types, :word_parts)

        # The words of config/locales/lesson_words.it.yml (key `scene`), the twin of lesson/diagrams/words/texts.js.
        def text(key) = I18n.t("lesson_words.scene.#{key}")

        def mark_word(mark) = text("mark_#{mark}")

        # ---- the analysis of one word (shared by the checks, the description and the printed strings) ----------------------------------

        def key_of(word) = FORM_KEYS.find { |k| word[k] }

        # The target-language keys (not Italian) the words use: a figure holds at most one.
        def target_keys(words) = words.filter_map { |w| key_of(w) }.uniq - [ "form_it" ]

        # {key:, lang:, pieces:, text:, groups: [String], syllables: [String]|nil, stress: Integer|nil} or {error: String, key:}
        def analyse(word)
          key = key_of(word)
          return { error: "a word needs form_it, form_en, form_es or form_la", key: nil } unless key

          lang = LANG_OF.fetch(key)
          split = begin
            Words.split(word[key])
          rescue Words::Refused => e
            return { error: e.message, key: key, lang: lang }
          end
          text = split["word"]
          groups = split["pieces"].group_by { |p| p["group"] }.sort.map { |_, ps| ps.sum("") { |p| p["text"] } }
          out = { key: key, lang: lang, pieces: split["pieces"], text: text, groups: groups, plain: split["pieces"].size == 1 && split["pieces"][0]["mark"] == "stem" }
          if lang == "es"
            begin
              out[:syllables] = Words.syllables_es(text)
              out[:stress] = es_stress(out)
            rescue Words::Refused => e
              out[:error] = e.message
            end
          elsif word["syllables"]
            out[:syllables] = word["syllables"].split("-")
            out[:stress] = word["stress"]
          end
          out
        end

        # The syllable the voice falls on: the written tilde, else the rule; a form with attached pieces keeps the voice on its first piece (dar+se+lo).
        def es_stress(info)
          return Words.stress_es(info[:text]) if info[:groups].size == 1 || info[:pieces].none? { |p| p["mark"] == "attached" }

          Words.stress_es(info[:groups].first)
        end

        # ---- checks -----------------------------------------------------------------------------------------------------------------

        def static(data, c)
          words = data["words"]
          c.diagram("/words", "a figure has #{caps['words'][0]} to #{caps['words'][1]} words", rule: "words-count") unless (caps["words"][0]..caps["words"][1]).cover?(words.size)
        end

        def state(eff, c, path)
          return if eff["view"] == "history" # a W2-2 draft: the reserved dry run checks the schema only

          words = eff["words"]
          langs = target_keys(words)
          c.add("E-LESSON-LANG", "#{path}/words", "a figure holds one language beside Italian: #{langs.join(', ')}", rule: "one-language#{path}") if langs.size > 1
          words.each_with_index { |w, i| word_checks(w, i, eff, c, "#{path}/words/#{i}") }
          arrow_checks(eff, words, c, path)
        end

        def across(data, states, c)
          langs = target_keys(states.flat_map { |s| s["words"] })
          c.add("E-LESSON-LANG", "/states", "a figure holds one language beside Italian: #{langs.join(', ')}", rule: "one-language-states") if langs.size > 1
          states.each_with_index do |s, i|
            c.diagram("/states/#{i}/words", "the states do not change the number of words (#{data['words'].size})", rule: "states-words#{i}") if s["words"].size != data["words"].size
          end
        end

        def word_checks(w, i, eff, c, at)
          view = eff["view"]
          forms = FORM_KEYS.select { |k| w[k] }
          if forms.size != 1
            c.diagram(at, "a word is written in exactly one of form_it, form_en, form_es, form_la (here #{forms.size})", rule: "form#{at}")
            return
          end
          info = analyse(w)
          key = info[:key]
          teaches = TEACHES[info[:lang]]
          c.add("E-LESSON-LANG", "#{at}/#{key}", "#{key} is not a language this subject teaches", rule: "lang#{at}") if teaches && !teaches.include?(c.subject)
          if info[:error]
            c.diagram("#{at}/#{key}", "the form cannot be read: #{info[:error]}", rule: "form-read#{at}")
            return
          end
          letters = info[:text].length
          c.diagram("#{at}/#{key}", "a word has #{letters} letters (at most #{caps['letters']})", rule: "letters#{at}") if letters > caps["letters"]
          c.diagram("#{at}/#{key}", "a word has #{info[:groups].size} pieces (at most #{caps['parts']})", rule: "parts#{at}") if info[:groups].size > caps["parts"]
          c.label("#{at}/label_it", w["label_it"])
          %w[from_it then_it now_it].each { |k| c.diagram("#{at}/#{k}", "#{k} belongs to the history view", rule: "history-only#{at}/#{k}") if w[k] }
          case view
          when "decode" then decode_checks(w, info, c, at)
          when "syllables"
            %w[parts_it meaning_it].each { |k| c.diagram("#{at}/#{k}", "#{k} belongs to the decode view", rule: "decode-only#{at}/#{k}") if w[k] }
          end
          syllable_checks(w, info, view, c, at)
          tilde_checks(info, c, at) if info[:lang] == "es"
        end

        def decode_checks(w, info, c, at)
          parts = w["parts_it"]
          if parts.nil?
            c.diagram("#{at}/parts_it", "the decode view gives what each piece means (parts_it)", rule: "parts-missing#{at}")
          elsif parts.size != info[:groups].size
            c.diagram("#{at}/parts_it", "the word has #{info[:groups].size} pieces and parts_it has #{parts.size} meanings: one for each piece", rule: "parts-count#{at}")
          else
            parts.each_with_index { |p, k| c.label("#{at}/parts_it/#{k}", p) }
          end
          if w["meaning_it"].nil?
            c.diagram("#{at}/meaning_it", "the decode view says what the whole word means (meaning_it)", rule: "meaning-missing#{at}")
          else
            n = Diagrams.label_words(w["meaning_it"])
            c.diagram("#{at}/meaning_it", "the meaning has #{n} words (at most #{caps['meaning_words']})", rule: "meaning-words#{at}") if n > caps["meaning_words"]
          end
        end

        def syllable_checks(w, info, view, c, at)
          given = w["syllables"]
          if info[:lang] == "es"
            return unless info[:syllables]

            c.diagram("#{at}/syllables", "the syllables of a Spanish word are computed, not written: #{info[:syllables].join('-')}", rule: "syl-es#{at}") if given && given != info[:syllables].join("-")
            c.diagram("#{at}/stress", "the stress of a Spanish word is computed (syllable #{info[:stress]}), not written", rule: "stress-es#{at}") if w["stress"] && w["stress"] != info[:stress]
          else
            if given.nil?
              c.diagram("#{at}/syllables", "the syllables view needs the syllables, written with hyphens", rule: "syl-missing#{at}") if view == "syllables"
              c.diagram("#{at}/stress", "stress needs the syllables", rule: "stress-alone#{at}") if w["stress"]
              return
            end
            syls = given.split("-", -1)
            if syls.any?(&:empty?) || syls.join.downcase != info[:text].downcase
              c.diagram("#{at}/syllables", "the syllables joined must give the word #{info[:text]}", rule: "syl-join#{at}")
              return
            end
            if w["stress"].nil?
              c.diagram("#{at}/stress", "the syllables view needs the stressed syllable (stress, counting from 1)", rule: "stress-missing#{at}") if view == "syllables"
            elsif w["stress"] > syls.size
              c.diagram("#{at}/stress", "the word has #{syls.size} syllables, so stress cannot be #{w['stress']}", rule: "stress-range#{at}")
            end
          end
          n = info[:syllables]&.size.to_i
          c.diagram("#{at}/syllables", "a word has #{n} syllables (at most #{caps['syllables']})", rule: "syl-count#{at}") if n > caps["syllables"]
        end

        # A Spanish word whose tilde breaks the rule cannot be drawn.
        def tilde_checks(info, c, at)
          return unless info[:syllables] && info[:stress]

          text = info[:text]
          if info[:pieces].none? { |p| p["mark"] == "attached" }
            c.diagram("#{at}/#{info[:key]}", "the tilde of #{text} breaks the rule of stress: write it only where the voice needs it", rule: "tilde#{at}") unless Words.tilde_ok?(text)
            return
          end
          natural = Words.stress_es(STRIP_TILDE.call(text))
          marked = info[:syllables].each_index.select { |k| info[:syllables][k].downcase.match?(/[áéíóú]/) }
          if info[:stress] > info[:syllables].size
            c.diagram("#{at}/#{info[:key]}", "the voice stays on #{info[:groups].first}, which is longer than the word", rule: "tilde#{at}")
          elsif info[:stress] != natural && marked.empty?
            c.diagram("#{at}/#{info[:key]}", "the voice stays on syllable #{info[:stress]} of #{info[:groups].first}, so #{STRIP_TILDE.call(text)} needs a tilde: an esdrújula never goes without it", rule: "tilde#{at}")
          elsif info[:stress] == natural && marked.any?
            c.diagram("#{at}/#{info[:key]}", "the tilde of #{text} is not needed: the voice falls there anyway", rule: "tilde#{at}")
          elsif marked.any? && marked.first + 1 != info[:stress]
            c.diagram("#{at}/#{info[:key]}", "the tilde of #{text} is not on the syllable where the voice stays (#{info[:groups].first})", rule: "tilde#{at}")
          end
        end

        def arrow_checks(eff, words, c, path)
          arrows = eff["arrows"].to_a
          seen = []
          arrows.each_with_index do |a, k|
            at = "#{path}/arrows/#{k}"
            if a["from"] >= words.size || a["to"] >= words.size
              c.diagram(at, "an arrow joins words that exist (the figure has #{words.size})", rule: "arrow-range#{at}")
            elsif a["to"] != a["from"] + 1
              c.diagram(at, "an arrow goes from a word to the next one", rule: "arrow-next#{at}")
            elsif seen.include?(a["from"])
              c.diagram(at, "two arrows leave the same word", rule: "arrow-twice#{at}")
            end
            seen << a["from"]
            c.label("#{at}/label_it", a["label_it"])
          end
        end

        # ---- what the browser is told -----------------------------------------------------------------------------------------------------

        def served(data, mode: :student)
          return StudentBody.diagram_generic(data) unless mode == :select

          words = Diagrams.effective_states(data).first&.fetch("words") || data["words"]
          neutral = words.map do |w|
            info = analyse(w)
            form = info[:key] ? { info[:key] => info[:groups].join("|") } : {}
            syllables = (info[:syllables] || []).join("-")
            form.merge(syllables.empty? ? {} : { "syllables" => syllables })
          end
          { "type" => "word_parts", "alt_it" => NEUTRAL_ALT, "view" => "syllables", "words" => neutral }
        end

        # The stored ids of a select set, in reading order: w1p2 is the second piece of the first word, w1s3 its third syllable.
        def targets(data, set)
          raise ArgumentError, "word_parts has no select set #{set.inspect}" unless %w[pieces syllables].include?(set.to_s)

          words_of(data).each_with_index.flat_map do |w, i|
            info = analyse(w)
            list = set.to_s == "pieces" ? info[:groups].to_a : info[:syllables].to_a
            letter = set.to_s == "pieces" ? "p" : "s"
            list.each_index.map { |k| "w#{i + 1}#{letter}#{k + 1}" }
          end
        end

        # What a teacher reads for a stored id: the piece or the syllable itself (E-CHECK-ANSWER-IN-ALT compares it with the figure's alt text).
        def target_names(data, set)
          words_of(data).each_with_index.flat_map do |w, i|
            info = analyse(w)
            list = set.to_s == "pieces" ? info[:groups].to_a : info[:syllables].to_a
            letter = set.to_s == "pieces" ? "p" : "s"
            list.each_with_index.map { |t, k| [ "w#{i + 1}#{letter}#{k + 1}", t ] }
          end.to_h
        end

        def words_of(data) = (Diagrams.effective_states(data).first || data)["words"]

        # ---- what a state prints ----------------------------------------------------------------------------------------------------------

        def effective(data, state)
          eff = Diagrams.effective_states(data)
          eff.empty? ? data : eff.fetch([ state, eff.size - 1 ].min)
        end

        def count_it(n, one, many) = n == 1 ? "una #{one}" : "#{n} #{many}"

        def describe_word(w, eff, number, several)
          info = analyse(w)
          return "" if info[:error] || info[:key].nil?

          prefix = several ? "Parola #{number}: " : ""
          out = []
          if eff["view"] == "decode"
            pieces = info[:groups].each_with_index.map { |t, k| w["parts_it"] && w["parts_it"][k] ? "#{t} vuol dire #{w['parts_it'][k]}" : t }
            out << "#{prefix}La parola #{info[:text]} è fatta di #{count_it(info[:groups].size, 'pezzo', 'pezzi')}: #{pieces.join('; ')}."
            out << "#{text('together')}: #{w['meaning_it']}." if w["meaning_it"]
          else
            out << "#{prefix}La parola #{info[:text]} ha #{count_it(info[:syllables]&.size.to_i, 'sillaba', 'sillabe')}#{info[:syllables] ? ": #{info[:syllables].join(', ')}" : ''}."
            if info[:stress] && info[:syllables]
              out << (info[:syllables].size == 1 ? "La voce batte su quella." : "La voce batte sulla sillaba numero #{info[:stress]}: #{info[:syllables][info[:stress] - 1]}.")
            end
            unless info[:plain]
              names = info[:pieces].map { |p| "#{p['text']} (#{mark_word(p['mark'])})" }
              out << "Pezzi: #{names.join(', ')}."
            end
          end
          out << "#{w['label_it']}." if w["label_it"]
          out.join(" ")
        end

        def describe(data, state: 0)
          eff = effective(data, state)
          words = eff["words"]
          parts = words.each_with_index.map { |w, i| describe_word(w, eff, i + 1, words.size > 1) }
          eff["arrows"].to_a.each do |a|
            parts << "Da parola #{a['from'] + 1} a parola #{a['to'] + 1}#{a['label_it'] ? ": #{a['label_it']}" : ''}."
          end
          parts.reject(&:empty?).join(" ")
        end

        def printed(data, state)
          eff = effective(data, state)
          out = []
          eff["words"].each do |w|
            info = analyse(w)
            next if info[:error] || info[:key].nil?

            out << info[:text]
            out.concat(info[:groups])
            out.concat(w["parts_it"].to_a)
            out << w["meaning_it"]
            out << w["label_it"]
            if info[:syllables] && eff["view"] != "decode"
              out.concat(info[:syllables])
              out << info[:syllables].join("-")
            end
            out.concat(info[:pieces].map { |p| mark_word(p["mark"]) }.uniq) if eff["view"] != "decode" && !info[:plain]
          end
          eff["arrows"].to_a.each { |a| out << a["label_it"] }
          out << (data["states"] ? (data["states"][[ state, data["states"].size - 1 ].min] || {})["op_it"] : nil)
          out << describe(data, state: state)
          out.compact.map(&:to_s).reject(&:empty?).uniq
        end
      end
    end
  end
end
