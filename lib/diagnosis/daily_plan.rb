# frozen_string_literal: true

require "set"

module Diagnosis
  # Which subjects the student may start today (B-12 and the operator's days
  # decision): a subject waits for the first sitting of each dependency to be
  # closed, and a day holds at most DAILY_MAX_SUBJECTS subjects and
  # DAILY_MAX_MINUTES counted minutes, in dependency order with mathematics first.
  # Pure; the caller supplies the facts.
  module DailyPlan
    # B-12 recommended order (a stable tie-break, not a rule).
    RECOMMENDED_ORDER = %w[math english italian computer_science business chemistry
                           history law_economics spanish biology geography].freeze

    Subject = Data.define(:key, :depends_on, :status, :sittings_closed, :sitting_dates, :counted_seconds_by_date)

    module_function

    # status: not_started | in_progress | continue_next_day | completed | to_redo
    # Returns {key => {state:, waiting_for:}} with state one of
    #   :done :to_do :after_dependency :tomorrow :continue_next_day
    def availability(subjects, today)
      by_key = subjects.to_h { |s| [ s.key, s ] }
      used_subjects = Set.new
      minutes_today = 0
      subjects.each do |s|
        secs = s.counted_seconds_by_date.fetch(today, 0)
        used_subjects << s.key if secs.positive? || s.sitting_dates.include?(today)
        minutes_today += secs / 60.0
      end

      ordered(subjects).to_h do |s|
        [ s.key, state_of(s, by_key, today, used_subjects, minutes_today) ]
      end
    end

    def state_of(subject, by_key, today, used_subjects, minutes_today)
      return { state: :done } if subject.status == "completed"

      missing = subject.depends_on.reject { |d| by_key[d] && by_key[d].sittings_closed.positive? }
      return { state: :after_dependency, waiting_for: missing } if missing.any?

      active_today = used_subjects.include?(subject.key)
      return { state: :continue_next_day } if active_today && subject.status == "continue_next_day"
      return { state: :to_do } if active_today # a sitting in progress today goes on

      full = used_subjects.size >= Rules::V1::DAILY_MAX_SUBJECTS || minutes_today >= Rules::V1::DAILY_MAX_MINUTES
      full ? { state: :tomorrow } : { state: :to_do }
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
