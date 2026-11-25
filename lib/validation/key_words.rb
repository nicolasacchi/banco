# frozen_string_literal: true

module Validation
  # Keys that are everyday words of the language taught (D-402, round 6). A key such as «in», «at», «es», «hay», «está» is a function word: it is in every
  # sentence, so the scans that look for the key in a hint (E-HINT-KEY), in the answer format and the steps (E-SUPPORT-LEAK) and in an error message
  # (W-MESSAGE-GIVES-KEY) fired on «Look at the lesson card» and forced the authors into stilted English and Spanish («dónde se encuentra»). For such a key
  # (three letters or fewer, or a word of the short list of its language) a text leaks it only when
  #
  #   - the key is quoted: in «...», “...”, "...", a [[..:..]] span or a code span;
  #   - or the text names it as the answer: «Write at», «la respuesta es está», or a line that is only the key;
  #   - or the key stands in the same sentence as a content word of the frame of the instance (the words just before and just after the gap of its
  #     sentence): «el gato está en la cocina» for «El gato ___ en la cocina».
  #
  # A longer key, and every key of a legacy (Italian) revision, is scanned as before (Answers.contains_after_lead?).
  module KeyWords
    SHORT = 3
    FUNCTION = {
      "en" => %w[a an the is are am was were be been in on at of to for by with from and or but do does did have has had can will would not it he she we you they
                 i my your his her its our their this that there here no so as if].freeze,
      "es" => %w[es son soy eres somos sois está están estoy estás estamos estáis hay he has ha hemos han el la los las un una unos unas en de del a al por para con sin
                 sobre y o e u que se lo le les me te nos mi tu su ya no muy].freeze
    }.freeze
    EVERY_FUNCTION_WORD = FUNCTION.values.flatten.to_set.freeze
    WORD = /\p{L}[\p{L}'’]*/
    # What a text quotes: «...», “...”, "...", ‘...’, a 'word' between apostrophes, a [[lang:...]] or colour-role span, a `code` span.
    QUOTED = /«([^»]*)»|“([^”]*)”|"([^"]*)"|‘([^’]*)’|(?<![\p{L}\p{N}])'([^'\n]+)'(?![\p{L}\p{N}])|\[\[[a-z]+(?:[_-][a-z]+)*(?:\|it)?:(.*?)\]\](?!\])|`([^`]*)`/m
    # The verbs and the phrases with which a hint names the word to type: «Write at», «Escribe está», «Scrivi in», «the answer is on».
    CUE = "write|type|enter|use|put|insert|choose|pick|say|answer(?: is)?|the (?:answer|key|word|form) is|escribe|usa|pon|elige|responde|completa con|" \
          "la (?:respuesta|palabra|forma) es|scrivi|metti|scegli|rispondi|inserisci|la (?:risposta|parola|forma) è"
    NOUN = "word|form|verb|preposition|article|palabra|forma|verbo|preposición|artículo|parola|preposizione|articolo"
    AFTER = "is the (?:answer|key)|es la respuesta|è la risposta|goes here|va aquí|va qui"

    module_function

    # Is +needle+ a key to be read as an everyday word of +lang+ (en or es; nil for any other subject)? Only a single word of letters is.
    def everyday?(needle, lang)
      word = Answers.plain(needle)
      FUNCTION.key?(lang.to_s) && word.match?(/\A\p{L}+\z/) && (word.length <= SHORT || FUNCTION.fetch(lang.to_s).include?(word))
    end

    # Does +text+ leak the everyday key +needle+? +frame+: the frame words of the instance (see +frame+).
    def leak?(text, needle, frame: [])
      key = Answers.plain(needle)
      plain = Answers.plain(text)
      return false unless Answers.token_match?(plain, key)

      quoted?(text, key) || named?(text, plain, key) || framed?(text, key, frame)
    end

    # The words just before and just after the gap of +stem+ (the line with the ___ of it), two on each side, lower case; [] when it has no gap. A bracketed cue
    # right after the gap, «___ (study)», is not a frame word.
    def frame(stem)
      line = stem.to_s.lines.find { |l| l.match?(/_{2,}/) } or return []
      before, after = line.gsub(/_{2,}\s*\([^)]*\)/, "___").split(/_{2,}/, 2)
      (before.to_s.scan(WORD).last(2) + after.to_s.scan(WORD).first(2)).map { |w| w.downcase.tr("’", "'") }
    end

    def quoted?(text, key)
      text.scan(QUOTED).any? { |groups| groups.compact.any? { |segment| Answers.token_match?(Answers.plain(segment), key) } }
    end

    # «Write at», «the answer is está», «at is the answer», or a line with nothing but the key.
    def named?(text, plain, key)
      word = Regexp.escape(key)
      plain.match?(/(?<![[:alnum:]])(?:#{CUE})\s+(?:(?:the|el|la|il|lo)\s+(?:#{NOUN})\s+)?[«“"‘']?#{word}(?![[:alnum:]])/) ||
        plain.match?(/(?<![[:alnum:]])#{word}[»”"’']?\s+(?:#{AFTER})(?![[:alnum:]])/) ||
        text.lines.any? { |line| line.gsub(/[[:punct:][:space:]«»“”‘’¿¡]/, "").downcase == key }
    end

    # The key and a content word of the frame (a word that is not a function word) in one sentence; a frame of function words only needs all of them.
    def framed?(text, key, frame)
      return false if frame.empty?

      content = frame.reject { |w| EVERY_FUNCTION_WORD.include?(w) || w.length < SHORT }
      text.split(/[.!?;:\n]+/).any? do |sentence|
        plain = Answers.plain(sentence)
        next false unless Answers.token_match?(plain, key)

        present = ->(w) { Answers.token_match?(plain, w) }
        content.empty? ? frame.all?(&present) : content.any?(&present)
      end
    end
  end
end
