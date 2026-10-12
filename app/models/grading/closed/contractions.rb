module Grading
  module Closed
    # The `contractions: en` option of a normalized_text check (WAVE2 2.11, D-267): the contractions of the vetted table
    # english/contractions are expanded on both sides before the comparison, so "I'll go" and "I will go" are the same answer.
    #
    # A table row is {short, long: [readings], ambiguous?}. A short form is a whole word ("won't", "I'm") or a suffix that
    # starts with an apostrophe or "n'" ("'ll", "n't"). A form marked ambiguous ('s, 'd) is never expanded: it stays as typed,
    # so "he's" is not read as "he is" when it could be "he has" or a possessive. A form with several readings gives every
    # reading; two texts are the same when some reading of one equals some reading of the other.
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

        # Is the table there? (The option is held back in lesson_types.yml until it is.)
        def ready? = table.any?
      end

      module_function

      # Every reading of +text+ (an already normalized string): the set of strings with its expandable contractions expanded.
      def readings(text)
        words = text.to_s.gsub(APOSTROPHE, "'").split(" ")
        options = words.map { |w| word_readings(w.downcase) }
        out = [ [] ]
        options.each do |choices|
          out = out.flat_map { |prefix| choices.map { |c| prefix + [ c ] } }.first(MAX_READINGS)
        end
        out.map { |ws| ws.join(" ") }.uniq
      end

      def same?(a, b) = (readings(a) & readings(b)).any?

      def word_readings(word)
        rows = Contractions.table
        whole = rows.find { |r| !r["ambiguous"] && r["short"].downcase == word }
        return whole["long"].map(&:downcase) if whole

        suffix = rows.select { |r| !r["ambiguous"] && r["short"].start_with?("'", "n'") && word.length > r["short"].length && word.end_with?(r["short"].downcase) }
                     .max_by { |r| r["short"].length }
        return [ word ] unless suffix

        stem = word.delete_suffix(suffix["short"].downcase)
        suffix["long"].map { |l| "#{stem} #{l.downcase.strip}" }
      end
    end
  end
end
