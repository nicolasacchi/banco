# frozen_string_literal: true

module Lessons
  # The languages of a lesson's text (D-266, WAVE2 1.11): which subject teaches which language, the keys that hold words of a language
  # (`text_en`, `form_es`: the suffix names the language, firm rule 6), the Italian that the lint can tell in such a key, and the plain
  # reading of a text without its spans for the Italian lint. The JS twin of TARGET_OF is app/javascript/lesson/lang.js.
  # D-402: in a bilingual revision of english or spanish each text is a pair, the target under `<base>_en|_es` and its Italian under
  # `<base>_it`; `pick` and `pair?` read a field either way, Lessons::Bilingual walks and folds the pairs.
  module Lang
    # The language of a language subject's lesson: a colour role span there is target-language text unless it says |it.
    TARGET_OF = { "english" => "en", "spanish" => "es" }.freeze
    KEY = /_(en|es|la)\z/
    # Function words that Italian has and neither English nor Spanish has: two of them in a text under an _en or _es key is Italian.
    ITALIAN_WORDS = %w[il gli della dello delle degli nella nelle sono perché anche questo questa quella quello che è].freeze
    # The mirror of ITALIAN_WORDS (D-402): function words of the target language that Italian does not have, so two of them in a text under an
    # `_it` key mean that the "translation" is not Italian (E-LANG-TRANSLATION-LANG). No word that is also Italian: not a, in, me, come, con, una, al, lo,
    # and not «del» (Spanish and Italian), «es» (Spanish «es», the ending «-es», Italian «es.» for esempio) or «son» (Spanish, archaic Italian).
    # test/lib/lessons/lang_test.rb checks both lists against ITALIAN_WORDS and ITALIAN_FUNCTION_WORDS.
    TARGET_WORDS = {
      "en" => %w[the and with this that these those you your they their have has had will would not from what which when because his her was were does did].freeze,
      "es" => %w[el los las unos unas está están muy también yo usted ustedes que por para donde cuando porque tengo tiene hay].freeze
    }.freeze
    # Italian function words, a superset of ITALIAN_WORDS (D-402): the leak scans of the Italian layer never take one of them for the key (the Italian
    # «perché» of «porque» is not a leak of it); a needle of fewer than DISTINCT_MIN letters is never distinctive either.
    ITALIAN_FUNCTION_WORDS = (ITALIAN_WORDS + %w[
      a ad al allo alla alle ai agli col con da dal dallo dalla dalle dai dagli di del dei dentro dopo e ed fra tra in nel nei su sul sulla sulle per
      un uno una lo la le l i mi ti si ci vi ne lui lei noi voi loro io tu egli ella esso essa non no sì ma o oppure se come dove quando quale quali
      quanto quanta quanti quante cosa chi cui mentre poi prima ora già ancora sempre mai molto poco più meno tutto tutta tutti tutte ogni altro altra
      altri altre stesso stessa stessi stesse ho hai ha abbiamo avete hanno sei siamo siete era erano sarà saranno può possono deve devono fa fanno
      va vanno sta stanno qui qua là lì così allora quindi però perciò dunque ecco
    ]).freeze
    DISTINCT_MIN = 5
    # The languages of a pair: the siblings `<base>_en` and `<base>_es` (Latin keys are quoted words, never a translated text).
    PAIR_LANGS = TARGET_OF.values.freeze

    module_function

    def target(subject) = TARGET_OF[subject.to_s]

    # The subjects that teach +lang+ (config/banco/validation_rules.yml lesson2.target_languages): only these may hold its keys and spans.
    def taught?(subject, lang) = Array(Validation::Rules.get(:lesson2, :target_languages)[lang]).include?(subject.to_s)

    # "text_en" -> "en"; nil for any other key.
    def key_lang(key) = key.to_s[KEY, 1]

    # The language of the target sibling of +base+ in +hash+ ("en" or "es"), nil when it has none.
    def sibling_lang(hash, base) = PAIR_LANGS.find { |lang| hash.key?("#{base}_#{lang}") }

    # Whether +hash+ holds the pair of +base+: the target text and its Italian.
    def pair?(hash, base) = !sibling_lang(hash, base).nil? && hash.key?("#{base}_it")

    # The text of +base+ that the target layer shows: `<base>_<lang>` when the hash has it, else `<base>_it` (a legacy field, or an
    # Italian-only one), so a legacy revision and a bilingual one are read by the same code. For the fields of rule R2 (an option's `text`,
    # `final`, a table's `header`/`rows`, `quote.text`) the bare key is the target text and is read as it is: pick is for R1 fields.
    def pick(hash, base, lang: nil)
      lang ||= sibling_lang(hash, base)
      (lang && hash["#{base}_#{lang}"]) || hash["#{base}_it"]
    end

    # Whether +text+ is Italian rather than the language of its key (two distinct Italian-only function words).
    def italian?(text)
      words = quoted_out(text).downcase.scan(/\p{L}+/)
      (words & ITALIAN_WORDS).size >= 2
    end

    # Words that are quoted, not said: «...», "...", a [[it:..]] span (Italian quoted inside target text, D-402), a span of a language, a code span.
    QUOTED = /«[^»]*»|"[^"]*"|“[^”]*”|\[\[(?:it|en|es|la|code):.*?\]\](?!\])/m

    # +text+ without what it quotes: the words that the language of a text is told from.
    def quoted_out(text) = text.to_s.gsub(QUOTED, " ")

    # +text+ as the Italian lint reads it, and the foreign pieces it leaves out: [italian, [[lang, words]]]. A span of another language
    # and a code span stand for one word ("m", like a formula); in a lesson of a language subject (+target+) a colour role span is
    # target-language text and goes the same way unless it says |it; [[g:term]] and [[role|it:words]] are Italian and show their words.
    def split(text, target: nil)
      foreign = []
      plain = text.gsub(/\[\[(en|es|la):(.*?)\]\](?!\])/m) { foreign << [ Regexp.last_match(1), Regexp.last_match(2) ]; " m " }
                  .gsub(/\[\[code:(.*?)\]\](?!\])/m, " m ")
                  .gsub(/\[\[g:(.*?)\]\](?!\])/m, '\1')
                  .gsub(/\[\[[a-z]+(?:[_-][a-z]+)*\|it:(.*?)\]\](?!\])/m, '\1')
      plain = plain.gsub(/\[\[[a-z]+(?:[_-][a-z]+)*:(.*?)\]\](?!\])/m) { foreign << [ target, Regexp.last_match(1) ]; " m " } if target
      plain = plain.gsub(/\[\[[a-z]+(?:[_-][a-z]+)*:(.*?)\]\](?!\])/m, '\1')
      plain = plain.gsub(/\[([^\[\]]*)\]\((?:scheda|argomento):[^()]*\)/, '\1')
      [ plain, foreign ]
    end

    # Every string under a key of +language+ in +node+: [pointer, key, string].
    def keyed(node, pointer = "", &block)
      return enum_for(:keyed, node, pointer) unless block

      case node
      when Hash
        node.each do |k, v|
          at = "#{pointer}/#{k}"
          if key_lang(k) && v.is_a?(String) then yield at, k.to_s, v
          elsif key_lang(k) && v.is_a?(Array) && v.all?(String) then v.each_with_index { |t, i| yield "#{at}/#{i}", k.to_s, t }
          else keyed(v, at, &block)
          end
        end
      when Array then node.each_with_index { |v, i| keyed(v, "#{pointer}/#{i}", &block) }
      end
    end

    # The target languages that the keys under +node+ use (a figure holds at most one besides Italian).
    def languages_in(node) = keyed(node).map { |_, key, _| key_lang(key) }.uniq
  end
end
