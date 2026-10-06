# frozen_string_literal: true

module Diagnosis
  # The fold: plan + list of log events -> State. Pure and deterministic; nothing
  # here touches a database, the clock or a random source.
  #
  # Event kinds (hashes with symbol keys; :kind, :at and :seq always present):
  #   sitting_started, sitting_closed{reason}, run_closed{reason}
  #   item_served{instance}                       seq of this event is the serve id
  #   answered{serve, skill?, verdict, error_code?, orthography_slip?, form?,
  #            form_skill?, orthography_skill?, retry_state?}
  #   grading{...}                                a later grading (retry), same keys
  #   resolve_attempt{serve, skill?, verdict, ...}  teacher resolves one answer
  #   confirm_grade{serve, passed}                 teacher confirms the short answer
  #   item_abandoned{serve}, paused, resumed, hidden, visible
  #   extend_diagnosis_run, close_diagnosis_run
  # Other kinds are ignored.
  class Fold
    ANSWER_KINDS = %w[answered grading].freeze

    def self.call(plan, events) = new(plan, events).call

    def initialize(plan, events)
      @plan = plan
      @events = events
      @state = State.new(plan)
    end

    def call
      prepare
      @events.each_with_index { |ev, idx| apply(ev, idx) }
      @state
    end

    private

    # Index of the first grader event of each (serve, skill) that carries a
    # certain verdict, and the last teacher resolution of each. A resolution of
    # an answer that already counted is applied in place at the original
    # position, as if the grader had said it.
    def prepare
      @first_certain = {}
      @teacher = {}
      # The skill of a serve is known only once its event is folded; prepare
      # runs first, so read it from the plan.
      @serve_skill = @events.select { |e| e[:kind] == "item_served" }
                            .to_h { |e| [ e[:seq], @plan.pool.fetch(e[:instance]) { raise Plan::Invalid, "served instance #{e[:instance].inspect} is not in the plan" }.skill ] }
      @events.each_with_index do |ev, idx|
        key = answer_key(ev)
        next unless key

        case ev[:kind]
        when "resolve_attempt" then @teacher[key] = ev
        when *ANSWER_KINDS
          @first_certain[key] ||= idx if certain?(evidence_of(ev))
        end
      end
      @plan.entries.each do |e|
        @state.origin[e.skill] = :entry
        @state.visited << e.skill
      end
      @state.frontier.concat(@plan.entries.map(&:skill).uniq)
    end

    def answer_key(ev)
      return nil unless ev[:serve]

      [ ev[:serve], ev[:skill] || @serve_skill[ev[:serve]] ]
    end

    def evidence_of(ev)
      return :pending if ev[:method] == "float" && !%w[invalid dont_know short_answer].include?(ev[:verdict].to_s)

      Rules::V1.evidence(ev[:verdict].to_s, orthography_slip: ev[:orthography_slip] ? true : false, form: ev[:form]&.to_sym)
    end

    def certain?(evidence) = %i[C W D].include?(evidence)

    def apply(ev, idx)
      case ev[:kind]
      when "sitting_started" then (close_open_intervals(ev[:at]); start_sitting(ev[:at]))
      when "sitting_closed" then close_sitting(ev[:at], ev[:reason])
      when "run_closed" then close_run(ev[:at], ev[:reason].to_s)
      when "close_diagnosis_run" then close_run(ev[:at], "teacher_close")
      when "extend_diagnosis_run" then extend_run
      when "item_served" then (close_open_intervals(ev[:at]); apply_serve(ev))
      when *ANSWER_KINDS, "resolve_attempt" then apply_answer(ev, idx)
      when "confirm_grade" then apply_confirm(ev)
      when "item_abandoned" then apply_abandon(ev)
      when "paused" then @state.pauses << [ ev[:at], nil ]
      when "resumed" then close_interval(@state.pauses, ev[:at])
      when "hidden" then @state.hiddens << [ ev[:at], nil ]
      when "visible" then close_interval(@state.hiddens, ev[:at])
      end
      settle
    end

    # A page that loads (a sitting starts, an item is served) is visible and running:
    # a hidden or paused interval still open then (the tab was closed or the page
    # reloaded, no "visible" or "resumed" was ever sent) ends here, and never
    # swallows the time of the items that follow.
    def close_open_intervals(at)
      close_interval(@state.pauses, at)
      close_interval(@state.hiddens, at)
    end

    def close_interval(list, at)
      i = list.rindex { |_from, to| to.nil? }
      list[i] = [ list[i][0], at ] if i
    end

    # ---- sittings -----------------------------------------------------------

    def start_sitting(at)
      @state.sittings << State::Sitting.new(index: @state.sittings.size + 1, started_at: at, serve_seqs: [])
    end

    def close_sitting(at, reason)
      s = @state.open_sitting
      return unless s

      s.closed_at = at
      s.close_reason = reason.to_s
      @state.last_close_reason = reason.to_s
    end

    def close_run(at, reason)
      close_sitting(at, reason)
      @state.closed = true
      @state.end_reason = reason
    end

    # An extra sitting. After a run closed on time or item cap it reopens the run.
    def extend_run
      @state.extends += 1
      return unless @state.closed && %w[time_budget item_cap].include?(@state.end_reason)

      @state.closed = false
      @state.end_reason = nil
    end

    # ---- serving ------------------------------------------------------------

    def apply_serve(ev)
      inst = @plan.pool.fetch(ev[:instance]) { raise Plan::Invalid, "served instance #{ev[:instance].inspect} is not in the plan" }
      start_sitting(ev[:at]) unless @state.open_sitting
      sitting = @state.open_sitting
      serve = State::Serve.new(seq: ev[:seq], instance: inst, at: ev[:at], sitting: sitting.index, answers: {})
      @state.add_serve(serve)
      sitting.serve_seqs << serve.seq
      @state.served_fingerprints << inst.fingerprint
      if inst.short_answer?
        @state.short_serve = serve
      else
        inst.skills.each do |k|
          @state.served_count[k] += 1
          @state.outstanding[k] << serve.seq
          @state.visited << k
        end
      end
    end

    def apply_abandon(ev)
      serve = @state.serve(ev[:serve])
      return unless serve&.open?

      serve.abandoned_at = ev[:at]
      if serve.instance.short_answer?
        # The short answer has one instance and no answer was given: it is served again.
        @state.short_serve = nil if @state.short_serve.equal?(serve)
      else
        serve.instance.skills.each { |k| @state.outstanding[k].delete(serve.seq) }
      end
    end

    # ---- answers ------------------------------------------------------------

    def apply_answer(ev, idx)
      serve = @state.serve(ev[:serve])
      return unless serve

      kind = ev[:kind]
      skill = ev[:skill] || serve.instance.skill
      evidence = evidence_of(ev) if kind != "resolve_attempt" || ev[:verdict]
      return if evidence == :none

      serve.answered_at = [ serve.answered_at, ev[:at] ].compact.max if kind == "answered"
      return apply_short_answer(serve, ev) if serve.instance.short_answer?

      key = [ serve.seq, skill ]
      answer = serve.answers[skill] ||= State::Answer.new(counted: false)
      return if answer.counted

      if kind == "resolve_attempt"
        return if @first_certain[key] && @first_certain[key] < idx # applied in place already

        count(serve, skill, answer, ev, evidence)
      elsif certain?(evidence)
        source = @teacher[key] || ev
        count(serve, skill, answer, source, evidence_of(source))
      else
        answer.evidence = evidence
        answer.verdict = ev[:verdict].to_s
        answer.retry_state = ev[:retry_state]
      end
    end

    def apply_short_answer(serve, ev)
      serve.answers[serve.instance.skill] ||= State::Answer.new(evidence: :pending, verdict: "short_answer", counted: false)
      @state.short_serve = serve
    end

    def apply_confirm(ev)
      serve = @state.serve(ev[:serve])
      return unless serve&.instance&.short_answer?

      @state.short_state ||= if ev[:passed]
                               [ "demonstrated", "short_answer_above_threshold" ]
      else
                               [ "to_recover", "short_answer_below_threshold" ]
      end
    end

    # An answer becomes an outcome of the skill.
    def count(serve, skill, answer, source, evidence)
      answer.counted = true
      answer.evidence = evidence
      @state.outstanding[skill].delete(serve.seq)
      outcome = @state.outcomes[skill] ||= SkillOutcome.new(skill)
      return if outcome.resolved? # logged, ignored

      note_observations(skill, source, evidence)
      code = evidence == :W && source[:verdict].to_s == "typical_error" ? source[:error_code]&.to_s : nil
      resolved = outcome.record(SkillOutcome::Outcome.new(evidence: evidence, low_guess: serve.instance.low_guess_for(skill),
                                                          choice: serve.instance.choice_for(skill), code: code, serve: serve.seq))
      on_resolved(skill) if resolved
    end

    # Observations that go with a credit: the declared form skill becomes a
    # suspect at the tail; an orthography slip is only noted.
    def note_observations(skill, source, evidence)
      return unless evidence == :C

      if source[:orthography_slip] && source[:orthography_skill]
        @state.observations << { skill: source[:orthography_skill], about: skill, kind: "orthography_slip" }
      end
      return unless source[:form].to_s == "declared" && source[:form_skill]

      @state.observations << { skill: source[:form_skill], about: skill, kind: "wrong_form_declared" }
      add_suspect(source[:form_skill], within: skill)
    end

    # ---- resolution, descent, suspects -----------------------------------------

    def on_resolved(skill)
      @state.frontier.delete(skill)
      outcome = @state.outcomes[skill]
      if outcome.demonstrated?
        @state.below.merge(@plan.closure(skill))
        suspect_from_errors(skill, outcome)
      else
        descend(skill, outcome)
      end
    end

    def suspect_from_errors(skill, outcome)
      d = @plan.skill(skill)
      return unless d

      outcome.error_codes.each { |code| (d.errors[code] || []).each { |t| add_suspect(t, within: skill) } }
    end

    def descend(skill, outcome)
      d = @plan.skill(skill)
      return unless d

      targets = outcome.error_codes.flat_map { |code| d.errors[code] || [] }
      targets += d.parents if outcome.unclassified?(d.errors.keys)
      queue_targets(targets.uniq - [ skill ])
    end

    # Targets go to the head, depth-first, in the order given.
    def queue_targets(targets)
      accepted = targets.select { |t| descendable?(t) }
      accepted.each do |t|
        @state.visited << t
        @state.origin[t] = :target
      end
      @state.frontier.replace(accepted + (@state.frontier - accepted))
    end

    def descendable?(key)
      @state.visited << key # a foreign skill we descend to is reported even when unavailable
      d = @plan.skill(key)
      return false unless d
      return false if @state.resolved_state(key)
      return false if @state.stalled.key?(key) || key == @plan.short_skill
      return false if d.scope == "in_progress" # never into a block still in study
      return false if @state.below.include?(key)
      return false unless d.subject == @plan.subject # other subjects: reuse or cross_subject_unavailable

      true
    end

    def add_suspect(key, within:)
      d = @plan.skill(key)
      return unless d && d.subject == @plan.subject
      return unless @plan.closure(within).include?(key)
      return if @state.resolved_state(key) || @state.served_count[key].positive? || @state.frontier.include?(key)
      return if d.scope == "in_progress" || key == @plan.short_skill

      @state.visited << key
      @state.origin[key] = :suspect
      @state.suspect_log << key
      @state.frontier << key
    end

    # Eager resolutions that need no further event: a mixed pair whose third
    # (low-guess, unseen) item cannot be served ends as to_recover(mixed).
    def settle
      @state.outcomes.each do |key, outcome|
        next if outcome.resolved? || outcome.outcomes.size != 2
        next unless @state.outstanding[key].empty?
        # No third item can be served: none unseen, or the serve cap is reached (a
        # skill with one C and one W is to_recover(mixed), not not_assessed(item_cap)),
        # unless an answer of it may still settle (pending or ungraded).
        capped = @state.served_count[key] >= Rules::V1::MAX_SERVED_PER_SKILL && !pending_answer?(key)
        next unless capped || Candidates.for(@state, key, :third).empty?

        on_resolved(key) if outcome.resolve_mixed!
      end
    end

    def pending_answer?(key)
      @state.serves.any? do |serve|
        a = serve.answers[key]
        a && !a.counted && %i[pending ungraded].include?(a.evidence)
      end
    end
  end
end
