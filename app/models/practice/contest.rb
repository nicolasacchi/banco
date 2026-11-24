module Practice
  # «Per me va bene così» (D-339 «Fai controllare», D-389): the student sends the latest try of a serve, which the engine did not call right, to the teacher. The state machine says
  # when that is allowed (`contest` among the serve's actions: the latest try is a typical error, unrecognised, form or a near miss and not contested yet, on an open serve or one closed wrong, near miss or by the solution he asked for, D-395). One short transaction
  # writes the contest row and the solution event if it was not sent yet. It writes no comment (D-400): the teacher reads the contest in «Contestazioni»
  # (Teacher::GradingReview, the `contested` signal), with his answer in words, and `comment_id` stays nil. A second call answers the same and writes
  # nothing. The grading, the attempt and the past answers are not touched: the try's outcome becomes `contested` because the row exists
  # (Practice::Loader), never by an update.
  #
  #   Practice::Contest.new(student:, course_view:, clock:).call(serve_id:)
  #   # => Result(http:, body:): 200 {status: "contested", message_it:, solution:, actions:} | 409 {status: "not_contestable"} | 404
  class Contest
    Result = AnswerRecorder::Result

    def initialize(student:, course_view:, clock: Diagnosis::Clock.new)
      @student = student
      @view = course_view
      @clock = clock
    end

    def call(serve_id:)
      tries = 0
      begin
        tries += 1
        run(serve_id)
      rescue ActiveRecord::RecordNotUnique
        # the same click arrived twice at once: the other one won, look again (it answers the same)
        tries < 2 ? retry : raise
      end
    end

    private

    def run(serve_id)
      now = @clock.now
      PracticeServe.transaction do
        serve = load(serve_id) or next Result.new(404, { status: "not_found" })
        status = Loader.status_of(serve, now: now, shown: @view.shown_revisions)
        step = ServeState.step(status, :contest)
        next Result.new(409, { status: "not_contestable" }) if step.result == :closed
        next answer(serve, status) if step.result == :noop

        attempt = serve.attempts.max_by(&:try_number)
        PracticeContest.create!(student: @student, practice_serve: serve, practice_attempt: attempt, created_at: now)
        event(serve, "solution_shown", { reason: step.solution_reason }, now) if step.solution_reason
        fresh = load(serve.id)
        answer(fresh, Loader.status_of(fresh, now: now, shown: @view.shown_revisions))
      end
    end

    def load(id)
      PracticeServe.includes(:events, attempts: :gradings, item_instance: { item_revision: :item }).find_by(id: id, student_id: @student.id)
    end

    def answer(serve, status)
      Result.new(200, { status: "contested", message_it: I18n.t("practice.contested"), solution: Payload.solution(serve.item_instance),
                        actions: Payload.actions(status) })
    end

    def event(serve, kind, payload, now)
      PracticeEvent.create!(student: @student, kind: kind, practice_serve: serve, topic_revision_id: serve.topic_revision_id,
                            payload_json: payload.to_json, at: now, created_at: now)
    end
  end
end
