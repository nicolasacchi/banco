module Grading
  # The sentence a `___` blank sits in (D-339, D-352), read from the text the student was shown: the instance display's stem,
  # else the item's own stem (prompt.stem) when the blank is there. A bilingual item is read in its target language (Items::Text.stem), never in
  # the Italian translation. Pure: no database, no clock.
  #
  # The frame is the line of the text that holds the blank, after the last → before the blank, without the label before the
  # last colon that comes ahead of the blank («Negativa con will: She ___ the test.» is «She ___ the test.»). The prefix is the words before
  # the blank, the suffix the words after it. A bracketed cue right after the blank («___ (get)») is not a word of the
  # sentence. Words compare case-insensitively, without the punctuation around them, with the apostrophes made one mark
  # and the direction of an accent ignored (D-296). A line that is the instruction itself («… al posto di ___») is not a sentence
  # and does not count as a blank.
  #
  #   frame = Grading::Frame.from_stem("«La mia scuola non ha una biblioteca.» → My school ___ a library.")
  #   frame.part("My school doesn't have a library")  # => "doesn't have"
  #   frame.fill("doesn't have")                      # => "My school doesn't have a library."
  class Frame
    BLANK = /_{3,}/
    # «scrivi le parole che vanno al posto di ___»: the instruction names the blank, it is not the sentence that has one. In a bilingual item (D-402)
    # the instruction is in the language it teaches («Write the words in place of ___», «Escribe las palabras en lugar de ___»): the same line.
    INSTRUCTION = /(?:al[[:space:]]+posto[[:space:]]+di|in[[:space:]]+place[[:space:]]+of|en[[:space:]]+(?:el[[:space:]]+)?lugar[[:space:]]+de)[[:space:]]+_{3,}/i
    OPENING_APOSTROPHE = /\A(?:#{Closed::Text::APOSTROPHES.source}|')/
    # A label ends at a colon followed by a space: everything up to the last such colon before the blank is the instruction.
    LABEL_END = /:[[:space:]]/
    CUE = /(?<=_)[[:space:]]*\([^)]*\)/
    EDGE_PUNCTUATION = /\A[^\p{L}\p{N}]+|[^\p{L}\p{N}]+\z/
    # A word one letter off a word of the frame still counts as the frame's word (a plural, a typo) from this length.
    CLOSE_MIN_LETTERS = 4

    attr_reader :prefix, :suffix, :before, :after

    class << self
      # The frame of what the student was shown for a spec: the instance's stem when it holds exactly one blank, else the
      # item's stem and the instance's together (the blank may sit in the item's own prompt). nil when there is not exactly one
      # blank in the sentences shown, or no word besides it.
      def for_spec(spec)
        instance = Items::Text.stem(spec.display)
        from_stem(instance) || from_stem([ spec.prompt_stem, instance ].grep(String).join("\n"))
      end

      # The frame of a stem, or nil when the stem does not hold exactly one blank or the sentence has no word besides it.
      def from_stem(stem)
        return nil unless stem.is_a?(String)

        text = plain(stem).lines.grep_v(INSTRUCTION).join
        return nil unless text.scan(BLANK).size == 1

        line = text.lines.find { |l| l.match?(BLANK) }
        blank = line =~ BLANK
        arrow = line[0...blank].rindex("→")
        line = line[(arrow + 1)..] if arrow
        blank = line =~ BLANK
        cut = line[0...blank].rindex(LABEL_END)
        line = line[(cut + 1)..] if cut
        line = line.sub(CUE, "")
        before, after = line.split(BLANK, 2)
        frame = new(words(before), words(after), before: before.to_s.strip, after: after.to_s.strip)
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

    # prefix, suffix: the word keys; before, after: the sentence's own text each side of the blank (no label, no cue).
    def initialize(prefix, suffix, before: "", after: "")
      @prefix = prefix.freeze
      @suffix = suffix.freeze
      @before = before.to_s.freeze
      @after = after.to_s.freeze
    end

    # The whole sentence with +filler+ in the blank, as text. A filler that opens with an apostrophe ('s got) joins the word before it.
    def fill(filler)
      filler = filler.to_s.strip
      head = before.empty? ? "" : (filler.match?(OPENING_APOSTROPHE) ? before : "#{before} ")
      tail = after.empty? || after.match?(/\A[[:punct:]]/) ? after : " #{after}"
      "#{head}#{filler}#{tail}"
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
