module Grading
  # The sentence a `___` blank sits in (D-339), read from the instance display's stem_it. Pure: no database, no clock.
  #
  # The frame is the line of the stem that holds the blank, after the last → on that line, without a leading label of one
  # or two words and a colon («Negativa: My parents ___ meat.» is «My parents ___ meat.»). The prefix is the words before
  # the blank, the suffix the words after it. A bracketed cue right after the blank («___ (get)») is not a word of the
  # sentence. Words compare case-insensitively, without the punctuation around them, with the apostrophes made one mark
  # and the direction of an accent ignored (D-296).
  #
  #   frame = Grading::Frame.from_stem("«La mia scuola non ha una biblioteca.» → My school ___ a library.")
  #   frame.part("My school doesn't have a library")  # => "doesn't have"
  class Frame
    BLANK = /_{3,}/
    LABEL = /\A[[:space:]]*\p{L}+(?:[[:space:]]+\p{L}+)?[[:space:]]*:[[:space:]]*/
    CUE = /(?<=_)[[:space:]]*\([^)]*\)/
    EDGE_PUNCTUATION = /\A[^\p{L}\p{N}]+|[^\p{L}\p{N}]+\z/
    # A word one letter off a word of the frame still counts as the frame's word (a plural, a typo) from this length.
    CLOSE_MIN_LETTERS = 4

    attr_reader :prefix, :suffix

    class << self
      # The frame of a stem, or nil when the stem does not hold exactly one blank or the sentence has no word besides it.
      def from_stem(stem)
        return nil unless stem.is_a?(String)

        text = plain(stem)
        return nil unless text.scan(BLANK).size == 1

        line = text.lines.find { |l| l.match?(BLANK) }.split("→").last.to_s.sub(LABEL, "")
        line = line.sub(CUE, "")
        before, after = line.split(BLANK, 2)
        frame = new(words(before), words(after))
        frame.prefix.empty? && frame.suffix.empty? ? nil : frame
      end

      # The word keys of a text: split at spaces, the punctuation around each word dropped, the empty ones left out.
      def words(text)
        text.to_s.split(/[[:space:]]+/).map { |t| key(t) }.reject(&:empty?)
      end

      def key(token, case_sensitive: false)
        t = Closed::Text.normalize(token.to_s, case_sensitive: case_sensitive).gsub(EDGE_PUNCTUATION, "")
        Closed::Text.fold_direction(t)
      end

      private

      # The markup of a stem (**bold**, [[en:span]]) is not part of the sentence.
      def plain(stem)
        stem.gsub(/\[\[(?:[a-z_]+(?:\|[a-z]+)?:)?/, "").gsub("]]", "").delete("*")
      end
    end

    def initialize(prefix, suffix)
      @prefix = prefix.freeze
      @suffix = suffix.freeze
    end

    # The words the student typed between the frame's prefix and suffix, as typed, when she wrote the whole sentence
    # (at least one word between); else nil.
    def part(answer)
      tokens = tokens_of(answer)
      return nil if tokens.size < prefix.size + suffix.size + 1
      return nil unless tokens.first(prefix.size).map(&:last) == prefix
      return nil unless suffix.empty? || tokens.last(suffix.size).map(&:last) == suffix

      between = tokens[prefix.size...(tokens.size - suffix.size)]
      answer[between.first.first.begin...between.last.first.end]
    end

    # How many different words of the frame (outside the blank) the answer holds, a word one letter off included.
    def shared_words(answer)
      mine = self.class.words(answer).uniq
      (prefix + suffix).uniq.count { |w| mine.any? { |m| close?(m, w) } }
    end

    private

    # [[range of the token in the text, its key], ...] for the tokens that hold a letter or a digit.
    def tokens_of(text)
      out = []
      text.to_s.scan(/\S+/) do |token|
        range = Regexp.last_match.begin(0)...Regexp.last_match.end(0)
        key = self.class.key(token)
        out << [ range, key ] unless key.empty?
      end
      out
    end

    def close?(a, b)
      return true if a == b

      [ a, b ].min_by(&:length).length >= CLOSE_MIN_LETTERS && Closed::Text.damerau(a, b) == 1
    end
  end
end
