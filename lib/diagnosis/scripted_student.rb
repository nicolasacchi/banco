# frozen_string_literal: true

module Diagnosis
  # A student that answers from a script, for tests and for `banco diagnosis
  # simulate`. A script is a name (all-correct, all-wrong, mixed) or a hash:
  #
  #   {"default": {"verdict": "wrong"},
  #    "seconds": 45,
  #    "confirm_short": true,
  #    "rules": [{"skill": "math.x", "n": 1, "verdict": "typical_error", "error_code": "sign_slip", "seconds": 30}]}
  #
  # A rule matches on skill (optional), n (the nth item served for that skill,
  # optional) and instance (optional); the first match wins. Verdicts are the
  # grader's (see Rules::V1::EVIDENCE); the student never sees a key.
  class ScriptedStudent
    NAMED = {
      "all-correct" => { "default" => { "verdict" => "correct" } },
      "all-wrong" => { "default" => { "verdict" => "wrong" } },
      "mixed" => { "rules" => [ { "n" => 2, "verdict" => "wrong" }, { "n" => 4, "verdict" => "wrong" } ],
                   "default" => { "verdict" => "correct" } }
    }.freeze

    class UnknownScript < StandardError; end

    attr_reader :name

    def initialize(script, seconds: nil)
      @name = script.is_a?(String) ? script : "file"
      @script = script.is_a?(String) ? NAMED.fetch(script) { raise UnknownScript, "unknown script #{script.inspect}" } : script
      @seconds = seconds || @script["seconds"]
    end

    def confirm_short = @script["confirm_short"]

    # ctx: {skill:, n:, instance: Plan::Instance}. Returns {verdict:, error_code:,
    # seconds:, ...} with symbol keys.
    def answer(ctx)
      inst = ctx[:instance]
      return base(inst, "verdict" => "short_answer") if inst.short_answer?

      rule = (@script["rules"] || []).find { |r| match?(r, ctx) }
      spec = rule || @script["default"] || { "verdict" => "wrong" }
      base(inst, spec)
    end

    private

    def match?(rule, ctx)
      (rule["skill"].nil? || rule["skill"] == ctx[:skill]) &&
        (rule["n"].nil? || rule["n"] == ctx[:n]) &&
        (rule["instance"].nil? || rule["instance"] == ctx[:instance].id)
    end

    def base(inst, spec)
      { verdict: spec["verdict"], error_code: spec["error_code"], orthography_slip: spec["orthography_slip"],
        form: spec["form"], form_skill: spec["form_skill"], retry_state: spec["retry_state"],
        seconds: spec["seconds"] || @seconds || inst.expected_seconds }.compact
    end
  end
end
