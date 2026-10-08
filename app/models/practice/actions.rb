module Practice
  # The hint and the solution of a practice serve (A8.3 rows 11-15, A8.4, A9.3). One short transaction
  # re-derives the serve state and writes only what the state machine names.
  #
  #   actions = Practice::Actions.new(student:, clock:)
  #   actions.hint(serve_id:, n:)      # => Result(http, body): {n, total, hint_it} | 409 | 422
  #   actions.solution(serve_id:)      # => Result(http, body): {solution, actions} | 409
  class Actions
    Result = AnswerRecorder::Result

    def initialize(student:, clock: Diagnosis::Clock.new)
      @student = student
      @clock = clock
    end

    def hint(serve_id:, n:)
      run(serve_id) do |serve, status, now|
        total = Instances.hints(serve.item_instance).size
        step = ServeState.step(status, :hint, hint_n: n, hints_total: total)
        case step.result
        when :closed then Result.new(409, Payload.closed)
        when :bad_hint then Result.new(422, { status: "bad_hint" })
        else
          event(serve, "hint_shown", { n: n, auto: false }, now) if step.result == :accept
          Result.new(200, Payload.hint(serve.item_instance, n))
        end
      end
    end

    def solution(serve_id:)
      run(serve_id) do |serve, status, now|
        step = ServeState.step(status, :solution_request)
        next Result.new(409, Payload.closed) if step.result == :closed

        event(serve, "solution_shown", { reason: step.solution_reason }, now) if step.result == :accept
        after = Loader.status_of(serve.reload, now: now)
        Result.new(200, { solution: Payload.solution(serve.item_instance), actions: Payload.actions(after) })
      end
    end

    private

    def run(serve_id)
      now = @clock.now
      PracticeServe.transaction do
        serve = PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find_by(id: serve_id, student_id: @student.id)
        next Result.new(404, { status: "not_found" }) unless serve

        yield serve, Loader.status_of(serve, now: now), now
      end
    end

    def event(serve, kind, payload, now)
      PracticeEvent.create!(student: @student, kind: kind, practice_serve: serve, topic_revision_id: serve.topic_revision_id,
                            payload_json: payload.to_json, at: now, created_at: now)
    end
  end
end
