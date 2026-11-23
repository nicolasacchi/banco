# frozen_string_literal: true

module Lessons
  # «Per me va bene così» on a check of a lesson/2 (D-396, as D-389 has it in practice): the student sends the answer he gave last to an inline check, a
  # faded example's blank or an exercise of «Prova tu», which the grader called wrong, to the teacher. One short transaction writes the comment the
  # teacher reads (through Comments::Intake, like any comment of the student: reason `error`, the lesson page, anchored on the block, the practice
  # contest's wording with his answer in the texts he read) and the lesson event `check_contested` that says which answer it was. A second press of the
  # same answer writes nothing and answers the same. The grading, the check_answered rows and every skill are not touched: the check is practice for his
  # head, and a contest is the one thing that reaches the teacher. The check then shows what a finished one shows (the explanation, the rest of a faded
  # example). The teacher's preview has no route, so it never gets here.
  #
  #   Lessons::CheckContest.new(revision, student:, topic_revision:, course_view:).call(locator)   # locator as Lessons::CheckAnswer's
  #   # => Lessons::CheckAnswer::Reply: 200 {status: "contested", explain_it?, model_it?, steps?...} | 409 {status: "not_contestable"} | 404 {status: "not_found"}
  class CheckContest
    Reply = CheckAnswer::Reply
    TEXT_KEYS = Blocks::Check::TEXT_KEYS

    def initialize(revision, student:, topic_revision:, course_view:)
      @revision = revision
      @student = student
      @topic_revision = topic_revision
      @view = course_view
      @answer = CheckAnswer.new(revision, student_key: student.key, student: student, topic_revision: topic_revision)
    end

    def call(locator)
      located = @answer.located(locator) or return Reply.new(404, { status: "not_found" })
      last = @answer.answers(locator).last
      # before the first try there is nothing to send, and a right answer needs no teacher
      return Reply.new(409, { status: "not_contestable" }) unless last && last.payload["verdict"] == "wrong"

      tries = 0
      begin
        tries += 1
        contest(locator, located, last)
      rescue ActiveRecord::RecordNotUnique
        # the same press arrived twice at once: the other one won, look again (it answers the same)
        tries < 2 ? retry : raise
      end
      Reply.new(200, { status: "contested" }.merge(@answer.revealed(locator)))
    end

    private

    def contest(locator, located, last)
      return if LessonEvent.exists?(student: @student, client_event_id: "contest-#{last.id}")

      LessonEvent.transaction do
        comment = comment_for(locator, located, last)
        now = Time.current
        key = locator.slice(:step, :ex, :part).compact.transform_keys(&:to_s)
        LessonEvent.create!(student: @student, topic_revision: @topic_revision, lesson_revision: @revision, kind: "check_contested", card: locator[:card], block: locator[:block],
                            payload_json: JSON.generate({ of: last.id, try: last.payload["try"], comment_id: comment.id }.merge(key)),
                            client_event_id: "contest-#{last.id}", at: now, created_at: now)
      end
    end

    def comment_for(locator, located, last)
      result = Comments::Intake.call(
        student: @student, course_view: @view,
        params: { client_comment_id: "lesson-contest-#{last.id}", reason: "error", text_it: comment_text(located, last.payload["response"]), # the teacher reads it: Italian (D-356)
                  page_path: "/topics/#{@topic_revision.lesson.key}/lesson", anchor: anchor(locator), refs: { "lesson_revision_id" => @revision.id } }
      )
      raise "the contest's comment was refused: #{result.error}" unless result.status == :recorded

      result.comment
    end

    # The block (D-396: «anchored on that block»), and in «Prova tu» or a faded example the exercise, the part or the step, so that two contests of
    # the same words on two exercises within two minutes are two comments (Comments::Intake's repeat window, D-388).
    def anchor(locator)
      segments = [ "card:#{locator[:card]}", "block:#{locator[:block]}" ]
      segments << "exercise:#{locator[:ex]}" if locator[:ex]
      segments << "part:#{locator[:part]}" if locator[:part]
      segments << "step:#{locator[:step]}" if locator[:step]
      segments.join("/")
    end

    # The practice contest's wording (D-387, `practice.contest_comment`) with his answer in the texts he read, never the code it travelled as; without
    # the answer when the words cannot be built.
    def comment_text(located, response)
      words = answer_words(located, response)
      return I18n.t("practice.contest_comment_bare", locale: :it) unless words

      I18n.t("practice.contest_comment", raw: words, locale: :it)
    end

    def answer_words(located, response)
      check = located.check
      response = Checks.structured(check, response)
      words =
        case check["component"]
        when "choice" then option_text(shown(check, located, "options"), response)
        when "matching" then matching(check, located, response)
        when "span_select" then spans(check, response)
        when "tiles", "ordering" then sequence(check, located, response)
        when "select" then select(check, located, response)
        when "fraction" then Diagnosis::AnswerText.fraction(response.is_a?(Hash) ? response : {})
        else response.is_a?(String) ? response : nil # number, normalized_text: as typed
        end
      words = words.to_s.gsub(/[[:space:]]+/, " ").strip
      words.empty? ? nil : Practice::Contest.fit(words)
    end

    def shown(check, located, column) = Checks.rekey(check, located.seed).display.fetch(column) { [] }

    def text_of(entry) = entry && TEXT_KEYS.filter_map { |k| entry[k] }.first

    def option_text(list, id) = text_of(Array(list).find { |e| e["id"] == id.to_s })

    def matching(check, located, response)
      return nil unless response.is_a?(Hash)

      display = Checks.rekey(check, located.seed).display
      response.map { |l, r| "#{option_text(display['left'], l) || l} – #{option_text(display['right'], r) || r}" }.join("; ")
    end

    def spans(check, response)
      return nil unless response.is_a?(Array)

      ids = check["spans"].each_with_index.to_h { |s, i| [ "s#{i + 1}", s ] }
      response.map { |id| text_of(ids[id]) || id }.join(", ")
    end

    def sequence(check, located, response)
      return nil unless response.is_a?(Array)

      list = shown(check, located, "elements")
      joiner = check["component"] == "tiles" ? " " : " → " # the tiles read as the line he built (the page's own sentence), an ordering as Diagnosis::AnswerText has it
      response.map { |id| option_text(list, id) || id }.join(joiner)
    end

    def select(check, located, response)
      return nil unless response.is_a?(Array)

      map = Checks.id_map(check, located.seed)
      SelectTargets.names(check, response.map { |id| map.fetch(id.to_s, id.to_s) }).join(", ")
    end
  end
end
