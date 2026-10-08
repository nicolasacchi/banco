module Practice
  # Takes one answer to a practice serve and records it (A8.4, A9.3). Grading runs first, outside any
  # transaction (the expression worker can take 2 s); then one short transaction re-derives the serve
  # state, refuses a closed serve, and appends the attempt, its grading and the events the state machine
  # names. A repeated client_attempt_id returns the stored answer rebuilt from rows.
  #
  #   Practice::AnswerRecorder.new(student:, clock:).call(serve_id:, client_attempt_id:, raw:, source:)
  #   # => Result(http:, body:)
  class AnswerRecorder
    Result = Data.define(:http, :body)

    SOURCES = %w[text mathlive button].freeze
    MAX_RAW_BYTES = 20_000
    ID_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/
    AUTO_SOLUTION_REASONS = %w[after_correct after_last_try after_undetermined].freeze
    ATTEMPTS = 3

    def initialize(student:, clock: Diagnosis::Clock.new)
      @student = student
      @clock = clock
    end

    def call(serve_id:, client_attempt_id:, raw:, source:)
      client_id = client_attempt_id.to_s
      return not_found unless raw.is_a?(String) && client_id.match?(ID_FORMAT)
      return invalid(Grading::Result::MESSAGES_IT["empty"]) if raw.strip.empty?
      return invalid(Grading::Result::MESSAGES_IT["unparseable"]) if raw.bytesize > MAX_RAW_BYTES

      serve = PracticeServe.find_by(id: serve_id, student_id: @student.id) or return not_found
      existing = PracticeAttempt.find_by(client_attempt_id: client_id)
      return existing.practice_serve_id == serve.id && existing.student_id == @student.id ? stored(serve, existing) : not_found if existing
      unless Loader.status_of(serve, now: @clock.now).state == :open
        # a twin of this very answer may have been stored and closed the serve since the lookup above
        twin = PracticeAttempt.find_by(client_attempt_id: client_id, student_id: @student.id, practice_serve_id: serve.id)
        return twin ? stored(serve, twin) : closed
      end

      source = SOURCES.include?(source.to_s) ? source.to_s : "text"
      instance = serve.item_instance
      spec = Grading::Spec.from_instance(instance)
      begin
        result = Grading.grade(instance, raw, source: source, id_map: serve.id_map_json.present? ? JSON.parse(serve.id_map_json) : nil)
      rescue Grading::Expression::Unavailable
        return Result.new(503, { status: "retry" })
      end
      key = result.invalid? ? nil : Grading::Evidence.key(verdict: result.verdict, spec: spec, error_codes: result.error_codes,
                                                          method: result.grading_method)
      return refuse(serve, result, key) if result.invalid? || !Outcome.try?(key)

      record(serve, client_id, raw, source, result, key)
    end

    private

    # Invalid input is not a try (row 10): an app event and a message, nothing else.
    def refuse(serve, result, key)
      code = result.invalid? ? result.invalid_code : key
      AppEvent.create!(kind: "practice_invalid_input", student: @student, payload_json: { serve_id: serve.id, code: code }.to_json)
      invalid(result.invalid? ? result.message_it : Grading::Result::MESSAGES_IT["unparseable"])
    end

    def record(serve, client_id, raw, source, result, key)
      attempts = 0
      begin
        attempts += 1
        attempt = write(serve, client_id, raw, source, result, key)
        # no longer open: a twin of this very answer may have closed it a moment ago
        attempt ||= PracticeAttempt.find_by(client_attempt_id: client_id, student_id: @student.id, practice_serve_id: serve.id)
        return closed unless attempt

        stored(serve, attempt)
      rescue ActiveRecord::RecordNotUnique
        # the same answer arrived twice at once, or another try took the number: look again
        again = PracticeAttempt.find_by(client_attempt_id: client_id)
        return stored(serve, again) if again
        retry if attempts < ATTEMPTS
        closed
      end
    end

    # One short transaction. Nil when the serve is no longer open.
    def write(serve, client_id, raw, source, result, key)
      now = @clock.now
      PracticeAttempt.transaction do
        serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(serve.id)
        status = Loader.status_of(serve, now: now)
        next nil unless status.state == :open

        hints_total = Instances.hints(serve.item_instance).size
        aided = ServeState.aided?(reason: serve.reason, w: status.w, hints_shown: status.hints_shown)
        outcome = Outcome.call(evidence_key: key, aided: aided)
        step = ServeState.step(status, :answer, outcome: outcome, hints_total: hints_total)
        attempt = PracticeAttempt.create!(student: @student, practice_serve: serve, try_number: serve.attempts.map(&:try_number).max.to_i + 1,
                                          client_attempt_id: client_id, raw: raw, source: source, hints_before: status.hints_shown,
                                          aided: aided, answered_at: now, created_at: now)
        Grading::Recorder.append(attempt, result, model: PracticeGrading)
        event(serve, "solution_shown", { reason: step.solution_reason }, now) if step.solution_reason
        event(serve, "hint_shown", { n: step.hint_n, auto: true }, now) if step.auto_hint
        attempt
      end
    end

    def event(serve, kind, payload, now)
      PracticeEvent.create!(student: @student, kind: kind, practice_serve: serve, topic_revision_id: serve.topic_revision_id,
                            payload_json: payload.to_json, at: now, created_at: now)
    end

    # The answer of A9.3 rebuilt from rows: what this attempt did, the same on the first reply and on a repeat.
    def stored(serve, attempt)
      serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(serve.id)
      attempt = serve.attempts.find { |a| a.id == attempt.id } # as stored (the database keeps microseconds)
      instance = serve.item_instance
      spec = Grading::Spec.from_instance(instance)
      upto = serve.attempts.sort_by(&:try_number).select { |a| a.try_number <= attempt.try_number }
      grades = upto.to_h { |a| [ a.id, Instances.grade(a, spec) ] }
      grade = grades.fetch(attempt.id) or return Result.new(200, { status: "invalid", message_it: Grading::Result::MESSAGES_IT["unparseable"] })
      tries = ->(list) { list.filter_map { |a| g = grades[a.id] and ServeTry.new(a.try_number, g.outcome) } }
      events = serve.events.sort_by(&:id).map { |e| serve_event(e) }
      hints_total = Instances.hints(instance).size
      at = attempt.answered_at
      before = ServeState.call(serve: serve, tries: tries.(upto[0...-1]), events: events.select { |e| e.at < at }, hints_total: hints_total, now: at)
      after = ServeState.call(serve: serve, tries: tries.(upto), events: events.select { |e| e.at <= at }, hints_total: hints_total, now: at)
      made = events.select { |e| e.at == at }
      body = graded_body(instance, grade, attempt, before, after, made)
      body[:skill] = skill_block(serve, attempt)
      body[:actions] = Payload.actions(after)
      body[:hint] = (h = made.find { |e| e.kind == "hint_shown" && e.auto }) ? Payload.hint(instance, h.n) : nil
      body[:solution] = made.any? { |e| e.kind == "solution_shown" && AUTO_SOLUTION_REASONS.include?(e.reason) } ? Payload.solution(instance) : nil
      Result.new(200, body)
    end

    def graded_body(instance, grade, attempt, before, after, made)
      outcome = grade.outcome
      closing = case outcome
      when :unrecognised, :form then before.w >= 1
      when :near_miss then after.closed_by == :near_miss
      else false
      end
      code = grade.codes.first
      { status: "graded", outcome: outcome.to_s, try_number: attempt.try_number,
        message_it: Messages.feedback(outcome, typical: code && Instances.message_for(instance, code), violations: grade.violations, closing: closing,
                                    hint: made.any? { |e| e.kind == "hint_shown" && e.auto }),
        note_it: %i[correct correct_aided].include?(outcome) ? Messages.note(grade.key, violations: grade.violations) : nil,
        error_code: outcome == :typical_error ? code : nil }
    end

    # The skill's state and "perché" after this try, and whether this try changed the state.
    def skill_block(serve, attempt)
      subject = Subject.find_by!(key: serve.skill_key.split(".").first)
      input = Loader.for(@student, subject: subject, now: @clock.now)
      mark = [ attempt.answered_at, serve.id, attempt.try_number ]
      key = ->(t) { [ t.at, t.serve_id, t.try_number ] }
      args = { seeds: input.seeds, serves: input.serves, skills: [ serve.skill_key ] }
      before = Fold.call(tries: input.tries.select { |t| (key.(t) <=> mark) < 0 }, **args)
      after = Fold.call(tries: input.tries.select { |t| (key.(t) <=> mark) <= 0 }, **args)
      Payload.skill(serve.skill_key, before, after)
    end

    def serve_event(event)
      payload = JSON.parse(event.payload_json || "{}")
      ServeEvent.new(kind: event.kind, n: payload["n"], reason: payload["reason"], auto: payload["auto"] == true, at: event.at)
    end

    def invalid(message) = Result.new(200, { status: "invalid", message_it: message })
    def closed = Result.new(409, Payload.closed)
    def not_found = Result.new(404, { status: "not_found" })
  end
end
