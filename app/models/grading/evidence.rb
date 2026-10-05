module Grading
  # From a grading to what it is worth to the engine (X-03, operator G and Q10).
  # A pure function of the verdict and of what the item declares; the table itself
  # is Diagnosis::Rules::V1::EVIDENCE, so a change of defaults (NEAR_MISS,
  # WRONG_FORM_DECLARED, ORTHOGRAPHY_SLIP) bumps the rules version in one place.
  #
  #   Grading::Evidence.call(verdict: "wrong_form", spec: spec)  # => :C or :pending ...
  #
  # Values: :C credit, :W wrong, :D "I do not know", :pending (counts neither way),
  # :ungraded (not an outcome yet), :none (not an attempt).
  module Evidence
    V1 = Diagnosis::Rules::V1

    module_function

    def call(verdict:, spec:, error_codes: [], method: nil, prerequisites: nil)
      V1::EVIDENCE.fetch(key(verdict: verdict, spec: spec, error_codes: error_codes, method: method,
                             prerequisites: prerequisites))
    end

    # The EVIDENCE key: the verdict, refined by the item's declarations.
    # prerequisites: the skill keys inside the item skill's prerequisite closure
    # (nil when the caller does not know the graph: the declaration is trusted).
    def key(verdict:, spec:, error_codes: [], method: nil, prerequisites: nil)
      # A result that touched floating point is uncertain whatever it says.
      return "float_method" if method == "float" && !%w[invalid dont_know short_answer].include?(verdict)

      V1.evidence_key(verdict, orthography_slip: orthography_slip?(verdict, error_codes, spec),
                               form: form_context(verdict, spec, prerequisites))
    end

    # The accent or apostrophe code of an item that does not measure accents
    # (accent_policy flag): credit on the item's skill (ORTHOGRAPHY_SLIP). With
    # accent_policy strict the item measures them and the slip is just wrong.
    def orthography_slip?(verdict, error_codes, spec)
      verdict == "typical_error" && spec.accent_policy == "flag" &&
        error_codes.any? && (error_codes - V1::ORTHOGRAPHY_ALLOWLIST).empty?
    end

    # :skill when the form is the item's own skill (reduce, factor, expand),
    # :declared when another skill owns it and the item names it inside the
    # prerequisite closure, :undeclared otherwise.
    def form_context(verdict, spec, prerequisites)
      return nil unless verdict == "wrong_form"
      return :skill if spec.form_skill.blank? || spec.form_skill == spec.skill
      return :declared if prerequisites.nil? || prerequisites.include?(spec.form_skill)

      :undeclared
    end

    # Extra observations that go with a credit (V1::OBSERVATIONS), each with the
    # skill it is about when the item names it.
    def observations(verdict:, spec:, error_codes: [], method: nil, prerequisites: nil)
      k = key(verdict: verdict, spec: spec, error_codes: error_codes, method: method, prerequisites: prerequisites)
      return [] unless V1::EVIDENCE.fetch(k) == :C && V1::OBSERVATIONS.key?(k)

      [ { kind: V1::OBSERVATIONS.fetch(k), skill: observation_skill(k, spec, error_codes) } ]
    end

    def observation_skill(key, spec, error_codes)
      case key
      when "wrong_form_declared" then spec.form_skill
      when "orthography_slip" then error_codes.filter_map { |c| V1::ORTHOGRAPHY_SKILLS[c] }.first
      end
    end

    # The evidence of a stored grading row (nil grading: nothing graded yet).
    def for_grading(grading, spec, prerequisites: nil)
      return :ungraded if grading.nil?

      call(verdict: grading.verdict, spec: spec, error_codes: JSON.parse(grading.error_codes_json || "[]"),
           method: grading[:method], prerequisites: prerequisites)
    end
  end
end
