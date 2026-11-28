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
    # Round 10: the contraction needs a word before it. A text that starts with a suffix is read as a fragment only when the gap it fills has
    # a word before it (`fragment: true`, the default; `Closed::Text` passes false when the frame opens with the gap: «___ Jack coming…?»
    # is not answered by «'s Jack coming»). «n't» expands only after the auxiliary of standard English (NEGATABLE: isn't, aren't, wasn't,
    # weren't, doesn't, don't, didn't, hasn't, haven't, hadn't, couldn't, wouldn't, shouldn't, mustn't, needn't, mightn't, daren't), so
    # «amn't» and «ain't» stay as typed and are wrong. «'s» is «has» only before a past participle or «got» («she's got», «she's gone»,
    # «she's just finished»): before anything else it is «is» only, so «Emma's a bad cold» is not «Emma has a bad cold».
    #
    # It is on for the typed answers of the subject english (D-398, `option`), and for a check that asks for it (`contractions: en`).
    #
    # A fragment (round 5 of the bilingual tooling): a text that STARTS with a suffix of the table, "'s scared", "'d better", is the
    # filler of a gap after a subject ("My friend ___ of deep water"). With nothing before it there is no noun for a possessive, so
    # the ambiguous forms are read too: "'s" is "is" or "has", "'d" is "would" or "had". The key decides which reading is meant:
    # "'s scared" is right for "is scared" and for "has scared", and wrong for "was scared". Only the first word is read so: an "'s"
    # after a word keeps the rule above.
    #
    # The typed side only (round 8): what the student TYPED is read one step further. An ambiguous "'s" or "'d" after a noun ("My sister's got a
    # cold") is read as a possessive and as each verb reading, so the key picks the reading it needs; the key and the accept entries are never
    # read so (a possessive key is not "is"). "'s" is both "is" and "has", and the reading that the key needs is the one that counts: a declared
    # error value that is the OTHER reading ("is got" for the key "has got") does not make "'s got" or "she's got" an error. The reading that
    # is itself a declared error value never makes an answer right (`accepts?`, `except:`), so an accept entry "'s got" does not accept "is got".
    module Contractions
      APOSTROPHE = /[‘’‛ʼ`´′]/
      MAX_READINGS = 16
      # The words that take «n't» in standard English (the vetted table's own list of the regular negatives); «n't» after any other word stays as typed.
      NEGATABLE = %w[is are was were does do did has have had could would should must need might dare].freeze
      # What may stand between «'s» and its participle: «she's just gone», «she's never been».
      PARTICIPLE_ADVERBS = %w[just already never ever always also still recently finally not only].freeze
      # The irregular past participles (the regular ones end in «ed») that follow a «has» that was written «'s».
      IRREGULAR_PARTICIPLES = %w[been begun bent bought brought built burnt caught chosen come cost cut dealt done drawn drunk driven eaten fallen
                                 felt fought found flown forgotten forgiven frozen given gone got gotten grown had heard hidden hit held hurt kept
                                 known laid led left lent let lain lit lost made meant met paid put quit read ridden rung risen run said seen
                                 sold sent set shaken shone shot shown shut sung sunk sat slept slid spoken spent spread stood stolen stuck struck
                                 sworn swept swum taken taught torn told thought thrown understood woken won worn written].freeze

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
      # +after+: the words of the sentence that follow the text when it fills a gap (the frame's suffix), which tell «'s» at the end of the text what comes next.
      def readings(text, case_sensitive: false, typed: false, fragment: true, after: [])
        words = text.to_s.gsub(APOSTROPHE, "'").split(" ")
        options = words.each_with_index.map do |w, i|
          choices = (i.zero? && fragment && fragment_readings(w)) || word_readings(w, case_sensitive: case_sensitive, ambiguous: typed)
          has_needs_participle(w, words[(i + 1)..] + after, choices)
        end
        out = [ [] ]
        options.each do |choices|
          out = out.flat_map { |prefix| choices.map { |c| prefix + [ c ] } }.first(MAX_READINGS)
        end
        out.map { |ws| ws.join(" ") }.uniq
      end

      # The readings of a bare suffix word ("'s" is is or has), whether or not the table marks it ambiguous; nil for any other word.
      def fragment_readings(word)
        return nil unless word&.start_with?("'")

        Contractions.table.find { |r| r["short"].start_with?("'") && r["short"].downcase == word.downcase }&.fetch("long")&.map { |l| l.downcase.strip }
      end

      # «'s» is «has» only before a past participle or «got»; with nothing after it the sentence may go on after the gap, so both readings stay.
      def has_needs_participle(word, rest, choices)
        return choices unless word.downcase.end_with?("'s") && rest.any? && !participle_ahead?(rest)

        kept = choices.reject { |c| c.split(" ").last.to_s.downcase == "has" }
        kept.empty? ? choices : kept
      end

      def participle_ahead?(rest)
        word = rest.find { |w| !PARTICIPLE_ADVERBS.include?(w.downcase) } or return true
        w = word.downcase.gsub(/\A[^a-z]+|[^a-z]+\z/, "")
        w == "got" || IRREGULAR_PARTICIPLES.include?(w) || (w.length > 3 && w.end_with?("ed"))
      end

      def same?(a, b, case_sensitive: false) = (readings(a, case_sensitive: case_sensitive) & readings(b, case_sensitive: case_sensitive)).any?

      # Would the +accepted+ text (the key, an accept entry) take what the student +typed+? The typed side is read with its ambiguous 's and 'd
      # (see above); a reading in +except+ (the declared error values, as normalized) never counts, so a reading that is itself an error
      # value does not make the answer right.
      def accepts?(accepted, typed, case_sensitive: false, except: [], fragment: true, after: [])
        ((readings(typed, case_sensitive: case_sensitive, typed: true, fragment: fragment, after: after) & readings(accepted, case_sensitive: case_sensitive, fragment: fragment, after: after)) - except).any?
      end

      # +ambiguous+: also read the ambiguous suffix of a typed word ("sister's": the word as typed, "sister is", "sister has").
      def word_readings(typed, case_sensitive: false, ambiguous: false)
        word = typed.downcase
        keep = ->(t) { case_sensitive ? t : t.downcase }
        rows = Contractions.table
        # a bare suffix ('re, n't) is no whole word: it is read as a fragment at the start of a gap's filler (fragment_readings) or not at all
        whole = rows.find { |r| !r["ambiguous"] && !r["short"].start_with?("'", "n'") && r["short"].downcase == word }
        if whole
          return whole["long"].map { |l| case_sensitive && typed[0] != word[0] ? l.sub(/\A./) { |c| c.upcase } : l.downcase }
        end

        suffix = rows.select { |r| !r["ambiguous"] && r["short"].start_with?("'", "n'") && word.length > r["short"].length && word.end_with?(r["short"].downcase) && negatable?(r, word) }
                     .max_by { |r| r["short"].length }
        return ambiguous_readings(typed, word, keep, rows, ambiguous) unless suffix

        stem = keep.(typed).slice(0, word.length - suffix["short"].length)
        suffix["long"].map { |l| "#{stem} #{l.downcase.strip}" }
      end

      # The «n't» suffix only after the auxiliary of standard English: «amn't» and «ain't» are not contractions to expand.
      def negatable?(row, word) = row["short"] != "n't" || NEGATABLE.include?(word.delete_suffix("n't"))

      # A word that ends with an ambiguous suffix: as typed, and (typed side only) with each of the suffix's readings.
      def ambiguous_readings(typed, word, keep, rows, ambiguous)
        as_typed = [ keep.(typed) ]
        return as_typed unless ambiguous

        row = rows.select { |r| r["ambiguous"] && r["short"].start_with?("'") && word.length > r["short"].length && word.end_with?(r["short"].downcase) }
                  .max_by { |r| r["short"].length }
        return as_typed unless row

        stem = keep.(typed).slice(0, word.length - row["short"].length)
        as_typed + row["long"].map { |l| "#{stem} #{l.downcase.strip}" }
      end
    end
  end
end
