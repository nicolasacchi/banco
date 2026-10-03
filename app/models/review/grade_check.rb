module Review
  # A grade proposal for a short answer against its rubric (B-06): every rubric point
  # exactly once, integer scores from 0 to the weight, a quote of 3 to 300
  # characters for every score above 0, and the quote an exact substring of the
  # student's text after normalization. The server computes the total.
  #
  # Normalization (not case or accent folding): NFC, curly quotes and apostrophes
  # straightened, whitespace collapsed, trim.
  module GradeCheck
    QUOTE_RANGE = (3..300)
    RATIONALE_MAX = 400
    Result = Struct.new(:error, :points, :total, :max_total, :threshold, :meets, keyword_init: true)
    Error = Struct.new(:code, :field, :message, :reason, keyword_init: true)

    module_function

    def normalize(text)
      text.to_s.unicode_normalize(:nfc)
          .tr("‘’‛′´`", "'").tr("“”„‟″", '"')
          .gsub(/[[:space:]]+/, " ").strip
    end

    def call(doc, rubric, student_text)
      return error("E-GRADE-POINT", "points", "send {points: [...], missing_it} with one entry per rubric point") unless doc.is_a?(Hash) && doc["points"].is_a?(Array)

      entries = doc["points"].map { |p| p.is_a?(Hash) ? canonical(p) : p }
      return error("E-GRADE-POINT", "points", "every entry of points is an object {point_id, score, quote, rationale_it}") unless entries.all?(Hash)

      weights = rubric["points"].to_h { |p| [ p["id"], p["weight"] ] }
      ids = entries.map { |p| p["point_id"] }
      unknown = ids - weights.keys
      return error("E-GRADE-POINT", "points", "unknown rubric point(s): #{unknown.map(&:to_s).first(5).join(', ')}; the rubric has #{weights.keys.join(', ')}") if unknown.any?

      dup = ids.tally.select { |_, n| n > 1 }.keys
      return error("E-GRADE-POINT", "points", "rubric point(s) given twice: #{dup.join(', ')}") if dup.any?

      missing = weights.keys - ids
      return error("E-GRADE-POINT", "points", "rubric point(s) missing: #{missing.join(', ')}; every point appears exactly once") if missing.any?

      text = normalize(student_text)
      entries.each_with_index do |p, i|
        weight = weights.fetch(p["point_id"])
        score = p["score"]
        unless score.is_a?(Integer) && score.between?(0, weight)
          return error("E-GRADE-POINT", "points/#{i}/score", "the score of #{p['point_id']} is an integer from 0 to #{weight}")
        end
        rationale = p["rationale_it"]
        unless rationale.is_a?(String) && !rationale.strip.empty? && rationale.size <= RATIONALE_MAX
          return error("E-GRADE-POINT", "points/#{i}/rationale_it", "rationale_it of #{p['point_id']} says in one or two plain sentences why (at most #{RATIONALE_MAX} characters)")
        end
        quote = p["quote"]
        if score.zero?
          return error("E-GRADE-QUOTE", "points/#{i}/quote", "a score of 0 has quote null") unless quote.nil?
        else
          unless quote.is_a?(String) && QUOTE_RANGE.cover?(quote.size)
            return error("E-GRADE-QUOTE", "points/#{i}/quote", "a score above 0 needs a quote of #{QUOTE_RANGE.min} to #{QUOTE_RANGE.max} characters")
          end
          unless text.include?(normalize(quote))
            return error("E-QUOTE-NOT-FOUND", "points/#{i}/quote", "the quote for #{p['point_id']} is not an exact substring of the student's text after normalization", "quote_not_in_submission")
          end
        end
      end
      missing_it = doc["missing_it"]
      return error("E-GRADE-POINT", "missing_it", "missing_it is a string") unless missing_it.nil? || missing_it.is_a?(String)

      total = entries.sum { |p| p["score"] }
      max = weights.values.sum
      threshold = (rubric["threshold"] || 0.6).to_f
      Result.new(points: entries.map { |p| p.slice("point_id", "score", "quote", "rationale_it") }, total: total, max_total: max,
                 threshold: threshold, meets: total.to_f / max >= threshold)
    end

    # The short names of the first draft of the brief are accepted too.
    def canonical(entry)
      entry = entry.dup
      entry["point_id"] = entry.delete("point") if entry.key?("point") && !entry.key?("point_id")
      entry["rationale_it"] = entry.delete("rationale") if entry.key?("rationale") && !entry.key?("rationale_it")
      entry["quote"] = nil unless entry.key?("quote")
      entry
    end

    def error(code, field, message, reason = nil)
      Result.new(error: Error.new(code: code, field: field, message: message, reason: reason))
    end
  end
end
