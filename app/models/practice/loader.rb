module Practice
  # Reads the practice rows of one student in one subject into what the pure engine takes (A8, C1).
  # Read-only. The tries of voided item revisions (void_revision_attempts decisions, which name the
  # official student) are dropped from the tries; their serves stay (the fingerprints stay seen).
  #
  #   input = Practice::Loader.for(student, subject: subject)
  #   Practice::Fold.call(seeds: input.seeds, tries: input.tries, serves: input.serves)
  class Loader
    V5 = Rules::V5

    Input = Data.define(:seeds, :tries, :serves, :voided_item_revision_ids)

    # skill: only the serves of that skill; seeds: false skips the diagnosis seeds (the serving path does
    # not need them and they are the costly part).
    def self.for(student, subject:, now: Time.current, skill: nil, seeds: true) = new(student, subject, now, skill, seeds).input

    # The ServeState::Status of one serve now, from its rows (a serve is abandoned when older than
    # OPEN_SERVE_HOURS or superseded by a newer serve of the same student on the same item).
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
      # ESCAPE: SQLite's LIKE has no default escape character, so without it "law\_economics.%" matched nothing and a subject
      # with an underscore in its key (law_economics, computer_science) never folded its skills.
      scope = @skill ? scope.where(skill_key: @skill) : scope.where("skill_key LIKE ? ESCAPE '\\'", "#{PracticeServe.sanitize_sql_like(@subject.key)}.%")
      @serves ||= scope.includes(:events, item_instance: { item_revision: :item }, attempts: :gradings).order(:id).to_a
    end

    # The attempts that the student sent to the teacher (PracticeContest, practice/3): for a student's loader those of all
    # its serves, read once; a lone serve (status_of) asks for its own.
    def contested_ids(serve)
      return Set.new unless defined?(PracticeContest)
      return PracticeContest.where(practice_serve_id: serve.id).pluck(:practice_attempt_id).to_set unless @student

      @contested_ids ||= PracticeContest.where(practice_serve_id: serves.map(&:id)).pluck(:practice_attempt_id).to_set
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
          grade = Instances.grade(attempt, spec, contested_ids: contested_ids(serve)) or next

          Try.new(skill: serve.skill_key, at: attempt.answered_at, day: attempt.answered_at.in_time_zone(V5::ZONE).to_date, serve_id: serve.id,
                  fingerprint: instance.fingerprint, item_id: instance.item_revision.item_id, item_revision_id: instance.item_revision_id,
                  low_guess: low, try_number: attempt.try_number, aided: attempt.aided || serve.reason == "reseen", reseen: serve.reason == "reseen",
                  evidence: Outcome.evidence(grade.outcome), outcome: grade.outcome, error_codes: grade.codes, contested: grade.contested,
                  seconds: (attempt.answered_at - started).to_i.clamp(0, V5::TIME_CAP_SECONDS))
        end
      end
    end

    def status_for(serve)
      ServeState.call(serve: serve, tries: serve_tries(serve).map { |t| ServeTry.new(t.try_number, t.outcome, t.contested) },
                      events: serve.events.sort_by(&:id).map { |e| serve_event(e) }, hints_total: Instances.hints(serve.item_instance).size, now: @now,
                      superseded: superseded?(serve))
    end

    # A newer serve of the same student on the same item (any revision) exists. The loader of a student reads
    # the newest serve of every item at once; one serve alone asks the database.
    def superseded?(serve)
      item_id = serve.item_instance.item_revision.item_id
      newest = @student ? latest_by_item[item_id] : newest_serve_id(serve.student_id, [ item_id ])[item_id]
      newest.to_i > serve.id
    end

    def latest_by_item
      @latest_by_item ||= newest_serve_id(@student.id, serves.map { |s| s.item_instance.item_revision.item_id }.uniq)
    end

    def newest_serve_id(student_id, item_ids)
      PracticeServe.where(student_id: student_id).joins(item_instance: :item_revision)
                   .where(item_revisions: { item_id: item_ids }).group("item_revisions.item_id").maximum(:id)
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
