module Teacher
  # The answers that wait for the teacher's word, as lines of plain text for the operator's console
  # (bin/rails banco:answers:pending, D-317): undetermined answers (an unreadable one, a grader that
  # could not decide) and short answers, each with the run, the item, the stem of the instance, the
  # key, what S typed and the attempt id to pass to banco:decide KIND=resolve_attempt.
  # Read-only. The same rows as the corrections page; no route, no API and no CLI command reach it.
  class PendingAnswers
    Entry = Data.define(:attempt_id, :run_id, :subject_key, :item_key, :stem, :key, :given, :kind, :note, :proposal_id)

    def self.call(student: Student.official, subject: nil) = new(student, subject).entries

    def initialize(student, subject)
      @student = student
      @subject = subject.presence
      @corrections = Corrections.call(student: student)
    end

    def entries
      list = @corrections.verdicts.map { |v| verdict_entry(v) } + @corrections.short_answers.map { |s| short_entry(s) }
      list = list.select { |e| e.subject_key == @subject } if @subject
      list.sort_by(&:attempt_id)
    end

    # The text of one entry, one block per answer.
    def self.lines(entry)
      cmd = if entry.kind == "short_answer"
        if entry.proposal_id
          %(bin/rails banco:decide KIND=confirm_grade TEACHER=<login> PARAMS='{"grade_proposal_id":#{entry.proposal_id}}'  ) +
            %((to edit the scores add "scores":{"POINT_ID":N,...} and REASON="..."; KIND=reject_grade takes REASON="..."))
        else
          "no grade proposal yet: wait for the agent's proposal, then confirm it here or on the corrections page"
        end
      else
        %(bin/rails banco:decide KIND=resolve_attempt TEACHER=<login> REASON="..." PARAMS='{"attempt_id":#{entry.attempt_id},"verdict":"correct|wrong|dont_know"}')
      end
      [ "attempt #{entry.attempt_id} · run #{entry.run_id} · #{entry.subject_key} · #{entry.item_key}#{" · #{entry.note}" if entry.note}",
        "  stem:  #{entry.stem.to_s.squish.first(300)}",
        "  key:   #{entry.key}",
        "  typed: #{entry.given.to_s.squish.first(300)}",
        "  to decide: #{cmd}" ]
    end

    private

    def run_of(attempt) = DiagnosisEvent.find_by(id: attempt.served_event_id)&.diagnosis_run_id

    def verdict_entry(v)
      Entry.new(v.attempt.id, run_of(v.attempt), v.subject.key, v.item_key, v.prompt, v.key, v.given, "verdict",
                v.unreadable ? "unreadable by the program#{" (#{v.unreadable_note})" if v.unreadable_note}" : v.verdict, nil)
    end

    def short_entry(s)
      Entry.new(s.attempt.id, run_of(s.attempt), s.subject.key, s.item_key, s.prompt, s.model_answer_it, s.attempt.raw, "short_answer", "short answer", s.proposal&.id)
    end
  end
end
