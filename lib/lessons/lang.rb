# frozen_string_literal: true

module Lessons
  # The languages of a lesson's text (D-265, WAVE2 1.11): which subject teaches which language, the keys that hold words of a language
  # (`text_en`, `form_es`: the suffix names the language, firm rule 6), the Italian that the lint can tell in such a key, and the plain
  # reading of a text without its spans for the Italian lint. The JS twin of TARGET_OF is app/javascript/lesson/lang.js.
  module Lang
    # The language of a language subject's lesson: a colour role span there is target-language text unless it says |it.
    TARGET_OF = { "english" => "en", "spanish" => "es" }.freeze
    KEY = /_(en|es|la)\z/
    # Function words that Italian has and neither English nor Spanish has: two of them in a text under an _en or _es key is Italian.
    ITALIAN_WORDS = %w[il gli della dello delle degli nella nelle sono perché anche questo questa quella quello che è].freeze

    module_function

    def target(subject) = TARGET_OF[subject.to_s]

    # The subjects that teach +lang+ (config/banco/validation_rules.yml lesson2.target_languages): only these may hold its keys and spans.
    def taught?(subject, lang) = Array(Validation::Rules.get(:lesson2, :target_languages)[lang]).include?(subject.to_s)

    # "text_en" -> "en"; nil for any other key.
    def key_lang(key) = key.to_s[KEY, 1]

    # Whether +text+ is Italian rather than the language of its key (two distinct Italian-only function words).
    def italian?(text)
      words = text.to_s.downcase.scan(/\p{L}+/)
      (words & ITALIAN_WORDS).size >= 2
    end

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
