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
      # One passage per run: once an instance of a testlet is served, no other
      # instance of it is (two serves would be correlated evidence, D-099).
      passages = state.serves.map { |s| s.instance.item if s.instance.testlet? }.compact
      held = testlet_pending?(state, skill)
      fresh = plan.instances_for(skill).reject do |i|
        state.served_fingerprints.include?(i.fingerprint) || plan.seen.include?(i.fingerprint) ||
          (i.testlet? && (held || passages.include?(i.item)))
      end
      unseen = fresh.reject { |i| i.testlet? && i.expected_seconds > max_seconds }
      too_long = fresh.size != unseen.size
      case need
      when :first
        low = unseen.select { |i| i.low_guess_for(skill) }
        plan.entry(skill)&.choice_only || low.empty? ? unseen : low
      when :second
        used = state.serves.select { |s| s.instance.skills.include?(skill) }.map { |s| s.instance.item }
        other = unseen.reject { |i| used.include?(i.item) }
        # The other item is a testlet that does not fit now: nothing, so the engine
        # reports :no_fit and the passage opens the next sitting, instead of a
        # repeat of the item already used (D-131).
        return [] if other.empty? && too_long && fresh.any? { |i| i.testlet? && !used.include?(i.item) }

        other.empty? ? unseen : other
      when :third
        unseen.select { |i| i.low_guess_for(skill) }
      else
        raise ArgumentError, "unknown need #{need.inspect}"
      end
    end

    # A testlet answer of this skill is pending or ungraded (a mostly right one is
    # undetermined, D-047): no further testlet of the skill is served until the
    # teacher or a retry settles it, so a 5-minute passage is not repeated up to
    # the serve cap (D-130).
    def testlet_pending?(state, skill)
      state.serves.any? do |s|
        s.instance.testlet? && (a = s.answers[skill]) && !a.counted && %i[pending ungraded].include?(a.evidence)
      end
    end
  end
end
