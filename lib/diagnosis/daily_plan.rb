# frozen_string_literal: true

module Diagnosis
  # Which subjects the student may start today (B-12): a subject waits for the
  # first sitting of each dependency to be closed; nothing else limits a day (D-294
  # removed the daily caps), the order is dependency order with mathematics first.
  # Pure; the caller supplies the facts.
  module DailyPlan
    # B-12 recommended order (a stable tie-break, not a rule).
    RECOMMENDED_ORDER = %w[math english italian computer_science business chemistry
                           history law_economics spanish biology geography].freeze

    Subject = Data.define(:key, :depends_on, :status, :sittings_closed, :sitting_dates, :counted_seconds_by_date)

    module_function

    # status: not_started | in_progress | continue_next_day | completed | to_redo
    # Returns {key => {state:, waiting_for:}} with state one of
    #   :done :to_do :after_dependency :continue_next_day
    def availability(subjects, today)
      by_key = subjects.to_h { |s| [ s.key, s ] }
      ordered(subjects).to_h { |s| [ s.key, state_of(s, by_key, today) ] }
    end

    def state_of(subject, by_key, today)
      return { state: :done } if subject.status == "completed"

      missing = subject.depends_on.reject { |d| by_key[d] && by_key[d].sittings_closed.positive? }
      return { state: :after_dependency, waiting_for: missing } if missing.any?

      active_today = subject.sitting_dates.include?(today)
      return { state: :continue_next_day } if active_today && subject.status == "continue_next_day"

      { state: :to_do }
    end

    # Subjects in dependency order, ties broken by RECOMMENDED_ORDER.
    def ordered(subjects)
      rank = ->(s) { RECOMMENDED_ORDER.index(s.key) || RECOMMENDED_ORDER.size }
      by_key = subjects.to_h { |s| [ s.key, s ] }
      out = []
      pending = subjects.sort_by(&rank)
      until pending.empty?
        ready = pending.find { |s| s.depends_on.all? { |d| !by_key.key?(d) || out.include?(by_key[d]) } } || pending.first
        out << ready
        pending.delete(ready)
      end
      out
    end
  end
end
