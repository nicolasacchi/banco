# frozen_string_literal: true

module Validation
  # The grading round trip (A-06, A-01): what the grader says about the keys and the
  # error values of the instances the student will meet. The key must come back
  # correct, every error value must come back as a typical error with its own code,
  # two error values must not be the same answer, and random well-formed answers
  # must not be accepted.
  #
  # Grading expressions needs the Node worker: when it does not answer the
  # validation is not a pass or a fail but an error to retry (Unavailable).
  class Roundtrip
    Unavailable = Class.new(StandardError)

    def initialize(unit, subject:, findings:)
      @unit = unit
      @subject = subject
      @findings = findings
    end

    # instances: [{"display", "answer", "errors"}], label: finding field prefix.
    def call(instances, label:, tests: nil)
      instances.each_with_index do |inst, i|
        check_instance(inst, label, i)
      end
      random_answers(instances.first, label) if instances.any? && Rules.list(:roundtrip, :random_components).include?(@unit.component)
      check_tests(instances.first, tests, label) if tests && instances.any?
    rescue Grading::Expression::Unavailable => e
      raise Unavailable, e.message
    end

    private

    def grade(inst, raw)
      Grading.grade_spec(Units.spec_for(@unit, @subject, inst), raw)
    end

    def check_instance(inst, label, index)
      field = "#{label}/#{index}"
      key_raw, problem = Answers.raw_for(@unit.component, inst["answer"], form: @unit.forms)
      if problem
        @findings.add("E-GEN-SCHEMA", "#{field}/answer", problem, rule: "answer_shape")
        return
      end

      verdict = grade(inst, key_raw)
      unless verdict.verdict == "correct"
        @findings.add("E-ROUNDTRIP", "#{field}/answer", "the grader does not accept the key of the instance (#{verdict.verdict})", rule: "key", verdict: verdict.verdict)
      end
      normalized = {}
      Array(inst["errors"]).each_with_index do |e, j|
        raw, err = Answers.raw_for(@unit.component, e["value"], form: @unit.forms)
        if err
          @findings.add("E-GEN-SCHEMA", "#{field}/errors/#{j}", "error value: #{err}", rule: "error_value")
          next
        end
        result = grade(inst, raw)
        if result.verdict == "typical_error" && result.error_codes.include?(e["code"])
          other = normalized[result.normalized]
          if other && other != e["code"]
            @findings.add("E-ROUNDTRIP", "#{field}/errors/#{j}", "the error values of #{other} and #{e['code']} are the same answer", rule: "collision")
          end
          normalized[result.normalized] ||= e["code"]
        else
          @findings.add("E-ROUNDTRIP", "#{field}/errors/#{j}",
                        "the error value of #{e['code']} comes back from the grader as #{result.verdict}#{" (#{result.error_codes.join(', ')})" if result.error_codes.any?}",
                        rule: "error_value", code: e["code"], verdict: result.verdict)
        end
      end
    end

    # ---- E-ACCEPTS-RANDOM -----------------------------------------------------------

    def random_answers(inst, label)
      key_raw, problem = Answers.raw_for(@unit.component, inst["answer"], form: @unit.forms)
      return if problem

      rng = Random.new(Canonical.fingerprint(inst["display"]).to_i(16) % (2**31))
      key = key_value(inst["answer"])
      Rules.get(:roundtrip, :random_answers).times do
        candidate = random_candidate(rng)
        next if candidate.nil? || candidate[:value] == key || candidate[:value].to_s == key_raw.to_s

        if grade(inst, candidate[:raw]).verdict == "correct" && !equal_in_value?(inst, candidate[:raw])
          @findings.add("E-ACCEPTS-RANDOM", "#{label}/0/answer", "the grader accepted a random answer (#{candidate[:raw].inspect})", rule: "random")
          return
        end
      end
    end

    # 1x+4 and 1(x+4) are the answer x+4 written another way, not a wrong answer the grader let through:
    # grade against the key with no form and no declared errors, which compares values only (D-080).
    def equal_in_value?(inst, raw)
      return false unless @unit.component == "expression"

      Grading::Expression.grade(Units.spec_for(@unit, @subject, inst, "form" => [], "errors" => []), raw).verdict == "correct"
    end

    def key_value(answer)
      case @unit.component
      when "number", "fraction" then Answers.rational(answer.is_a?(Hash) ? { "n" => answer["n"], "d" => answer["d"] } : answer)
      when "expression" then Answers.squash(answer.is_a?(Hash) ? answer["latex"] : answer)
      end
    end

    def random_candidate(rng)
      case @unit.component
      when "number"
        value = Rational(rng.rand(-99_999..99_999), [ 1, 10, 100 ].sample(random: rng))
        { raw: Answers.decimal_string(value), value: value }
      when "fraction"
        n = rng.rand(-20..20)
        d = rng.rand(1..20)
        { raw: { "n" => n.to_s, "d" => d.to_s }, value: Rational(n, d) }
      when "expression"
        a = rng.rand(1..9)
        b = rng.rand(1..9)
        text = [ "#{a}x+#{b}", "#{a}x-#{b}", "x^2+#{a}", "#{a}x+#{b}y", "#{a}(x+#{b})", "x+#{a}" ].sample(random: rng)
        { raw: text, value: Answers.squash(text) }
      end
    end

    # ---- tests of the item --------------------------------------------------------------

    def check_tests(inst, tests, label)
      Array(tests["must_accept"]).each do |raw|
        verdict = grade(inst, raw).verdict
        @findings.add("E-ROUNDTRIP", "#{label}/tests/must_accept", "must_accept #{raw.inspect} comes back #{verdict}", rule: "must_accept") unless verdict == "correct"
      end
      Array(tests["must_reject"]).each do |raw|
        verdict = grade(inst, raw).verdict
        @findings.add("E-ROUNDTRIP", "#{label}/tests/must_reject", "must_reject #{raw.inspect} is accepted", rule: "must_reject") if verdict == "correct"
      end
      verdict = grade(inst, blank_raw).verdict
      @findings.add("E-ROUNDTRIP", "#{label}/tests/blank", "a blank answer comes back #{verdict}, not invalid", rule: "blank") unless verdict == "invalid"
    end

    def blank_raw
      case @unit.component
      when "ordering" then []
      when "matching" then {}
      when "fraction" then { "n" => "", "d" => "" }
      else ""
      end
    end
  end
end
