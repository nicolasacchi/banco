module Practice
  # «Per me va bene così» (D-339 «Fai controllare», D-389): the student sends the latest try of a serve, which the engine did not call right, to the teacher. The state machine says
  # when that is allowed (`contest` among the serve's actions: the latest try is a typical error, unrecognised, form or a near miss and not contested yet, on an open serve or one closed wrong, near miss or by the solution he asked for, D-395). One short transaction
  # writes the contest row, the comment the teacher reads (through Comments::Intake, like any comment of the student: reason `error`, the practice
  # page, anchored to the exercise's answer, the serve as its ref) and the solution event if it was not sent yet. A second call answers the same
  # and writes nothing. The teacher's preview writes the contest for the preview student and no comment (D-309). The grading, the attempt and
  # the past answers are not touched: the try's outcome becomes `contested` because the row exists (Practice::Loader), never by an update.
  #
  #   Practice::Contest.new(student:, course_view:, clock:).call(serve_id:)
  #   # => Result(http:, body:): 200 {status: "contested", message_it:, solution:, actions:} | 409 {status: "not_contestable"} | 404
  class Contest
    Result = AnswerRecorder::Result

    COMMENT_ANCHOR = "exercise/item/answer".freeze
    CUT = "…".freeze

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

    # D-395: all of his answer that the comment can hold (Comment::TEXT_MAX less the template). If it is still too long it is cut at the
    # last «; » (a whole pair of a matching, a whole item) and ends with «…»; an answer with no «; » is cut at the limit. Shared with the
    # lesson checks' contest (D-396).
    def self.fit(words)
      room = Comment::TEXT_MAX - I18n.t("practice.contest_comment", raw: "", locale: :it).length
      return words if words.length <= room

      head = words.first(room - CUT.length)
      cut = head.rindex("; ")
      "#{cut ? head.first(cut) : head}#{CUT}"
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
        PracticeContest.create!(student: @student, practice_serve: serve, practice_attempt: attempt, comment: comment_for(serve, attempt), created_at: now)
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
                        actions: Payload.actions(status), **Payload.passage(serve.item_instance) })
    end

    # The teacher's comment, written as the student's own comment would be; nil in the preview, which never writes one.
    def comment_for(serve, attempt)
      return nil unless @student.kind == "student"

      result = Comments::Intake.call(
        student: @student, course_view: @view,
        params: { client_comment_id: "contest-#{attempt.id}", reason: "error", text_it: comment_text(serve, attempt), # the teacher reads it: Italian, whatever the student's page speaks (D-356)
                  page_path: "/topics/#{serve.topic_revision.lesson.key}/practice/#{serve.skill_key}", anchor: COMMENT_ANCHOR,
                  refs: { "serve_id" => serve.id } }
      )
      raise "the contest's comment was refused: #{result.error}" unless result.status == :recorded

      result.comment
    end

    # The comment's words (D-387): his answer in the texts he read, never the code it travels as; without the answer when the words cannot be built.
    def comment_text(serve, attempt)
      words = answer_words(serve, attempt)
      return I18n.t("practice.contest_comment_bare", locale: :it) unless words

      I18n.t("practice.contest_comment", raw: words, locale: :it)
    end

    # Diagnosis::AnswerText (the reader of the teacher's pages, Teacher::AnswerWords): a matching is «riga – scelta; riga – scelta», a choice its option
    # text, an ordering its items in his order, a typed answer as typed. nil when the answer does not read as that exercise's, or when the reader
    # fell back to the stored code of a structured answer.
    def answer_words(serve, attempt)
      raw = attempt.raw.to_s
      words = squish(Diagnosis::AnswerText.call(attempt, serve))
      return nil if words.empty? || (words == squish(raw) && structured?(serve))

      self.class.fit(words)
    rescue JSON::ParserError, NoMethodError, TypeError
      nil
    end

    def squish(text) = text.to_s.gsub(/[[:space:]]+/, " ").strip

    # A choice, an ordering, a matching, a fraction or a reading test: its stored answer is ids, never words.
    def structured?(serve)
      body = JSON.parse(serve.item_instance.item_revision.body_json)
      body["kind"] == "testlet" || %w[choice ordering matching fraction].include?(body["component"])
    end

    def event(serve, kind, payload, now)
      PracticeEvent.create!(student: @student, kind: kind, practice_serve: serve, topic_revision_id: serve.topic_revision_id,
                            payload_json: payload.to_json, at: now, created_at: now)
    end
  end
end
