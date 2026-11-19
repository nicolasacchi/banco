module Comments
  # «In scadenza» (D-371): the threads that wait for the teacher, with the hours left of the promised answer time (D-349), the
  # soonest due first (the late ones, with negative hours, at the top), and which of them are a follow-up of the student after the
  # teacher's last reply. One place for the teacher's inbox and the digest, so both show the same numbers. Read-only.
  module Due
    Row = Struct.new(:comment, :since, :due_in_hours, :late, :followup, keyword_init: true)

    module_function

    # Every comment that waits, whatever the filters of the page; comments: the candidates (the default: all of them), with their events loaded.
    def rows(comments = Comment.includes(:events, :student, :subject).to_a, now: Time.current)
      comments.select(&:waiting_for_teacher?).map do |c|
        Row.new(comment: c, since: c.waiting_since, due_in_hours: c.due_in_hours(now), late: c.late?, followup: c.student_followup?)
      end.sort_by { |r| [ r.due_in_hours, r.comment.id ] }
    end

    # {within_hours, waiting, late, followups, rows: [...]} for the digest: the counts of all, the first `limit` rows.
    def api(limit:, comments: nil, now: Time.current)
      all = comments ? rows(comments, now: now) : rows(now: now)
      { within_hours: ReplyWindow.hours, waiting: all.size, late: all.count(&:late), followups: all.count(&:followup), rows: all.first(limit).map { |r| api_row(r) } }
    end

    def api_row(row)
      c = row.comment
      { id: c.id, state: c.state, student: c.student.key, subject: c.subject&.key, page_kind: c.page_kind, waiting_since: row.since.utc.iso8601,
        due_in_hours: row.due_in_hours, late: row.late, student_followup: row.followup }.compact
    end

    # «5 ore rimaste», «meno di un'ora rimasta», «in ritardo di 6 ore»: for the teacher's page.
    def left_it(row)
      hours = row.due_in_hours
      return I18n.t("teacher.comments.due.late_by", span: ReplyWindow.span_it(-hours * 3600)) if hours.negative?
      return I18n.t("teacher.comments.due.under_hour") if hours < 1

      I18n.t("teacher.comments.due.left", count: hours.floor)
    end
  end
end
