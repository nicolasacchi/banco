# frozen_string_literal: true

module Lessons
  # Words: The split notation shared by paradigm and word_parts (| stem and ending, [..] changed letters, + attached piece), Spanish syllables and stress.
  # Built by T3 (WAVE2 1.10, batch w2-1). The JS twin is app/javascript/lesson/lib/words.js and both run test/fixtures/lesson2/spanish_words.json (like
  # Lessons::Num and lesson/num.js). `present` is the W2-2 half and is not built yet.
  #
  # The Spanish engine follows the RAE rules in the form a school book gives them:
  #   - a vowel is a e i o u (with tilde, and the diaeresis u); a final y after a vowel and a lone y are vowels; ch, ll, rr, and qu, gu before e or i, are one
  #     consonant (the u of que, gui is silent; the u of güe, güi is a vowel);
  #   - two strong vowels (a e o) are two syllables; a strong and a weak one (i u), or two different weak ones, are one (a diphthong); a weak vowel with a
  #     written tilde (í, ú) next to a strong one is a hiatus; two equal vowels are two syllables; a weak vowel between two strong ones goes with the second;
  #   - one consonant goes with the vowel after it; of two or more, the last goes with the vowel after it, unless the last two are p b f g c k t d plus
  #     l or r (except dl, tl): then both do; h is a consonant (ahumar is a-hu-mar);
  #   - stress: a written tilde says it; else a word that ends in a vowel, n, or s (not after another consonant) falls on the last syllable but one, and any
  #     other word on the last; a monosyllable is its one syllable. A final y counts as a consonant.
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

    Refused = Class.new(ArgumentError)

    ACCENTED = "áéíóú"
    STRONG = %w[a e o á é ó].freeze
    WEAK = %w[i u ü í ú].freeze
    VOWELS = (STRONG + WEAK).freeze
    TILDE_WEAK = %w[í ú].freeze
    INSEPARABLE = %w[pl pr bl br fl fr gl gr cl cr kl kr tr dr].freeze
    # words that carry a tilde in a monosyllable or against the rule only to tell them from another word (and the question words)
    DIACRITIC = %w[tú él mí sí sé té dé más aún qué quién quiénes cuál cuáles cuán cuándo cuánto cuánta cuántos cuántas cómo dónde adónde].freeze

    module_function

    # A form in split notation as pieces with their marks; the marks removed give the word.
    # Returns {"pieces" => [{"text", "mark", "group"}], "word" => String}. The marks: "stem" (before the first |), "ending" (after a |),
    # "attached" (after a +), "change" (inside [..]); a "group" is a piece between | and + (the pieces of a decode), counted from 0.
    def split(notation)
      raise Refused, "the form must be a text" unless notation.is_a?(String)
      raise Refused, "the form is empty" if notation.empty?
      raise Refused, "no spaces in a form" if notation.match?(/\s/)

      pieces = []
      group = 0
      mark = "stem"
      buf = +""
      inside = false
      flush = lambda do |m|
        pieces << { "text" => buf.dup, "mark" => m, "group" => group } unless buf.empty?
        buf.clear
      end
      base = "stem"
      notation.each_char do |ch|
        case ch
        when "["
          raise Refused, "[ inside [ ]" if inside
          flush.call(mark)
          inside = true
        when "]"
          raise Refused, "] without [" unless inside
          raise Refused, "[] is empty" if buf.empty?
          flush.call("change")
          inside = false
          mark = base
        when "|", "+"
          raise Refused, "#{ch} inside [ ]" if inside
          raise Refused, "a piece before #{ch} is missing" if pieces.empty? && buf.empty?
          flush.call(mark)
          raise Refused, "two separators in a row" if pieces.last["group"] != group
          group += 1
          base = ch == "|" ? "ending" : "attached"
          mark = base
        else
          buf << ch
        end
      end
      raise Refused, "[ is not closed" if inside
      flush.call(mark)
      raise Refused, "a piece after the last separator is missing" if pieces.empty? || pieces.last["group"] != group

      { "pieces" => pieces, "word" => pieces.sum("") { |p| p["text"] } }
    end

    # The syllables of a Spanish word.
    def syllables_es(word)
      units = units_of(word)
      nuclei = nuclei_of(units)
      return [ word.dup ] if nuclei.size <= 1

      cuts = []
      nuclei.each_cons(2) do |a, b|
        cons = (a[:to] + 1...b[:from]).to_a
        cuts << if cons.empty?
          b[:from]
        elsif cons.size == 1
          cons.first
        elsif INSEPARABLE.include?(units[cons[-2]][:low] + units[cons[-1]][:low]) && units[cons[-2]][:len] == 1 && units[cons[-1]][:len] == 1
          cons[-2]
        else
          cons.last
        end
      end
      spans = []
      from = 0
      cuts.each do |unit|
        at = units[unit][:at]
        spans << word[from...at]
        from = at
      end
      spans << word[from..]
      spans
    end

    # The 1-based index of the stressed syllable.
    def stress_es(word)
      syls = syllables_es(word)
      marked = syls.each_index.select { |i| syls[i].downcase.each_char.any? { |c| ACCENTED.include?(c) } }
      raise Refused, "#{word}: two written tildes" if marked.size > 1
      return marked.first + 1 if marked.any?

      default_stress(syls, word.downcase)
    end

    # Whether the written tilde (or its absence) follows the stress rule: false for a tilde that is not needed (cámara is right, camára
    # is not; a tilde on a monosyllable such as fué, or on the stressed syllable of a word that is stressed there anyway); a word with no tilde
    # cannot be told wrong, because the engine does not know how it is said.
    def tilde_ok?(word)
      low = word.downcase
      return true if DIACRITIC.include?(low)

      syls = syllables_es(word)
      marked = syls.each_index.select { |i| syls[i].downcase.each_char.any? { |c| ACCENTED.include?(c) } }
      return true if marked.empty?
      return false if marked.size > 1 || syls.size == 1
      return true if hiatus_tilde?(syls, marked.first)

      marked.first + 1 != default_stress(syls, low.tr(ACCENTED, "aeiou"))
    end

    # The words of a Spanish text whose tilde the stress rule does not need (W-ES-TILDE, a warning: the reviewer judges). A word the engine cannot
    # read (a number, a foreign word) is let be.
    def tilde_warnings(text)
      text.to_s.scan(/[[:alpha:]]+/).select do |word|
        word.match?(/[áéíóúÁÉÍÓÚ]/) && !tilde_ok?(word)
      rescue Refused
        false
      end.uniq
    end

    # W2-2: the six present forms by pattern; spanish/verbs is the truth and the engine only cross-checks regular and stem-changing rows.
    def present(verb, pattern)
      raise NotBuilt, "Lessons::Words.present is not built yet (T3, w2-2)"
    end

    # ---- inside the engine -----------------------------------------------------------------------------------------------------

    # The default stress of a word without a written tilde (syls: its syllables; low: the word in lower case).
    def default_stress(syls, low)
      return 1 if syls.size == 1

      last = low[-1]
      ends_open = VOWELS.include?(last) || last == "n" || (last == "s" && VOWELS.include?(low[-2].to_s))
      ends_open ? syls.size - 1 : syls.size
    end

    # A tilde on í or ú next to a strong vowel keeps the hiatus (día, país, baúl).
    def hiatus_tilde?(syls, index)
      syl = syls[index].downcase
      at = syl.index(/[íú]/)
      return false unless at

      before = syl[at - 1] if at.positive?
      after = syl[at + 1]
      return true if before && STRONG.include?(before)
      return true if after && STRONG.include?(after)

      # the strong vowel can be in the next or the previous syllable (dí-a, pa-ís, ba-úl)
      (index.positive? && at.zero? && STRONG.include?(syls[index - 1].downcase[-1].to_s)) || (at == syl.length - 1 && index < syls.size - 1 && STRONG.include?(syls[index + 1].downcase[0].to_s))
    end

    # The word as units: {low:, vowel:, len:, at:} a vowel or a consonant (a digraph is one unit); at is the index of its first letter.
    def units_of(word)
      raise Refused, "#{word.inspect}: a word of letters only" unless word.is_a?(String) && word.match?(/\A[[:alpha:]]+\z/)

      low = word.downcase
      units = []
      i = 0
      while i < low.length
        c = low[i]
        n = low[i + 1]
        d = low[i + 2]
        if %w[ch ll rr].include?("#{c}#{n}")
          units << { low: "#{c}#{n}", vowel: false, len: 2, at: i }
          i += 2
        elsif (c == "q" || c == "g") && n == "u" && %w[e i é í].include?(d.to_s)
          units << { low: "#{c}u", vowel: false, len: 2, at: i }
          i += 2
        elsif VOWELS.include?(c) || (c == "y" && i == low.length - 1 && (i.zero? || VOWELS.include?(low[i - 1].to_s)))
          units << { low: c, vowel: true, len: 1, at: i }
          i += 1
        else
          units << { low: c, vowel: false, len: 1, at: i }
          i += 1
        end
      end
      units
    end

    # The nuclei of the syllables: runs of vowel units cut at hiatus. [{from:, to:}] as indexes of units.
    def nuclei_of(units)
      nuclei = []
      i = 0
      while i < units.size
        unless units[i][:vowel]
          i += 1
          next
        end
        j = i
        j += 1 while j + 1 < units.size && units[j + 1][:vowel]
        run = (i..j).to_a
        start = run.first
        run.each_cons(2) do |a, b|
          next if joined?(units, a, b, run)

          nuclei << { from: start, to: a }
          start = b
        end
        nuclei << { from: start, to: run.last }
        i = j + 1
      end
      nuclei
    end

    # Whether two neighbouring vowels are one syllable.
    def joined?(units, a, b, run)
      x = units[a][:low]
      y = units[b][:low]
      sx = STRONG.include?(x)
      sy = STRONG.include?(y)
      wx = WEAK.include?(x) || x == "y"
      wy = WEAK.include?(y) || y == "y"
      return false if sx && sy

      if wx && wy
        base = ->(v) { v.tr("íúü", "iuu").tr("y", "i") }
        return base.call(x) != base.call(y)
      end
      return false if TILDE_WEAK.include?(x) || TILDE_WEAK.include?(y)

      # a weak vowel between two strong ones goes with the second (a-ia, not ai-a)
      return false if sx && wy && b < run.last && STRONG.include?(units[b + 1][:low])

      true
    end
  end
end
