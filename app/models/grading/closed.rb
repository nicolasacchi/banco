module Grading
  # Grading::Closed (A-01): the components whose answer can be settled with
  # certainty in Ruby. Choice, ordering and matching compare ids; number and
  # fraction compare exact rationals; normalized_text compares normalized strings.
  # No I/O, no database, no clock.
  module Closed
    GRADER = "closed".freeze

    class << self
      def grade(spec, value, id_map: nil)
        case spec.component
        when "choice" then choice(spec, value, id_map)
        when "ordering" then ordering(spec, value, id_map)
        when "matching" then matching(spec, value, id_map)
        when "number" then Numbers.grade(spec, value)
        when "fraction" then Fractions.grade(spec, value)
        when "normalized_text" then Text.grade(spec, value)
        else raise ArgumentError, "Grading::Closed does not grade #{spec.component.inspect}"
        end
      end

      def result(verdict, **attrs)
        Result.new(verdict: verdict, grader: GRADER, grading_method: "exact", **attrs)
      end

      def invalid(code) = Result.invalid(code, grader: GRADER)

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

        verdict_for_errors(error_hit(spec, id) { |v, a| v.to_s == a }, normalized: id)
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
        return result("correct", normalized: normalized) if inverted.zero?

        verdict_for_errors(error_hit(spec, order) { |v, a| Array(v).map(&:to_s) == a }, normalized: normalized)
      end

      def matching(spec, value, id_map)
        return invalid("unparseable") unless value.is_a?(Hash)

        key = spec.answer.to_h { |l, r| [ l.to_s, r.to_s ] }
        pairs = value.to_h { |l, r| [ map_id(l, id_map), r.to_s.empty? ? "" : map_id(r, id_map) ] }
        return invalid("unparseable") unless pairs.keys.sort == key.keys.sort
        return invalid("empty") if pairs.values.any?(&:empty?)

        rights = Array(spec.display["right"]).map { |o| o["id"] }
        return invalid("unparseable") if rights.any? && !(pairs.values - rights).empty?

        right_pairs = pairs.count { |l, r| key[l] == r }
        normalized = { "pairs" => pairs.sort.to_h, "correct_pairs" => right_pairs }.to_json
        return result("correct", normalized: normalized) if right_pairs == key.size

        hits = error_hit(spec, pairs) { |v, a| v.is_a?(Hash) && v.to_h { |l, r| [ l.to_s, r.to_s ] } == a }
        verdict_for_errors(hits, normalized: normalized)
      end
    end
  end
end
