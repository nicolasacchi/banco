# frozen_string_literal: true

module Diagnosis
  # Engine.next_action(plan, events, clock): the one decision the engine makes.
  # Pure: it folds the log and answers; the caller (the web app, or Simulator)
  # appends the event that goes with the answer.
  #
  #   :serve          serve +instance+ (a Plan::Instance) for +skill+
  #   :abandon_item   the open item has been open (counted time: pause and hidden excluded) for ABANDON_GAP: log item_abandoned
  #   :wait           nothing to do now (reason :open_item, or :pending_answers when
  #                   the frontier is empty but an answer is still pending or ungraded)
  #   :start_sitting  a sitting may start on +not_before+ (a date)
  #   :end_sitting    close this sitting (+reason+), the run goes on in the next
  #   :close_run      close the run with +reason+ (an END_REASONS value)
  #   :none           the run is closed
  module Engine
    VERSION = "engine/1"

    Action = Data.define(:type, :reason, :skill, :instance, :not_before, :serve) do
      def to_h = { type: type, reason: reason, skill: skill, instance: instance&.id, not_before: not_before&.to_s, serve: serve }.compact
    end

    module_function

    def action(type, reason: nil, skill: nil, instance: nil, not_before: nil, serve: nil)
      Action.new(type: type, reason: reason, skill: skill, instance: instance, not_before: not_before, serve: serve)
    end

    def fold(plan, events) = Fold.call(plan, normalize(events))

    # Events with symbol keys and a seq (position, from 1) when missing.
    def normalize(events)
      events.each_with_index.map do |ev, i|
        e = ev.to_h.transform_keys(&:to_sym)
        e[:kind] = e[:kind].to_s
        e[:seq] ||= i + 1
        e
      end
    end

    def next_action(plan, events, clock)
      state = fold(plan, events)
      return action(:none, reason: state.end_reason) if state.closed

      if (open = state.open_serve)
        return action(:abandon_item, serve: open.seq) if state.open_counted_seconds(open, clock.now) >= Rules::V1::ABANDON_GAP_SECONDS

        return action(:wait, reason: :open_item, serve: open.seq)
      end

      sitting = state.open_sitting
      choice = choose(state, sitting ? remaining_seconds(state, sitting) : plan.sitting_seconds - Rules::V1::OPEN_RESERVE_MINUTES * 60)
      short_due = short_available?(state)

      if choice.nil? && !short_due
        # A run never closes while an answer of it is pending or ungraded: the
        # answer may still settle a skill (a retry, or the teacher), and a close
        # now would freeze the skill as pending. It waits; the close comes after
        # the resolution (or the teacher closes the run).
        return action(:wait, reason: :pending_answers) if pending_answers?(state)

        return action(:close_run, reason: "frontier_empty")
      end

      return start_sitting_action(state, clock) unless sitting

      counted = state.sitting_counted_seconds(sitting)
      return finish_sitting(state, "item_cap") if sitting.serve_seqs.size >= Rules::V1::MAX_ITEMS_PER_SITTING
      return finish_sitting(state, "time_budget") if counted >= plan.sitting_seconds

      reserve_start = plan.sitting_seconds - Rules::V1::OPEN_RESERVE_MINUTES * 60
      first_of_later_sitting = sitting.index > 1 && sitting.serve_seqs.empty?
      if short_due && (choice.nil? || choice == :no_fit || counted >= reserve_start || first_of_later_sitting)
        return action(:serve, reason: "short_answer", skill: plan.short_skill, instance: plan.short_instance)
      end
      return finish_sitting(state, "time_budget") if choice == :no_fit

      action(:serve, reason: state.outcome(choice[0]) ? "next_item" : "first_item", skill: choice[0], instance: choice[1])
    end

    def remaining_seconds(state, sitting)
      state.plan.sitting_seconds - state.sitting_counted_seconds(sitting) - Rules::V1::OPEN_RESERVE_MINUTES * 60
    end

    # True when some answer of this run is pending or ungraded and its skill is
    # not resolved: it can still change the states, so the run is not closed yet.
    def pending_answers?(state)
      state.serves.any? do |s|
        s.answers.any? { |skill, a| !a.counted && %i[pending ungraded].include?(a.evidence) && !state.resolved_state(skill) }
      end
    end

    # The run is open, nothing more can be served and only pending answers keep it
    # from closing (what next_action answers with :wait, :pending_answers).
    def waiting_on_pending?(state)
      return false if state.closed || state.open_serve

      choose(state, Float::INFINITY).nil? && !short_available?(state) && pending_answers?(state)
    end

    def short_available?(state)
      inst = state.plan.short_instance
      inst && state.short_serve.nil? && !state.plan.seen.include?(inst.fingerprint)
    end

    def start_sitting_action(state, clock)
      if state.sittings.size >= state.allowed_sittings
        reason = Rules::V1::END_REASONS.include?(state.last_close_reason) ? state.last_close_reason : "time_budget"
        return action(:close_run, reason: reason)
      end

      last = state.sittings.last
      not_before = last ? clock.date(last.closed_at || last.started_at) + 1 : clock.date(clock.now)
      action(:start_sitting, not_before: not_before)
    end

    # Budget or item cap reached with work left: the next sitting if one is
    # allowed (operator Q11), otherwise the run closes with the reason.
    def finish_sitting(state, reason)
      if state.sittings.size < state.allowed_sittings
        action(:end_sitting, reason: reason)
      else
        action(:close_run, reason: reason)
      end
    end

    # The next [skill, instance] to serve, :no_fit when only a testlet that does
    # not fit is left, or nil when the frontier has nothing servable. Skills that
    # cannot go on are marked stalled in +state+ (a local copy of the fold).
    def choose(state, remaining)
      no_fit = false
      state.frontier.each do |key|
        next unless servable?(state, key)

        need = state.outcome(key)&.need || :first
        if state.served_count[key] >= Rules::V1::MAX_SERVED_PER_SKILL
          state.stalled[key] = "item_cap"
          next
        end
        if Candidates.for(state, key, need).empty?
          state.stalled[key] = "no_unseen_items"
          next
        end
        fitting = Candidates.for(state, key, need, max_seconds: remaining)
        if fitting.empty?
          no_fit = true
          next
        end
        return [ key, fitting.first ]
      end
      no_fit ? :no_fit : nil
    end

    def servable?(state, key)
      plan = state.plan
      return false if state.resolved_state(key) || state.stalled.key?(key) || key == plan.short_skill

      d = plan.skill(key)
      return false unless d
      return false if state.below.include?(key) && state.origin[key] != :suspect
      return false if gated?(state, key)

      d.subject == plan.subject || plan.entry(key) ? true : false
    end

    # A starting skill whose same-subject prerequisite is to_recover with kind
    # learn (or is itself gated) is not served: not_assessed(prerequisite_to_recover).
    def gated?(state, key)
      return false unless state.origin[key] == :entry && state.served_count[key].zero?

      d = state.plan.skill(key)
      return false unless d

      d.parents.any? do |p|
        pd = state.plan.skill(p)
        next false unless pd && pd.subject == d.subject

        (state.outcome(p)&.to_recover? && pd.kind == "learn") || gated?(state, p)
      end
    end
  end
end
