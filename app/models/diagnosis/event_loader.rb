module Diagnosis
  # Turns the rows of one run into the list of events the pure fold reads: the
  # run's own events, each attempt with its gradings, and the teacher decisions
  # that touch the run. Read-only. Order: time, then source (events, attempts,
  # gradings, decisions), then row id.
  #
  # Payloads of decisions (see docs/rules/diagnosis-1.md, section 13):
  #   resolve_attempt {attempt_id, verdict, error_code?}, confirm_grade {attempt_id,
  #   passed}, extend_diagnosis_run {run_id}, close_diagnosis_run {run_id},
  #   void_revision_attempts {item_revision_id}.
  class EventLoader
    RANK = { event: 0, attempt: 1, grading: 2, decision: 3 }.freeze

    def self.for_run(run) = new(run).events

    def self.voided?(run)
      Decision.where(kind: "void_diagnosis_run", student_id: run.student_id).any? do |d|
        JSON.parse(d.payload_json)["run_id"] == run.id
      end
    end

    def initialize(run)
      @run = run
    end

    def events
      rows = run_events + attempt_events + decision_events
      rows.sort_by { |at, rank, id, _| [ at, rank, id ] }.map(&:last)
    end

    private

    def run_events
      served = ItemServed.where(diagnosis_event_id: @run.events.select(:id)).index_by(&:diagnosis_event_id)
      @run.events.order(:seq).map do |row|
        payload = row.payload_json ? JSON.parse(row.payload_json) : {}
        ev = payload.symbolize_keys.merge(kind: row.kind, at: row.at, seq: row.seq)
        if row.kind == "item_served"
          detail = served.fetch(row.id)
          ev[:instance] = detail.item_instance_id
          ev[:skill] = detail.skill_key
        end
        [ row.at, RANK[:event], row.id, ev ]
      end
    end

    def seq_by_event_id = @seq_by_event_id ||= @run.events.pluck(:id, :seq).to_h

    def voided_revisions
      @voided_revisions ||= Decision.where(kind: "void_revision_attempts", student_id: @run.student_id).filter_map do |d|
        JSON.parse(d.payload_json)["item_revision_id"]
      end
    end

    def attempts = @attempts ||= Attempt.where(served_event_id: seq_by_event_id.keys, context: %w[diagnosis teacher_preview])
                                        .includes(:gradings, item_instance: :item_revision)
                                        .reject { |a| voided_revisions.include?(a.item_instance.item_revision_id) }

    def attempt_events
      attempts.flat_map do |attempt|
        serve = seq_by_event_id.fetch(attempt.served_event_id)
        body = JSON.parse(attempt.item_instance.item_revision.body_json)
        skill = body["skill"]
        gradings = attempt.gradings.to_a
        first = gradings.first
        answered = first ? grading_fields(first, body, skill) : { verdict: "ungraded", retry_state: retry_state(attempt) }
        out = [ [ attempt.answered_at, RANK[:attempt], attempt.id, { kind: "answered", at: attempt.answered_at, serve: serve }.merge(answered) ] ]
        gradings.drop(1).each do |g|
          out << [ g.created_at, RANK[:grading], g.id, { kind: "grading", at: g.created_at, serve: serve }.merge(grading_fields(g, body, skill)) ]
        end
        out
      end
    end

    # The grader's verdict plus what the item says about forms and spelling.
    def grading_fields(grading, body, skill)
      codes = grading.error_codes_json ? JSON.parse(grading.error_codes_json) : []
      code = codes.first
      fields = { verdict: grading.verdict, error_code: code }
      # The credit rule of Grading::Evidence#orthography_slip?: the item says accent_policy
      # flag (a missing policy is strict) and every code is an accent or apostrophe code.
      if grading.verdict == "typical_error" && body["accent_policy"] == "flag" && codes.any? && (codes - Rules::V1::ORTHOGRAPHY_ALLOWLIST).empty?
        fields[:orthography_slip] = true
      end
      # A result that touched floating point is uncertain whatever it says (D-029).
      fields[:method] = "float" if grading.method == "float"
      if grading.verdict == "wrong_form"
        form_skill = body["form_skill"]
        fields[:form] = if form_skill && form_skill != skill then "declared"
        elsif body["form"].present? then "skill" # the form is the skill itself
        end
        fields[:form_skill] = form_skill if form_skill
      end
      fields.compact
    end

    def retry_state(attempt)
      exhausted = AppEvent.where(kind: "grade_retries_exhausted").any? { |e| JSON.parse(e.payload_json || "{}")["attempt_id"] == attempt.id }
      exhausted ? "exhausted" : "running"
    end

    def decision_events
      attempt_serve = attempts.to_h { |a| [ a.id, seq_by_event_id.fetch(a.served_event_id) ] }
      Decision.where(student_id: @run.student_id, subject_id: @run.subject_id)
              .where(kind: %w[resolve_attempt confirm_grade extend_diagnosis_run close_diagnosis_run]).order(:id).filter_map do |d|
        payload = JSON.parse(d.payload_json)
        ev = { kind: d.kind, at: d.created_at }
        case d.kind
        when "resolve_attempt", "confirm_grade"
          serve = attempt_serve[payload["attempt_id"]]
          next unless serve

          ev[:serve] = serve
          ev.merge!(verdict: payload["verdict"], error_code: payload["error_code"]) if d.kind == "resolve_attempt"
          ev[:passed] = payload["passed"] if d.kind == "confirm_grade"
        else
          next unless payload["run_id"] == @run.id
        end
        [ d.created_at, RANK[:decision], d.id, ev.compact ]
      end
    end
  end
end
