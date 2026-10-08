module Practice
  # Reads the practice rows of one student in one subject into what the pure engine takes (A8, C1).
  # Read-only. The tries of voided item revisions (void_revision_attempts decisions, which name the
  # official student) are dropped from the tries; their serves stay (the fingerprints stay seen).
  #
  #   input = Practice::Loader.for(student, subject: subject)
  #   Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves)
  class Loader
    V1 = Rules::V1

    Input = Data.define(:seeds, :tries, :serves, :voided_item_revision_ids)

    # skill: only the serves of that skill; seeds: false skips the diagnosis seeds (the serving path does
    # not need them and they are the costly part).
    def self.for(student, subject:, now: Time.current, skill: nil, seeds: true) = new(student, subject, now, skill, seeds).input

    # The ServeState::Status of one serve now, from its rows.
    def self.status_of(serve, now: Time.current) = new(nil, nil, now).send(:status_for, serve)

    def initialize(student, subject, now, skill = nil, seeds = true)
      @student = student
      @subject = subject
      @now = now
      @skill = skill
      @seeds = seeds
    end

    def input
      voided = voided_revisions
      tries = []
      rows = serves.map do |serve|
        serve_tries = serve_tries(serve)
        tries.concat(serve_tries.reject { |t| voided.include?(t.item_revision_id) })
        serve_row(serve)
      end
      Input.new(seeds: @seeds ? Seeder.call(@student, @subject) : {}, tries: tries, serves: rows, voided_item_revision_ids: voided)
    end

    private

    def serves
      scope = PracticeServe.where(student: @student)
      scope = @skill ? scope.where(skill_key: @skill) : scope.where("skill_key LIKE ?", "#{PracticeServe.sanitize_sql_like(@subject.key)}.%")
      @serves ||= scope.includes(:events, item_instance: { item_revision: :item }, attempts: :gradings).order(:id).to_a
    end

    def voided_revisions
      Decision.where(kind: "void_revision_attempts", student_id: @student.id)
              .filter_map { |d| JSON.parse(d.payload_json)["item_revision_id"] }.to_set
    end

    # The tries of a serve in order, built from attempts whose latest grading is a practice try.
    def serve_tries(serve)
      @tries_by_serve ||= {}
      @tries_by_serve[serve.id] ||= begin
        instance = serve.item_instance
        spec = Grading::Spec.from_instance(instance)
        low = Instances.low_guess?(instance)
        previous = serve.created_at
        serve.attempts.sort_by(&:try_number).filter_map do |attempt|
          started = previous
          previous = attempt.answered_at
          grade = Instances.grade(attempt, spec) or next

          Try.new(skill: serve.skill_key, at: attempt.answered_at, day: attempt.answered_at.in_time_zone(V1::ZONE).to_date, serve_id: serve.id,
                  fingerprint: instance.fingerprint, item_id: instance.item_revision.item_id, item_revision_id: instance.item_revision_id,
                  low_guess: low, try_number: attempt.try_number, aided: attempt.aided || serve.reason == "reseen", reseen: serve.reason == "reseen",
                  evidence: Outcome.evidence(grade.outcome), outcome: grade.outcome, error_codes: grade.codes,
                  seconds: (attempt.answered_at - started).to_i.clamp(0, V1::TIME_CAP_SECONDS))
        end
      end
    end

    def status_for(serve)
      ServeState.call(serve: serve, tries: serve_tries(serve).map { |t| ServeTry.new(t.try_number, t.outcome) },
                      events: serve.events.sort_by(&:id).map { |e| serve_event(e) }, hints_total: Instances.hints(serve.item_instance).size, now: @now)
    end

    def serve_row(serve)
      instance = serve.item_instance
      events = serve.events.sort_by(&:id).map { |e| serve_event(e) }
      status = status_for(serve)
      ServeRow.new(id: serve.id, student_id: serve.student_id, skill: serve.skill_key, topic_revision_id: serve.topic_revision_id,
                   item_instance_id: instance.id, item_revision_id: instance.item_revision_id, item_id: instance.item_revision.item_id,
                   fingerprint: instance.fingerprint, reason: serve.reason, parent_serve_id: serve.parent_serve_id, error_code: serve.error_code,
                   at: serve.created_at, hints_shown: status.hints_shown, solution_requested: events.any? { |e| e.reason == "requested" }, status: status)
    end

    def serve_event(event)
      payload = JSON.parse(event.payload_json || "{}")
      ServeEvent.new(kind: event.kind, n: payload["n"], reason: payload["reason"], auto: payload["auto"] == true, at: event.at)
    end
  end
end
