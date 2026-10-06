module Diagnosis
  # Runs one diagnosis run for the web (M10): asks the pure engine what comes
  # next, appends the event that goes with the answer and, for an item, the
  # item_served detail row with the serve-time shuffle (X-01). It is the only
  # writer of run events besides the teacher's decisions.
  #
  #   conductor = Conductor.new(run)
  #   step = conductor.step!      # => Step (item, sitting_over, wait, final)
  #   conductor.record(:paused)   # pause and visibility events
  class Conductor
    # type: :item (+event+ is the item_served event), :sitting_over (the sitting
    # ended and another is allowed), :wait (the next sitting starts on a later
    # day), :final (the run is closed).
    Step = Data.define(:type, :event, :reason)

    PAUSE_EVENTS = %w[paused resumed hidden visible].freeze
    MAX_LOOPS = 12

    attr_reader :run, :clock

    # The run of a student in a subject that goes on now: the latest one, unless
    # the teacher voided it, in which case a fresh run starts (a redo). Nil when
    # the subject has no blueprint yet.
    def self.run_for(student, subject)
      latest = DiagnosisRun.where(student: student, subject: subject).order(:sequence).last
      return latest if latest && !EventLoader.voided?(latest)

      create_run(student, subject, sequence: latest ? latest.sequence + 1 : 1)
    end

    # A new run now, whatever came before (the teacher's preview starts afresh).
    def self.fresh_run(student, subject)
      latest = DiagnosisRun.where(student: student, subject: subject).order(:sequence).last
      create_run(student, subject, sequence: latest ? latest.sequence + 1 : 1)
    end

    def self.create_run(student, subject, sequence:)
      blueprint = student.kind == "preview" ? latest_blueprint(subject) : approved_blueprint(subject)
      return nil unless blueprint

      DiagnosisRun.create!(student: student, subject: subject, blueprint_revision: blueprint, sequence: sequence,
                           seed_salt: SecureRandom.hex(8), rules_version: Rules::V1::RULES_VERSION,
                           engine_version: Engine::VERSION)
    end

    # The newest draft of a subject's entry test: what the teacher's preview plays
    # and what the approval gate looks at.
    def self.latest_blueprint(subject)
      BlueprintRevision.where(subject: subject).order(:seq).last
    end

    # The blueprint a run of the student is pinned to when it starts: the revision
    # the teacher approved last, needing an approved graph too. A newer draft never
    # replaces it and never changes a run that has started (M9a, D-059).
    def self.approved_blueprint(subject)
      blueprint = SubjectStage.approved_blueprint(subject) or return nil
      SubjectStage.approved_graph(subject) ? blueprint : nil
    end

    # The serve-time shuffle of an instance (X-01), also used by the teacher's item
    # preview, which shows an instance the way a run would.
    def self.rekey(instance, body, seed)
      display = JSON.parse(instance.display_json)
      answer = JSON.parse(instance.answer_json)
      errors = instance.errors_json.present? ? JSON.parse(instance.errors_json) : []
      if body["kind"] == "testlet"
        subs = Array(body["sub_items"]).map do |sub|
          shown = Array(display["sub_items"]).find { |s| s["id"] == sub["id"] }
          { "id" => sub["id"], "component" => sub["component"], "display" => shown&.fetch("display", {}) || {},
            "answer" => answer.is_a?(Hash) ? answer[sub["id"]] : nil,
            "errors" => errors.is_a?(Hash) ? Array(errors[sub["id"]]) : [] }
        end
        Rekey.testlet(subs, seed: seed)
      else
        component = body["kind"] == "short_answer" ? "short_answer" : body["component"]
        Rekey.call(display: display, component: component, answer: answer, seed: seed, errors: Array(errors))
      end
    end

    def initialize(run, clock: Clock.new)
      @run = run
      @clock = clock
    end

    # The plan the engine decides on: what other subjects resolved and what the
    # student has seen count (reuse). The light plan leaves them out; it is enough
    # to read facts that the log alone settles (open, closed, sittings), and it is
    # much cheaper, because reuse loads the plan of every other run of the student.
    def plan(reuse: true)
      reuse ? (@plan ||= PlanLoader.for_run(run)) : (@light_plan ||= PlanLoader.for_run(run, reuse: false))
    end

    def events = EventLoader.for_run(run)

    # What the log says, folded with the light plan.
    def state = Engine.fold(plan(reuse: false), events)

    # Moves the run on until there is something to show.
    def step!
      MAX_LOOPS.times do
        action = Engine.next_action(plan, events, clock)
        case action.type
        when :none then return Step.new(:final, nil, action.reason)
        when :wait
          # The engine holds a run open while an answer of it is pending or ungraded
          # (D-039). The student has nothing more to answer: the end screen, which
          # lists the pending items as "in correzione", is the honest page.
          return Step.new(:final, nil, "pending_answers") if action.reason == :pending_answers

          return Step.new(:item, open_serve_event(action.serve), nil)
        when :abandon_item then append("item_abandoned", "serve" => action.serve)
        when :start_sitting
          return Step.new(:wait, nil, nil) if action.not_before > clock.date(clock.now)

          append("sitting_started", "condition" => "unsupervised")
        when :end_sitting
          append("sitting_closed", "reason" => action.reason)
          return Step.new(:sitting_over, nil, action.reason)
        when :close_run
          append("run_closed", "reason" => action.reason)
          return Step.new(:final, nil, action.reason)
        when :serve then return Step.new(:item, serve!(action), action.reason)
        else raise "unknown engine action #{action.type.inspect}"
        end
      rescue ActiveRecord::RecordNotUnique
        next # another request appended at the same moment: look again
      end
      raise "the engine did not settle after #{MAX_LOOPS} steps"
    end

    # Pause and visibility events, only on change. Returns true when one was written.
    def record(kind)
      kind = kind.to_s
      raise ArgumentError, "not a pause event: #{kind}" unless PAUSE_EVENTS.include?(kind)

      pair = kind.in?(%w[paused resumed]) ? %w[paused resumed] : %w[hidden visible]
      last = run.events.where(kind: pair).order(:seq).last&.kind
      return false if (last || pair.last) == kind

      append(kind)
      true
    end

    def closed? = state.closed

    # Open, but with nothing left to ask while an answer is pending or ungraded.
    def holding?
      return false if closed?

      action = Engine.next_action(plan, events, clock)
      action.type == :wait && action.reason == :pending_answers
    end

    # A sitting is open and has already served something: the student is coming back.
    def resuming? = state.open_sitting&.serve_seqs&.any? ? true : false

    # The item_served detail of an event and its presentation.
    def presentation(event, student:)
      served = ItemServed.includes(item_instance: :item_revision).find_by!(diagnosis_event_id: event.id)
      ItemPresenter.new(
        served: served, number: serve_number(event), subject: run.subject,
        not_studied: not_studied?(served.skill_key),
        expression_input: editor_fallback?(student) ? "text" : "mathlive"
      ).as_json
    end

    private

    def append(kind, payload = nil)
      DiagnosisEvent.transaction do
        seq = DiagnosisEvent.where(diagnosis_run_id: run.id).maximum(:seq).to_i + 1
        DiagnosisEvent.create!(diagnosis_run: run, seq: seq, kind: kind, at: clock.now, payload_json: payload&.to_json)
      end
    end

    def open_serve_event(seq)
      run.events.find_by!(seq: seq)
    end

    # Appends item_served and its detail row in one transaction. The shuffle is
    # seeded from the run's salt, the serve's own seq and the instance, so a
    # replay of the log can recompute it; what was shown is also stored.
    def serve!(action)
      instance = ItemInstance.includes(:item_revision).find(action.instance.id)
      body = JSON.parse(instance.item_revision.body_json)
      DiagnosisEvent.transaction do
        seq = DiagnosisEvent.where(diagnosis_run_id: run.id).maximum(:seq).to_i + 1
        rekeyed = rekey(instance, body, "#{run.seed_salt}|#{seq}|#{instance.id}")
        event = DiagnosisEvent.create!(diagnosis_run: run, seq: seq, kind: "item_served", at: clock.now,
                                       payload_json: { "reason" => action.reason }.to_json)
        ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: action.skill,
                           shown_order_json: rekeyed.shown_order.to_json, id_map_json: rekeyed.id_map.to_json)
        event
      end
    end

    def rekey(instance, body, seed) = self.class.rekey(instance, body, seed)

    # "Domanda n": the serves of this run up to this one, not counting the ones
    # given up.
    def serve_number(event)
      abandoned = run.events.where(kind: "item_abandoned").filter_map { |e| JSON.parse(e.payload_json || "{}")["serve"] }
      run.events.where(kind: "item_served").where("seq <= ?", event.seq).where.not(seq: abandoned).count
    end

    # Skills the student is still studying or never saw get the button
    # "Non l'ho ancora studiato" instead of "Non lo so".
    def not_studied?(skill_key)
      Rules::V1::LEARN_SCOPES.include?(plan.skill(skill_key)&.scope)
    end

    def editor_fallback?(student)
      AppEvent.where(student_id: student.id, kind: "warmup_editor_fallback").exists?
    end
  end
end
