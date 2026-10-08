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
    Grade = Data.define(:outcome, :key, :codes, :violations)

    def grade(attempt, spec)
      grading = attempt.latest_grading or return nil
      codes = JSON.parse(grading.error_codes_json || "[]")
      key = Grading::Evidence.key(verdict: grading.verdict, spec: spec, error_codes: codes, method: grading[:method])
      return nil unless Practice::Outcome.try?(key)

      Grade.new(outcome: Practice::Outcome.call(evidence_key: key, aided: attempt.aided), key: key, codes: codes,
                violations: JSON.parse(grading.form_violations_json || "[]"))
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
