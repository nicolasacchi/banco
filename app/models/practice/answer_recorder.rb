module Practice
  # Takes one answer to a practice serve and records it (A8.4, A9.3). Grading runs first, outside any
  # transaction (the expression worker can take 2 s); then one short transaction re-derives the serve
  # state, refuses a closed serve, and appends the attempt, its grading and the events the state machine
  # names. A repeated client_attempt_id returns the stored answer rebuilt from rows.
  #
  #   Practice::AnswerRecorder.new(student:, shown:, clock:).call(serve_id:, client_attempt_id:, raw:, source:)
  #   # => Result(http:, body:)
  class AnswerRecorder
    Result = Data.define(:http, :body)

    SOURCES = %w[text mathlive button].freeze
    MAX_RAW_BYTES = 20_000
    ID_FORMAT = /\A[A-Za-z0-9_-]{8,64}\z/
    AUTO_SOLUTION_REASONS = %w[after_correct after_last_try after_undetermined].freeze
    ATTEMPTS = 3

    # shown: {lesson id => TopicRevision} (Course::StudentView#shown_revisions): what the student is shown now. An answer to an open serve made on
    # another revision of a shown lesson is not taken: the reply is `replaced` (D-377), with no try, no event and no row.
    def initialize(student:, shown: nil, clock: Diagnosis::Clock.new)
      @student = student
      @shown = shown
      @clock = clock
    end

    def call(serve_id:, client_attempt_id:, raw:, source:)
      client_id = client_attempt_id.to_s
      return not_found unless raw.is_a?(String) && client_id.match?(ID_FORMAT)
      return invalid(Grading::Result.message("empty")) if raw.strip.empty?
      return invalid(Grading::Result.message("unparseable")) if raw.bytesize > MAX_RAW_BYTES

      serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find_by(id: serve_id, student_id: @student.id) or return not_found
      existing = PracticeAttempt.find_by(client_attempt_id: client_id)
      return existing.practice_serve_id == serve.id && existing.student_id == @student.id ? stored(serve, existing) : not_found if existing
      status = Loader.status_of(serve, now: @clock.now, shown: @shown)
      unless status.state == :open
        # a twin of this very answer may have been stored and closed the serve since the lookup above
        twin = PracticeAttempt.find_by(client_attempt_id: client_id, student_id: @student.id, practice_serve_id: serve.id)
        return twin ? stored(serve, twin) : refused(status)
      end

      source = SOURCES.include?(source.to_s) ? source.to_s : "text"
      instance = serve.item_instance
      spec = Grading::Spec.from_instance(instance)
      return same_answer(serve) if repeated?(serve, spec, raw) # D-339: not a try, nothing stored
      begin
        result = Grading.grade(instance, raw, source: source, id_map: serve.id_map_json.present? ? JSON.parse(serve.id_map_json) : nil)
      rescue Grading::Expression::Unavailable
        return Result.new(503, { status: "retry" })
      end
      key = result.invalid? ? nil : Grading::Evidence.key(verdict: result.verdict, spec: spec, error_codes: result.error_codes,
                                                          method: result.grading_method)
      return refuse(serve, result, key, raw) if result.invalid? || !Outcome.try?(key)

      record(serve, client_id, raw, source, result, key)
    end

    private

    # Invalid input is not a try (row 10): an app event and a message, nothing else.
    def refuse(serve, result, key, raw)
      code = result.invalid? ? result.invalid_code : key
      payload = { serve_id: serve.id, code: code }
      payload[:text] = raw.first(Diagnosis::AnswerRecorder::REFUSED_TEXT_CHARS) if result.invalid? # D-298
      AppEvent.create!(kind: "practice_invalid_input", student: @student, payload_json: payload.to_json)
      invalid(result.invalid? ? result.message_it : Grading::Result.message("unparseable"))
    end

    def record(serve, client_id, raw, source, result, key)
      attempts = 0
      begin
        attempts += 1
        attempt = write(serve, client_id, raw, source, result, key)
        return same_answer(PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(serve.id)) if attempt == :same
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

    # One short transaction. Nil when the serve is no longer open; :same when an identical answer was stored since the check in call.
    def write(serve, client_id, raw, source, result, key)
      now = @clock.now
      PracticeAttempt.transaction do
        serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(serve.id)
        status = Loader.status_of(serve, now: now, shown: @shown)
        next nil unless status.state == :open

        spec = Grading::Spec.from_instance(serve.item_instance)
        next :same if repeated?(serve, spec, raw)

        hints_total = Instances.hints(serve.item_instance).size
        aided = ServeState.aided?(reason: serve.reason, w: status.w, hints_shown: status.hints_shown)
        near = Instances.near_kind(spec, key, result.normalized.presence || raw) # the loader derives it the same way from the stored row
        outcome = Outcome.call(evidence_key: key, aided: aided, near: near)
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

    # The same answer as a try this serve already has, read as the grader reads it: a whole sentence round a `___` blank is its words in the
    # blank's place, then the spaces collapsed and a text answer normalized as the grader does.
    def repeated?(serve, spec, raw)
      mine = answer_key(spec, raw)
      serve.attempts.any? { |a| answer_key(spec, a.raw) == mine }
    end

    def answer_key(spec, raw)
      text = (full_sentence_part(spec, raw.to_s) || raw.to_s).gsub(/[[:space:]]+/, " ").strip
      spec.component == "normalized_text" ? Grading::Closed::Text.normalize(text, case_sensitive: spec.case_sensitive) : text
    end

    # Refused, not a try, nothing stored: status `same_answer` (the page and its outbox end the entry on it; the page does not draw it as a
    # verdict; HTTP 200, so the browser logs no failed request). `actions` lets the page offer «Fai controllare» while a contest is allowed.
    def same_answer(serve)
      Result.new(200, { status: "same_answer", message_it: I18n.t("practice.same_answer"), actions: Loader.status_of(serve, now: @clock.now, shown: @shown).actions })
    end

    # The answer of A9.3 rebuilt from rows: what this attempt did, the same on the first reply and on a repeat.
    def stored(serve, attempt)
      serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find(serve.id)
      attempt = serve.attempts.find { |a| a.id == attempt.id } # as stored (the database keeps microseconds)
      instance = serve.item_instance
      spec = Grading::Spec.from_instance(instance)
      upto = serve.attempts.sort_by(&:try_number).select { |a| a.try_number <= attempt.try_number }
      grades = upto.to_h { |a| [ a.id, Instances.grade(a, spec) ] }
      grade = grades.fetch(attempt.id) or return Result.new(200, { status: "invalid", message_it: Grading::Result.message("unparseable") })
      tries = ->(list) { list.filter_map { |a| g = grades[a.id] and ServeTry.new(a.try_number, as_answered(g, a)) } }
      events = serve.events.sort_by(&:id).map { |e| serve_event(e) }
      hints_total = Instances.hints(instance).size
      at = attempt.answered_at
      before = ServeState.call(serve: serve, tries: tries.(upto[0...-1]), events: events.select { |e| e.at < at }, hints_total: hints_total, now: at)
      after = ServeState.call(serve: serve, tries: tries.(upto), events: events.select { |e| e.at <= at }, hints_total: hints_total, now: at)
      made = events.select { |e| e.at == at }
      body = graded_body(instance, spec, grade, attempt, before, after, made)
      body[:attempt_id] = attempt.id
      body[:skill] = skill_block(serve, attempt)
      body[:actions] = Payload.actions(after)
      body[:hint] = (h = made.find { |e| e.kind == "hint_shown" && e.auto }) ? Payload.hint(instance, h.n) : nil
      body[:solution] = made.any? { |e| e.kind == "solution_shown" && AUTO_SOLUTION_REASONS.include?(e.reason) } ? Payload.solution(instance) : nil
      Result.new(200, body)
    end

    # The outcome the try had when it was answered: a contest comes later and changes the try's outcome for the engine, not this reply.
    def as_answered(grade, attempt)
      grade.contested ? Outcome.call(evidence_key: grade.key, aided: attempt.aided, near: grade.near) : grade.outcome
    end

    def graded_body(instance, spec, grade, attempt, before, after, made)
      outcome = as_answered(grade, attempt)
      closing = case outcome
      when :unrecognised, :form then before.w >= 1
      when :near_miss then after.closed_by == :near_miss
      else false
      end
      code = grade.codes.first
      { status: "graded", outcome: outcome.to_s, try_number: attempt.try_number,
        message_it: Messages.feedback(outcome, typical: code && Instances.message_for(instance, code), violations: grade.violations, closing: closing,
                                    hint: made.any? { |e| e.kind == "hint_shown" && e.auto }, near: grade.near),
        note_it: %i[correct correct_aided].include?(outcome) ? note(spec, grade, attempt.raw) : nil,
        count_it: Messages.rows_line(outcome, grade.rows),
        error_code: outcome == :typical_error ? code : nil }
    end

    # The credit's own note, then (D-339) the full-sentence one: the whole sentence was written where only the words for the blank were asked.
    def note(spec, grade, raw)
      part = full_sentence_part(spec, raw)
      [ Messages.note(grade.key, violations: grade.violations, pair_note: grade.pair_note), part && Messages.full_sentence_note(part) ].compact.join(" ").presence
    end

    # The words written between the frame of the stem's `___` blank, as typed; nil when the answer is not a whole sentence (the grader's own rule).
    def full_sentence_part(spec, raw)
      return nil unless spec.component == "normalized_text" && !(spec.profile.is_a?(Hash) && spec.profile["name"] == "binary")

      Grading::Frame.for_spec(spec)&.part(raw)
    end

    # The skill's state and "perché" after this try, and whether this try changed the state.
    def skill_block(serve, attempt)
      subject = Subject.find_by!(key: serve.skill_key.split(".").first)
      input = Loader.for(@student, subject: subject, now: @clock.now, shown: @shown)
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

    # A serve that is not open takes no answer: a replaced one says so with HTTP 200 (the page asks for the new serve with it, D-377), else 409 closed.
    def refused(status) = status.state == :replaced ? Result.new(200, Payload.replaced) : closed
    def not_found = Result.new(404, { status: "not_found" })
  end
end
