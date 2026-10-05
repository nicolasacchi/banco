module Grading
  # A testlet is one served unit with five sub items, and one attempt (the unique
  # index on attempts.served_event_id). Its raw answer is a JSON object
  # {sub item id => the raw answer of that sub item}, each in the encoding of its
  # own component (decision D-030); id_map is {sub item id => {shown id => id}}.
  #
  # Every sub item is graded by the grader of its component. The unit is then
  # settled only when that is certain (decision D-047): all correct is correct, all
  # wrong or "Non lo so" is wrong (dont_know when every one is), and any mixture
  # goes to the teacher as undetermined, which counts neither way. An invalid sub
  # answer makes the whole answer invalid, so nothing is recorded half done.
  module Testlet
    GRADER = "closed".freeze

    module_function

    def grade(spec, value, source: "text", id_map: nil)
      return Result.invalid("unparseable", grader: GRADER) unless value.is_a?(Hash)

      results = []
      spec.sub_specs.each do |id, sub|
        return Result.invalid("empty", grader: GRADER) unless value.key?(id)

        results << Grading.grade_spec(sub, value[id], source: source, id_map: id_map&.dig(id))
      end
      invalid = results.find(&:invalid?)
      return invalid if invalid

      verdicts = results.map(&:verdict)
      unit = unit_verdict(verdicts)
      # A unit that is wrong because of typical errors carries their codes (D-112), so the
      # engine can follow their implicates; a mixture stays undetermined with no codes.
      codes = unit == "wrong" ? results.flat_map(&:error_codes).uniq : []
      Result.new(verdict: codes.any? ? "typical_error" : unit, grader: GRADER, grading_method: "exact",
                 error_codes: codes,
                 normalized: { "sub_verdicts" => spec.sub_specs.keys.zip(verdicts).to_h }.to_json)
    end

    def unit_verdict(verdicts)
      if verdicts.all?("correct") then "correct"
      elsif verdicts.all?("dont_know") then "dont_know"
      elsif (verdicts & %w[correct undetermined near_miss wrong_form]).empty? then "wrong"
      else "undetermined"
      end
    end
  end
end
