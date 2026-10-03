# frozen_string_literal: true

module Diagnosis
  # The per-skill rule (B-02) on the counted outcomes of one skill, in the order
  # they became certain. Pure: no clock, no pool.
  #
  #   item 1 D                  -> to_recover(dont_know)
  #   C C                       -> demonstrated(two_of_two | two_of_two_choice)
  #   W W (a later D is a W)    -> to_recover(two_wrong)
  #   one C, one W              -> a third low-guess item:
  #                                C with a low-guess C among them -> two_of_three
  #                                otherwise                       -> to_recover(mixed)
  #
  # Pending and ungraded answers are not outcomes: they never reach this class.
  class SkillOutcome
    # One counted outcome. evidence is :C, :W or :D; code is the typical-error
    # code of a W, or nil for an unclassified W or a D.
    Outcome = Data.define(:evidence, :low_guess, :choice, :code, :serve)

    attr_reader :skill, :outcomes, :state, :reason

    def initialize(skill)
      @skill = skill
      @outcomes = []
      @state = nil
      @reason = nil
    end

    def resolved? = !@state.nil?
    def demonstrated? = @state == "demonstrated"
    def to_recover? = @state == "to_recover"

    # Add a counted outcome. Outcomes after resolution are ignored (they stay in
    # the log). Returns true when this outcome resolved the skill.
    def record(outcome)
      return false if resolved?

      @outcomes << outcome
      @state, @reason = self.class.resolve(@outcomes)
      resolved?
    end

    # What the next item must be: :first, :second or :third (low-guess, unseen).
    def need
      case @outcomes.size
      when 0 then :first
      when 1 then :second
      else :third
      end
    end

    # The third item could not be served: a mixed pair ends as to_recover(mixed).
    def resolve_mixed!
      return false if resolved? || @outcomes.size != 2

      @state = "to_recover"
      @reason = "mixed"
      true
    end

    # Typical-error codes seen on W outcomes, in order.
    def error_codes = @outcomes.filter_map { |o| o.code if o.evidence == :W }

    # True when some W had no catalogue code, or the student said "I do not know".
    def unclassified?(known_codes)
      @outcomes.any? do |o|
        o.evidence == :D || (o.evidence == :W && (o.code.nil? || !known_codes.include?(o.code)))
      end
    end

    class << self
      # Pure rule on a list of Outcome. Returns [state, reason] or nil when more
      # evidence is needed.
      def resolve(outcomes)
        first = outcomes[0]
        return nil unless first
        return [ "to_recover", "dont_know" ] if first.evidence == :D
        return nil if outcomes.size < 2

        second = outcomes[1]
        a = first.evidence
        b = second.evidence == :D ? :W : second.evidence
        if a == :C && b == :C
          return [ "demonstrated", first.choice && second.choice ? "two_of_two_choice" : "two_of_two" ]
        end
        return [ "to_recover", "two_wrong" ] if a == :W && b == :W
        return nil if outcomes.size < 3

        third = outcomes[2]
        credits = outcomes.first(3).select { |o| o.evidence == :C }
        if third.evidence == :C && credits.any?(&:low_guess)
          [ "demonstrated", "two_of_three" ]
        else
          [ "to_recover", "mixed" ]
        end
      end
    end
  end
end
