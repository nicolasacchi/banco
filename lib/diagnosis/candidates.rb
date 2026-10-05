# frozen_string_literal: true

module Diagnosis
  # Which instances may be served next for a skill (B-02), by the kind of item the
  # sequence needs. Pure: reads the plan and what the State has served.
  module Candidates
    module_function

    # need: :first (low-guess unless the skill is choice-only), :second (another
    # item when the pool has one), :third (low-guess, unseen). Returns instances
    # in the seeded order of the plan. A testlet is left out when its expected
    # seconds do not fit in max_seconds (B-05).
    def for(state, skill, need, max_seconds: Float::INFINITY)
      plan = state.plan
      unseen = plan.instances_for(skill).reject do |i|
        state.served_fingerprints.include?(i.fingerprint) || plan.seen.include?(i.fingerprint) ||
          (i.testlet? && i.expected_seconds > max_seconds)
      end
      case need
      when :first
        low = unseen.select { |i| i.low_guess_for(skill) }
        plan.entry(skill)&.choice_only || low.empty? ? unseen : low
      when :second
        used = state.serves.select { |s| s.instance.skills.include?(skill) }.map { |s| s.instance.item }
        other = unseen.reject { |i| used.include?(i.item) }
        other.empty? ? unseen : other
      when :third
        unseen.select { |i| i.low_guess_for(skill) }
      else
        raise ArgumentError, "unknown need #{need.inspect}"
      end
    end
  end
end
