module Grading
  # Grading::Closed (A-01): the components whose answer can be settled with
  # certainty in Ruby. Choice, ordering and matching compare ids; number and
  # fraction compare exact rationals; normalized_text compares normalized strings.
  # No I/O, no database, no clock.
  module Closed
    GRADER = "closed".freeze
    # A matching with all pairs right but one counts as right when the key has at least this many pairs (D-301).
    NEARLY_CORRECT_MIN_PAIRS = 3
    # Never with fewer right options than this (D-314): in a right/wrong judge (two options) one option for every row
    # can be all right but one. Nor when the answer gives one right option to every left row.
    NEARLY_CORRECT_MIN_RIGHT = 3

    class << self
      def grade(spec, value, id_map: nil)
        case spec.component
        when "choice" then choice(spec, value, id_map)
        when "ordering" then ordering(spec, value, id_map)
        when "matching" then matching(spec, value, id_map)
        when "number" then Numbers.grade(spec, value)
        when "fraction" then Fractions.grade(spec, value)
        when "normalized_text" then normalized_text(spec, value)
        else raise ArgumentError, "Grading::Closed does not grade #{spec.component.inspect}"
        end
      end

      def result(verdict, **attrs)
        Result.new(verdict: verdict, grader: GRADER, grading_method: "exact", **attrs)
      end

      def invalid(code, detail: nil) = Result.invalid(code, grader: GRADER, detail: detail)

      # normalized_text. When the text the student was shown holds exactly one `___` (Frame.for_spec: the instance's stem, else
      # the item's) he may write the whole sentence (D-339, D-352). Two ways in, both graded by the item's own rules:
      #   1. the sentence is the frame with the gap filled by the key or an accepted value: right, whatever the case, the
      #      punctuation .,!?;: , the apostrophes and quotes (whole_sentence);
      #   2. what he wrote between the frame's words is graded exactly as if he had typed only that (the declared error
      #      values, accents and typos of the part: a wrong filler stays wrong, with its error code).
      # The result says so (observation full_sentence, answer_part) and its normalized is the normalized part. The blank typed as
      # it is, or a long answer that repeats the frame without fitting it, is refused (blank_copied, not_in_frame): never an attempt.
      # Two blanks or none: no frame, the answer is graded as typed. Lesson checks reach this through Lessons::Checks (their
      # prompt_it is the stem), so the rule is the same there.
      def normalized_text(spec, value)
        frame = value.is_a?(String) && !binary?(spec) ? Frame.for_spec(spec) : nil
        return Text.grade(spec, value) unless frame
        return invalid("blank_copied") if value.match?(Frame::BLANK)

        # An item whose key is itself a whole sentence keeps it: what the student typed is right as it stands.
        plain = Text.grade(spec, value)
        return plain if plain.verdict == "correct"

        part = frame.part(value)
        graded = part && Text.grade(spec, part)
        return graded.full_sentence(part) if graded&.verdict == "correct"

        filler = whole_sentence_filler(spec, frame, value)
        if filler
          matched = { kind: filler == spec.answer.to_s ? "key" : "accept", value: filler }
          return result("correct", normalized: Text.normalize(filler, case_sensitive: spec.case_sensitive), matched: matched).full_sentence(part || filler)
        end

        return graded.invalid? ? graded : graded.full_sentence(part) if graded
        return invalid("not_in_frame") if longer_than_a_blank_answer?(spec, frame, value)

        plain
      end

      # The key or accepted value whose frame, filled, is the answer (D-352); nil when none is. Compared with the grader's
      # normalisation, the case, the punctuation .,!?;: … and the quotes ignored, the spaces collapsed, the direction of an accent ignored.
      def whole_sentence_filler(spec, frame, value)
        given = sentence_key(value, spec)
        fillers = ([ spec.answer ] + spec.accept).map(&:to_s)
        filled = ->(filler) { sentence_key(frame.fill(filler), spec) }
        # the filler that is written exactly first, then (contractions en) the one the answer reads as
        exact = fillers.find { |filler| filled.(filler) == given }
        return exact if exact || spec.contractions != "en"

        errors = spec.error_values.map { |_code, v| sentence_key(frame.fill(v.to_s), spec) }
        fillers.find { |filler| Contractions.accepts?(filled.(filler), given, case_sensitive: spec.case_sensitive, except: errors) }
      end

      def sentence_key(text, spec)
        words = Text.normalize(text, case_sensitive: spec.case_sensitive).gsub(/[.,!?;:\u2026"]/, " ").gsub(/[[:space:]]+/, " ").strip
        Text.fold_direction(words)
      end

      def binary?(spec) = spec.profile.is_a?(Hash) && spec.profile["name"] == "binary"

      # More words than the longest accepted answer plus one, and at least two of the frame's own words in it.
      def longer_than_a_blank_answer?(spec, frame, value)
        longest = ([ spec.answer ] + spec.accept).map { |t| Frame.words(t).size }.max
        Frame.words(value).size > longest + 1 && frame.shared_words(value) >= 2
      end

      # The first error value of the catalogue that equals the answer (by +same+).
      def error_hit(spec, answer_value)
        spec.error_values.select { |_code, value| yield(value, answer_value) }.map(&:first).uniq
      end

      def verdict_for_errors(codes, **attrs)
        codes.any? ? result("typical_error", error_codes: codes, **attrs) : result("wrong", **attrs)
      end

      private

      def map_id(id, id_map)
        id = id.to_s
        id_map ? id_map.fetch(id, id) : id
      end

      def choice(spec, value, id_map)
        return invalid("empty") if value.to_s.strip.empty?
        return invalid("unparseable") unless value.is_a?(String)

        id = map_id(value.strip, id_map)
        options = Array(spec.display["options"]).map { |o| o["id"] }
        return invalid("unparseable") if options.any? && !options.include?(id)
        return result("correct", normalized: id) if id == spec.answer.to_s
        return result("correct", normalized: id) if same_text_up_to_accent_direction?(spec, id)

        verdict_for_errors(error_hit(spec, id) { |v, a| v.to_s == a }, normalized: id)
      end

      # An option whose text equals the key option's text up to the direction of an accent (perchè / perché) is
      # the key (D-296): the same folding and normalization as normalized_text.
      def same_text_up_to_accent_direction?(spec, id)
        texts = Array(spec.display["options"]).to_h { |o| [ o["id"].to_s, o["text"] ] }
        chosen = texts[id]
        key = texts[spec.answer.to_s]
        return false unless chosen.is_a?(String) && key.is_a?(String)

        fold = ->(t) { Text.fold_direction(Text.normalize(t, case_sensitive: spec.case_sensitive)) }
        fold.(chosen) == fold.(key)
      end

      def ordering(spec, value, id_map)
        return invalid("unparseable") unless value.is_a?(Array)
        return invalid("empty") if value.empty?

        order = value.map { |id| map_id(id, id_map) }
        key = Array(spec.answer).map(&:to_s)
        return invalid("unparseable") unless order.sort == key.sort

        # The number of pairs whose relative order differs from the key is stored
        # with the grading (inverted_pairs): a near miss is not a wild guess.
        position = key.each_with_index.to_h
        inverted = order.combination(2).count { |a, b| position[a] > position[b] }
        normalized = { "order" => order, "inverted_pairs" => inverted }.to_json
        return result("correct", normalized: normalized, matched: { kind: "key", value: key }) if inverted.zero?

        # An alternative right order of the instance (accept: a permutation of the key, e.g. a time phrase moved): right, with the same payload as the
        # key's, its inverted pairs counted against the order it matched, so 0.
        alternative = Array(spec.accept).find { |a| a.is_a?(Array) && a.map(&:to_s) == order }
        return result("correct", normalized: { "order" => order, "inverted_pairs" => 0 }.to_json, matched: { kind: "accept", value: order }) if alternative

        verdict_for_errors(error_hit(spec, order) { |v, a| Array(v).map(&:to_s) == a }, normalized: normalized)
      end

      def matching(spec, value, id_map)
        return invalid("unparseable") unless value.is_a?(Hash)

        key = spec.answer.to_h { |l, r| [ l.to_s, r.to_s ] }
        pairs = value.to_h { |l, r| [ map_id(l, id_map), r.to_s.empty? ? "" : map_id(r, id_map) ] }
        return invalid("unparseable") unless pairs.keys.sort == key.keys.sort
        # Nothing chosen at all is "empty"; some rows left blank is its own refusal, so the student is told to fill the rest.
        return invalid("empty") if pairs.values.all?(&:empty?)
        return invalid("incomplete_rows") if pairs.values.any?(&:empty?)

        rights = Array(spec.display["right"]).map { |o| o["id"] }
        return invalid("unparseable") if rights.any? && !(pairs.values - rights).empty?

        right_pairs = pairs.count { |l, r| key[l] == r }
        normalized = { "pairs" => pairs.sort.to_h, "correct_pairs" => right_pairs }.to_json
        return result("correct", normalized: normalized) if right_pairs == key.size

        hits = error_hit(spec, pairs) { |v, a| v.is_a?(Hash) && v.to_h { |l, r| [ l.to_s, r.to_s ] } == a }
        return verdict_for_errors(hits, normalized: normalized) if hits.any?
        return result("wrong", normalized: normalized) unless nearly_correct?(right_pairs, key, pairs, rights)

        # All pairs right but one (D-301): right, with the pair that was off kept for the notes.
        left = pairs.keys.find { |l| key[l] != pairs[l] }
        off = { "left" => left, "given" => pairs[left], "key" => key[left] }
        result("nearly_correct", normalized: { "pairs" => pairs.sort.to_h, "correct_pairs" => right_pairs, "off_pair" => off }.to_json)
      end

      # D-301 with the limits of D-314: a key of 3 pairs or more, exactly one pair off, a right column of 3 options or
      # more (the display's, else the right ids the key names) and an answer that does not give one option to every row.
      def nearly_correct?(right_pairs, key, pairs, rights)
        options = rights.any? ? rights.uniq.size : key.values.uniq.size
        key.size >= NEARLY_CORRECT_MIN_PAIRS && right_pairs == key.size - 1 &&
          options >= NEARLY_CORRECT_MIN_RIGHT && pairs.values.uniq.size > 1
      end
    end
  end
end
