module Practice
  # Reads of a stored practice item instance that the engine needs: its effective hints (the instance's
  # own, else the item's), its worked solution, its declared errors and whether it is hard to guess.
  module Instances
    module_function

    def body(instance) = JSON.parse(instance.item_revision.body_json)

    def component(instance) = body(instance)["component"].to_s

    # Effective hints (A2.4): the instance's own, else the item's.
    def hints(instance)
      own = instance.hints_json.present? ? JSON.parse(instance.hints_json) : nil
      Array(own.presence || body(instance)["hints_it"])
    end

    def errors(instance) = instance.errors_json.present? ? JSON.parse(instance.errors_json) : []

    def solution(instance) = instance.solution_json.present? ? JSON.parse(instance.solution_json) : {}

    # The item's error catalogue message for a code (nil when the item has none).
    def message_for(instance, code)
      Array(body(instance)["error_catalogue"]).find { |e| e["code"] == code }&.dig("message_it")
    end

    # What a stored attempt was worth: Grade = the outcome, the evidence key, the error codes and the
    # form violations of its latest grading. Nil when it is not a try (no grading, "Non lo so", ...).
    # near: nil | :typo | :one_word, set on a plain wrong text answer one typo or one word from an accepted one (outcome
    # near_miss). contested: the student sent the try to the teacher (a PracticeContest row; outcome :contested). resolution: the teacher
    # resolved the try (Practice::Resolutions, D-352); the outcome is then the verdict's, never contested.
    # pair_note: the line of a nearly_correct matching (D-301). rows: [right, total] of an item with rows (matching, ordering), nil for any other (D-363).
    Grade = Data.define(:outcome, :key, :codes, :violations, :pair_note, :near, :contested, :resolution, :rows)

    # contested_ids: the attempt ids that have a contest row, when the caller already read them (the loader reads
    # them once for all its serves); nil asks the database. resolution: the teacher's latest resolution of this try, if any
    # (a Practice::Resolutions::Resolution); the evidence comes from its verdict, the aided flag stays the try's own.
    def grade(attempt, spec, contested_ids: nil, resolution: nil)
      grading = attempt.latest_grading or return nil
      codes = JSON.parse(grading.error_codes_json || "[]")
      key = Grading::Evidence.key(verdict: grading.verdict, spec: spec, error_codes: codes, method: grading[:method])
      return nil unless Practice::Outcome.try?(key)

      rows = rows_count(spec, grading.normalized)
      resolved = resolution && resolved_grade(attempt, spec, resolution, rows)
      return resolved if resolved

      near = near_kind(spec, key, grading.normalized.presence || attempt.raw)
      contested = contested?(attempt, contested_ids)
      outcome = contested ? :contested : Practice::Outcome.call(evidence_key: key, aided: attempt.aided, near: near)
      Grade.new(outcome: outcome, key: key, codes: codes, violations: JSON.parse(grading.form_violations_json || "[]"),
                pair_note: key == "nearly_correct" ? Grading::PairNote.line(spec.display, grading.normalized) : nil,
                near: near, contested: contested, resolution: nil, rows: rows)
    end

    # How many rows of an item with rows the answer got right, as [right, total] (D-363): a matching's correct_pairs, an ordering's items in their
    # place; read from the grading's normalized, never which rows. nil for any other component.
    def rows_count(spec, normalized)
      data = JSON.parse(normalized.to_s)
      return nil unless data.is_a?(Hash)

      case spec.component
      when "matching"
        right = data["correct_pairs"]
        [ right, spec.answer.to_h.size ] if right.is_a?(Integer)
      when "ordering"
        key = Array(spec.answer).map(&:to_s)
        order = Array(data["order"]).map(&:to_s)
        [ key.each_index.count { |i| order[i] == key[i] }, key.size ] if order.size == key.size
      end
    rescue JSON::ParserError
      nil
    end

    # The try as the teacher resolved it: the evidence key of the verdict (with the item's declarations), the outcome of that key with the
    # try's own aided flag. nil when the verdict is not a practice try's (a resolution never removes a try).
    def resolved_grade(attempt, spec, resolution, rows)
      codes = resolution.error_code ? [ resolution.error_code ] : []
      key = Grading::Evidence.key(verdict: resolution.verdict, spec: spec, error_codes: codes, method: nil)
      return nil unless Practice::Outcome.try?(key)

      Grade.new(outcome: Practice::Outcome.call(evidence_key: key, aided: attempt.aided), key: key, codes: codes, violations: [], pair_note: nil,
                near: nil, contested: false, resolution: resolution, rows: rows)
    end

    # Practice::Outcome's `near` for one answer: only a `wrong` text answer, compared with the key and the accepted
    # forms of the instance (deterministic, so old tries are re-derived the same way).
    def near_kind(spec, key, text)
      return nil unless key == "wrong" && spec.component == "normalized_text"

      Grading::NearText.kind(text.to_s, ([ spec.answer ] + spec.accept).map(&:to_s), case_sensitive: false)
    end

    def contested?(attempt, contested_ids = nil)
      return false unless defined?(PracticeContest)

      contested_ids ? contested_ids.include?(attempt.id) : PracticeContest.exists?(practice_attempt_id: attempt.id)
    end

    def low_guess?(instance)
      component = component(instance)
      display = JSON.parse(instance.display_json)
      size = case component
      when "ordering" then Array(display["elements"]).size
      when "matching" then Array(display["left"]).size
      end
      Diagnosis::Rules::V1.low_guess?(component, size: size)
    end
  end
end
