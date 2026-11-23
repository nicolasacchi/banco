module Grading
  module Closed
    # The `contractions: en` option of a normalized_text check (WAVE2 2.11, D-268): the contractions of the vetted table
    # english/contractions are expanded on both sides before the comparison, so "I'll go" and "I will go" are the same answer.
    #
    # A table row is {short, long: [readings], ambiguous?}. A short form is a whole word ("won't", "it's") or a suffix that
    # starts with an apostrophe or "n'" ("'ll", "n't"). A form marked ambiguous ('s, 'd after a noun) is never expanded: it stays
    # as typed, so "Anna's" is not read as "Anna is" when it could be a possessive. A form with several readings gives every
    # reading ("it's" is "it is" and "it has"); two texts are the same when some reading of one equals some reading of the other.
    #
    # It is on for the typed answers of the subject english (D-398, `option`), and for a check that asks for it (`contractions: en`).
    module Contractions
      APOSTROPHE = /[‘’‛ʼ`´′]/
      MAX_READINGS = 16

      class << self
        # The table rows, from config/banco/data/english/contractions.yml; tests may set another table.
        attr_writer :table

        def table
          @table ||= Lessons::VettedData.table("english/contractions")&.fetch("contractions") || []
        end

        def reset! = (@table = nil)

        # The value of a spec's `contractions` for a normalized_text answer: the one the author wrote, else "en" for the subject english
        # (D-398), else nil. Italian, Spanish and every other subject are never expanded.
        def option(subject, explicit = nil) = explicit.presence || (subject.to_s == "english" ? "en" : nil)

        # Is the table there?
        def ready? = table.any?
      end

      module_function

      # Every reading of +text+ (an already normalized string): the set of strings with its expandable contractions expanded.
      # Case is folded unless +case_sensitive+ (the item's policy): then the words keep their case, and an expanded form keeps the case of
      # the first letter of the contraction ("Doesn't" is "Does not", "I'd" is "I would"), so a case-sensitive answer stays case-sensitive.
      def readings(text, case_sensitive: false)
        words = text.to_s.gsub(APOSTROPHE, "'").split(" ")
        options = words.map { |w| word_readings(w, case_sensitive: case_sensitive) }
        out = [ [] ]
        options.each do |choices|
          out = out.flat_map { |prefix| choices.map { |c| prefix + [ c ] } }.first(MAX_READINGS)
        end
        out.map { |ws| ws.join(" ") }.uniq
      end

      def same?(a, b, case_sensitive: false) = (readings(a, case_sensitive: case_sensitive) & readings(b, case_sensitive: case_sensitive)).any?

      def word_readings(typed, case_sensitive: false)
        word = typed.downcase
        keep = ->(t) { case_sensitive ? t : t.downcase }
        rows = Contractions.table
        whole = rows.find { |r| !r["ambiguous"] && r["short"].downcase == word }
        if whole
          return whole["long"].map { |l| case_sensitive && typed[0] != word[0] ? l.sub(/\A./) { |c| c.upcase } : l.downcase }
        end

        suffix = rows.select { |r| !r["ambiguous"] && r["short"].start_with?("'", "n'") && word.length > r["short"].length && word.end_with?(r["short"].downcase) }
                     .max_by { |r| r["short"].length }
        return [ keep.(typed) ] unless suffix

        stem = keep.(typed).slice(0, word.length - suffix["short"].length)
        suffix["long"].map { |l| "#{stem} #{l.downcase.strip}" }
      end
    end
  end
end
