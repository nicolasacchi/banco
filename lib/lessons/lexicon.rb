# frozen_string_literal: true

module Lessons
  # The most frequent words of English and Spanish (config/banco/lexicon, see its README for source and licence; the first
  # lesson2.target_vocabulary_top, 3000, are the easy ones), for W-LANG-LEVEL:
  # a target-language word of a lesson that is outside them, outside the lesson's glossary and outside its teaches_en / teaches_es list is
  # a warning (the reviewer judges). Inflected forms are looked up through their plain form, and a word that has the Snowball stem of a listed word
  # (aprendes for aprender) is known too, as is an irregular form of a known verb (slept, ate, fui: `<lang>_irregular.txt`, form to verb); a name (a capital
  # letter inside a sentence) is not a word to teach. A word the lesson or the item teaches (its glossary, teaches_<lang>, the forms of its key and its errors)
  # is matched the same way: through its Snowball stem and its irregular verb, so «limpiar» in teaches_es covers «limpié», «limpiamos».
  module Lexicon
    DIR = File.expand_path("../../config/banco/lexicon", __dir__)
    LANGS = %w[en es].freeze
    EXTRA_LISTS = %w[grammar basic school].freeze
    MIN_STEM = 3
    WORD = /\p{L}[\p{L}'’]*/

    module_function

    # The first +top+ words of +lang+ (lesson2.target_vocabulary_top by default), as a set.
    def words(lang, top = Validation::Rules.get(:lesson2, :target_vocabulary_top))
      @lists ||= {}
      @lists[lang] ||= File.readlines(File.join(DIR, "#{lang}.txt"), chomp: true).reject(&:empty?)
      (@sets ||= {})[[ lang, top ]] ||= @lists[lang].first(top).to_set
    end

    # Whether +word+ (any case) or a plain form of it is in the first 3000 words of +lang+, or among the words of the language that its allowlists
    # add (D-402): the metalanguage of a language lesson (`<lang>_grammar.txt`: verb, singular, sílaba, tilde), the beginner words that the frequency
    # list lacks (`<lang>_basic.txt`: thirteen, grandad, pen, lección) and the school words of an A2 learner (`<lang>_school.txt`: exam, piano, homework);
    # or, for a word of another inflection of a listed word, when it has the Snowball stem of one of them (aprendes, buscas, quedáis, tenéis, with aprender,
    # buscar, quedar, tener in the list); or an irregular form whose verb is any of these (slept, with sleep).
    def known?(lang, word)
      return true unless LANGS.include?(lang)

      list = words(lang)
      extra = extras(lang)
      found = forms(lang, word.downcase.tr("’", "'"))
      found.any? { |f| list.include?(f) || extra.include?(f) } || found.first(2).any? { |f| (s = stem(lang, f)) && stems(lang).include?(s) } ||
        verbs(lang, found.first).any? { |v| list.include?(v) || extra.include?(v) || ((s = stem(lang, v)) && stems(lang).include?(s)) }
    end

    # The verbs of +form+ in `<lang>_irregular.txt` (one line a verb, `verb: form form ...`; a form may belong to two verbs, fui: ir, ser): [] for a regular word.
    def verbs(lang, form) = irregular(lang).fetch(form, [])

    # The table of `<lang>_irregular.txt`: form => [verb], frozen.
    def irregular(lang)
      (@irregular ||= {})[lang] ||= begin
        path = File.join(DIR, "#{lang}_irregular.txt")
        table = Hash.new { |h, k| h[k] = [] }
        if File.exist?(path)
          File.readlines(path, chomp: true).reject { |l| l.strip.empty? || l.start_with?("#") }.each do |line|
            verb, forms = line.downcase.tr("’", "'").split(":", 2)
            forms.to_s.split.each { |f| table[f] << verb.strip }
          end
        end
        table.default_proc = nil
        table.freeze
      end
    end

    # Is +word+ (a form, any case) one of +known+ (the words a lesson or an item teaches, lower case), or of the same Snowball stem or the same irregular verb as one
    # of them? +memo+ (a Hash) keeps the stems of +known+ between the words of one text.
    def taught?(lang, word, known, memo)
      w = word.downcase.tr("’", "'")
      return true if known.include?(w)

      stems = (memo[:stems] ||= known.filter_map { |k| stem(lang, k.to_s.downcase.tr("’", "'")) }.to_set)
      irregular = verbs(lang, w)
      return true if irregular.any? { |v| known.include?(v) }

      (forms(lang, w).first(2) + irregular).any? { |c| (s = stem(lang, c)) && stems.include?(s) }
    end

    # The Snowball stems of the listed words and the allowlists of +lang+ (the stemmer of the content search, Search::Text), as a set.
    def stems(lang)
      top = Validation::Rules.get(:lesson2, :target_vocabulary_top)
      (@stems ||= {})[[ lang, top ]] ||= (words(lang, top) | extras(lang)).filter_map { |w| stem(lang, w) }.to_set.freeze
    end

    # The stem of a word, nil for one too short to say anything («ten», «has»: a stem of fewer than 3 letters would match any word).
    def stem(lang, word)
      stemmed = Search::Text.stem(word, lang)
      stemmed.length >= MIN_STEM ? stemmed : nil
    end

    # The words of `<lang>_grammar.txt`, `<lang>_basic.txt` and `<lang>_school.txt` (one word to a line, `#` comments), lower case, as a set.
    def extras(lang)
      (@extras ||= {})[lang] ||= EXTRA_LISTS.flat_map do |kind|
        path = File.join(DIR, "#{lang}_#{kind}.txt")
        File.exist?(path) ? File.readlines(path, chomp: true).reject { |l| l.strip.empty? || l.start_with?("#") }.flat_map { |l| l.downcase.tr("’", "'").split } : []
      end.to_set.freeze
    end

    def forms(lang, w)
      base = w.sub(/'(s|ll|re|ve|d|m)\z/, "")
      base = base.sub(/n't\z/, "") if lang == "en"
      out = [ w, base ]
      if lang == "en"
        out += [ base.sub(/s\z/, ""), base.sub(/es\z/, ""), base.sub(/ies\z/, "y"), base.sub(/ed\z/, ""), base.sub(/ed\z/, "e"), base.sub(/(.)\1ed\z/, '\1'),
                 base.sub(/ing\z/, ""), base.sub(/ing\z/, "e"), base.sub(/(.)\1ing\z/, '\1'), base.sub(/ly\z/, ""), base.sub(/er\z/, ""), base.sub(/est\z/, "") ]
      else
        out += [ base.sub(/s\z/, ""), base.sub(/es\z/, ""), base.sub(/[ao]s?\z/, "o"), base.sub(/[ao]s?\z/, "a"), base.sub(/mente\z/, ""), base.sub(/ción\z/, "") ]
      end
      out.uniq
    end

    # The words of +text+ (a target-language sentence or more) that need teaching: outside the lists and outside +known+ (downcased words
    # of the glossary and of teaches_*). A capitalised word inside a sentence is a name and is skipped.
    def unknown(lang, text, known: [])
      out = []
      memo = {}
      Validation::Readability.sentences_of(text.to_s).each do |sentence|
        sentence.scan(WORD).each_with_index do |word, i|
          next if word.length == 1
          next if i.positive? && word.match?(/\A\p{Lu}/)
          next if known?(lang, word) || taught?(lang, word, known, memo)

          out << word.downcase
        end
      end
      out.uniq
    end
  end
end
