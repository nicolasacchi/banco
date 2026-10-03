# frozen_string_literal: true

module Diagnosis
  # Runs the pure engine against a ScriptedStudent on a FakeClock, appending the
  # events the app would append. No database, no I/O: `banco diagnosis simulate`
  # and the property tests use this. Returns the trace (the event list) and the
  # derivation of the final log.
  module Simulator
    class Stuck < StandardError; end

    module_function

    MAX_STEPS = 5_000

    # resolve_pending: nil stops at a wait on pending answers (no grader retry and no
    # teacher in a simulation); a verdict ("wrong", "correct") plays the teacher
    # resolving each of them, after which the run can close.
    def run(plan, student, clock: FakeClock.new, resolve_pending: nil)
      events = []
      counts = Hash.new(0)
      push = lambda do |kind, **payload|
        events << { kind: kind, at: clock.now, seq: events.size + 1 }.merge(payload)
        events.last
      end

      MAX_STEPS.times do
        action = Engine.next_action(plan, events, clock)
        case action.type
        when :none then break
        when :start_sitting
          clock.advance_to(action.not_before) if clock.date(clock.now) < action.not_before
          push.call("sitting_started")
        when :serve then serve(plan, student, action, push, counts, clock)
        when :end_sitting then push.call("sitting_closed", reason: action.reason)
        when :close_run then push.call("run_closed", reason: action.reason)
        when :abandon_item then push.call("item_abandoned", serve: action.serve)
        when :wait
          # Only pending answers keep the run open (an open item cannot happen: the
          # simulated student answers at once).
          raise Stuck, "engine answered #{action.type} (#{action.reason}) in a simulation" unless action.reason == :pending_answers
          break unless resolve_pending

          resolve_all(plan, events, push, resolve_pending)
        else raise Stuck, "engine answered #{action.type} (#{action.reason}) in a simulation"
        end
      end
      result = Derivation.result(plan, events)
      unless events.last && events.last[:kind] == "run_closed" || result[:waiting_on]
        raise Stuck, "no end after #{MAX_STEPS} steps"
      end

      { events: events, trace: events.map { |e| trace_row(e) }, result: result }
    end

    def resolve_all(plan, events, push, verdict)
      state = Engine.fold(plan, events)
      state.serves.each do |serve|
        serve.answers.each do |skill, a|
          next if a.counted || !%i[pending ungraded].include?(a.evidence)

          if serve.instance.short_answer?
            push.call("confirm_grade", serve: serve.seq, passed: verdict == "correct")
          else
            push.call("resolve_attempt", serve: serve.seq, skill: skill, verdict: verdict)
          end
        end
      end
    end

    def serve(plan, student, action, push, counts, clock)
      inst = action.instance
      served = push.call("item_served", instance: inst.id, skill: action.skill, item: inst.item)
      counts[action.skill] += 1 unless inst.short_answer?
      ans = student.answer(skill: action.skill, n: counts[action.skill], instance: inst)
      clock.advance(ans[:seconds])
      push.call("answered", serve: served[:seq], **ans.except(:seconds))
      return unless inst.short_answer? && !student.confirm_short.nil?

      push.call("confirm_grade", serve: served[:seq], passed: student.confirm_short)
    end

    def trace_row(event)
      event.except(:at).merge(at: event[:at].iso8601).compact
    end
  end
end
