module Diagnosis
  # The list of subjects on the student's Diagnosi screen: for each, its state in
  # words (B-11), whether it can be started now, and which ones the screen
  # proposes. The rules (dependencies, the daily caps) are DailyPlan's; this reads
  # the runs of the student and hands DailyPlan its facts.
  class Availability
    Row = Data.define(:subject, :label_key, :label_args, :startable, :suggested, :done, :status, :run_id)

    def self.for(student, clock: Clock.new) = new(student, clock).rows

    def initialize(student, clock)
      @student = student
      @clock = clock
    end

    def rows
      facts = subjects.map { |s| fact(s) }
      today = @clock.date(@clock.now)
      states = DailyPlan.availability(facts.map(&:daily), today)
      slots = [ Rules::V1::DAILY_MAX_SUBJECTS - facts.count { |f| f.daily.sitting_dates.include?(today) }, 0 ].max
      by_key = facts.to_h { |f| [ f.daily.key, f ] }
      states.map do |key, availability|
        f = by_key.fetch(key)
        # A sitting that closed today leaves the rest of the subject for tomorrow.
        startable = availability[:state] == :to_do && f.daily.status != "completed" && !f.closed_today
        suggested = false
        if startable && (f.daily.status == "in_progress" || slots.positive?)
          suggested = true
          slots -= 1 unless f.daily.status == "in_progress"
        end
        label_key, args = label(f, availability, by_key)
        Row.new(subject: f.subject, label_key: label_key, label_args: args, startable: startable, suggested: suggested,
                done: f.daily.status == "completed", status: f.daily.status, run_id: f.run&.id)
      end
    end

    Fact = Data.define(:subject, :daily, :run, :checking, :closed_today)

    private

    def subjects
      Subject.order(:position).select { |s| Conductor.approved_blueprint(s) }
    end

    def fact(subject)
      depends = JSON.parse(Conductor.approved_blueprint(subject).body_json).fetch("depends_on_subjects", [])
      run = DiagnosisRun.where(student: @student, subject: subject).order(:sequence).last
      return Fact.new(subject, daily(subject, depends, "not_started"), nil, false, false) unless run
      return Fact.new(subject, daily(subject, depends, "to_redo"), run, false, false) if EventLoader.voided?(run)

      conductor = Conductor.new(run)
      state = conductor.state
      # A run held open for pending answers has nothing left to ask: for the list it is done.
      status = if state.closed || (!state.open_serve && conductor.holding?) then "completed"
      elsif state.open_sitting then "in_progress"
      elsif state.sittings.any? then "continue_next_day"
      else "not_started"
      end
      dates = state.sittings.map { |s| @clock.date(s.started_at) }
      seconds = state.sittings.group_by { |s| @clock.date(s.started_at) }.transform_values { |ss| ss.sum { |s| state.sitting_counted_seconds(s) } }
      daily = DailyPlan::Subject.new(key: subject.key, depends_on: depends, status: status,
                                     sittings_closed: status == "completed" ? [ state.sittings.count(&:closed_at), 1 ].max : state.sittings.count(&:closed_at), sitting_dates: dates,
                                     counted_seconds_by_date: seconds)
      checking = status == "completed" && Derivation.result(conductor.plan(reuse: false), conductor.events)[:skills].any? { |r| r[:state] == "pending" }
      last = state.sittings.last
      closed_today = status == "continue_next_day" && last&.closed_at && @clock.date(last.closed_at) == @clock.date(@clock.now)
      Fact.new(subject, daily, run, checking, closed_today ? true : false)
    end

    def daily(subject, depends, status)
      DailyPlan::Subject.new(key: subject.key, depends_on: depends, status: status, sittings_closed: 0, sitting_dates: [],
                             counted_seconds_by_date: {})
    end

    def label(fact, availability, by_key)
      case availability[:state]
      when :done then [ fact.checking ? "diagnosis.states.done_checking" : "diagnosis.states.done", {} ]
      when :after_dependency
        names = availability[:waiting_for].map { |k| by_key[k]&.subject&.name_it || k }
        [ "diagnosis.states.after_dependency", { subjects: names.to_sentence(two_words_connector: " e ", last_word_connector: " e ") } ]
      when :tomorrow then [ "diagnosis.states.tomorrow", {} ]
      when :continue_next_day then [ "diagnosis.states.continue_next_day", {} ]
      else
        key = { "in_progress" => "paused", "continue_next_day" => "continue_next_day", "to_redo" => "to_redo" }.fetch(fact.daily.status, "to_do")
        [ "diagnosis.states.#{key}", {} ]
      end
    end
  end
end
