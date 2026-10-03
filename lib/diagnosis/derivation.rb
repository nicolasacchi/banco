# frozen_string_literal: true

module Diagnosis
  # Derivation.result: the states of every skill of a run (B-04) and the run's
  # time account, derived by folding the log from the beginning. The log is never
  # edited, so a replay gives the same answer. Pure.
  module Derivation
    module_function

    # voided: the run was cancelled by the teacher (a void_diagnosis_run row).
    def result(plan, events, voided: false)
      state = Engine.fold(plan, events)
      Engine.choose(state, Float::INFINITY) # marks the skills that cannot go on
      keys = report_keys(plan, state)
      skills = keys.map { |k| skill_row(plan, state, k, voided) }
      {
        rules_version: Rules::V1::RULES_VERSION,
        engine_version: Engine::VERSION,
        subject: plan.subject,
        closed: state.closed,
        end_reason: state.end_reason,
        waiting_on: Engine.waiting_on_pending?(state) ? "pending_answers" : nil,
        served: state.serves.size,
        counted_seconds: state.counted_seconds_total,
        sittings: state.sittings.map { |s| sitting_row(state, s) },
        skills: skills,
        observations: state.observations,
        suspects: state.suspect_log,
        checks: skills.select { |r| r[:reason] == "cross_subject_unavailable" }.map { |r| { skill: r[:skill], check: "cross_subject_unavailable" } }
      }
    end

    # Just the state of each skill: {skill => [state, reason]}.
    def states(plan, events, voided: false)
      result(plan, events, voided: voided)[:skills].to_h { |r| [ r[:skill], [ r[:state], r[:reason] ] ] }
    end

    def report_keys(plan, state)
      keys = plan.skills.keys + plan.entries.map(&:skill) + state.visited.to_a + state.outcomes.keys
      keys << plan.short_skill if plan.short_skill
      keys.uniq
    end

    def sitting_row(state, sitting)
      { index: sitting.index, started_at: sitting.started_at&.iso8601, closed_at: sitting.closed_at&.iso8601,
        close_reason: sitting.close_reason, counted_seconds: state.sitting_counted_seconds(sitting),
        served: sitting.serve_seqs.size, condition: "unsupervised" }
    end

    def skill_row(plan, state, key, voided)
      d = plan.skill(key)
      st, reason, source = classify(plan, state, key, voided)
      outcome = state.outcome(key)
      {
        skill: key, subject: d&.subject || key.split(".").first, scope: d&.scope, kind: d&.kind,
        guest: plan.entry(key)&.guest_of,
        state: st, reason: reason, source: source,
        evidence: (outcome&.outcomes || []).first(3).map { |o| o.evidence.to_s },
        error_codes: outcome ? outcome.error_codes.uniq : [],
        unclassified: outcome ? outcome.unclassified?(d&.errors&.keys || []) : false,
        served: state.served_count[key]
      }
    end

    # [state, reason, source]; state nil means "still being asked" (run open).
    def classify(plan, state, key, voided)
      return [ "not_assessed", "voided", nil ] if voided

      resolved = state.resolved_state(key)
      return resolved if resolved

      pending = pending_reason(state, key)
      can_go_on = !state.closed && !state.stalled.key?(key) && key != plan.short_skill
      return [ "pending", pending, "run" ] if pending && !can_go_on

      d = plan.skill(key)
      foreign = !(d ? d.subject == plan.subject : key.start_with?("#{plan.subject}.")) && !plan.entry(key)
      return [ "not_assessed", "cross_subject_unavailable", nil ] if foreign
      return [ "not_assessed", "prerequisite_to_recover", nil ] if d && Engine.gated?(state, key)
      return [ "not_assessed", "below_demonstrated", nil ] if state.below.include?(key) && state.origin[key] != :suspect
      return [ "not_assessed", state.stalled[key], nil ] if state.stalled[key]

      unresolved(plan, state, key)
    end

    def unresolved(plan, state, key)
      return [ "not_assessed", "not_started", nil ] if !state.closed && state.sittings.empty?

      queued = state.frontier.include?(key) || state.served_count[key].positive?
      if state.closed
        return [ "not_assessed", end_reason_to_skill_reason(state, key), nil ] if queued || key == plan.short_skill

        [ "not_assessed", "not_needed", nil ]
      elsif queued
        [ nil, nil, nil ]
      else
        [ "not_assessed", plan.skill(key) || plan.entry(key) ? "not_started" : "not_needed", nil ]
      end
    end

    def end_reason_to_skill_reason(state, key)
      case state.end_reason
      when "time_budget" then "time_budget"
      when "item_cap" then "item_cap"
      when "teacher_close" then state.served_count[key].positive? ? "time_budget" : "not_started"
      else key == state.plan.short_skill && state.plan.seen.include?(state.plan.short_instance.fingerprint) ? "no_unseen_items" : "not_needed"
      end
    end

    # Reason of the pending state of a skill, from its uncounted answers; the
    # ones that need the teacher come before a grader that may still answer.
    def pending_reason(state, key)
      if key == state.plan.short_skill
        return state.short_serve&.answered_at ? "grade_unconfirmed" : nil
      end

      reasons = state.serves.flat_map do |s|
        a = s.answers[key]
        a && !a.counted && %i[pending ungraded].include?(a.evidence) ? [ a.pending_reason ] : []
      end
      %w[grade_unconfirmed verdict_pending grader_unavailable].find { |r| reasons.include?(r) }
    end
  end
end
