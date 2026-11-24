module Course
  # What the student does next, per subject (D-333), for GET /api/v1/students/:key/next and the digest: the topic Oggi
  # proposes first for that subject (Course::StudentView#next_topic: the topic the student left, else the first of Oggi's
  # own ranked suggestions of the subject; programme topics only, never an extra one), the skills the pages call «Da
  # riprendere» (Course::StudentView#skills_to_recover) and the programme tally. No rule of its own, no query of its
  # own, nothing written. A subject whose course was withdrawn is listed with next null.
  class StudentNext
    # subject: a subject key to keep, or nil for every subject of the student's course.
    # view: a StudentView already built for this student (the digest shares one with the progress).
    def initialize(student, subject: nil, now: Time.current, view: nil)
      @student = student
      @subject = subject
      @view = view || StudentView.new(student, now: now)
    end

    def as_json(*)
      { student: @student.key, subjects: subjects.map { |sv| subject_json(sv) } }
    end

    private

    def subjects
      @view.catalog.select { |sv| @subject.nil? || sv.subject.key == @subject }
    end

    def subject_json(sv)
      open = sv.topics.any?
      pick = open ? @view.next_topic(sv) : nil
      { subject: sv.subject.key, name_it: sv.subject.name_it, next: pick && next_json(pick),
        skills_to_recover: open ? @view.skills_to_recover(sv).map { |skill, topic| { skill: skill, label_it: @view.label_italian(skill), taught_in: topic } } : [],
        done_it: open ? done_text(@view.progress(sv).programme) : I18n.t("today.closed") }
    end

    def next_json(pick)
      topic = pick.topic
      { topic: topic.key, title_it: topic.title_it, kind: topic.kind, minutes: topic.minutes, term: topic.term, why_it: why(pick) }
    end

    # Oggi's own words for the reason (course.it.yml today.reason).
    def why(pick)
      return I18n.t("today.reason.#{pick.reason}", skill: @view.label_italian(pick.skill)) if pick.skill

      I18n.t("today.reason.#{pick.reason}")
    end

    def done_text(tally)
      return I18n.t("progress.required_none") if tally.none?

      [ I18n.t("progress.required", count: tally.total), I18n.t("progress.known", count: tally.known), I18n.t("progress.exercises_done", count: tally.exercises) ].join(". ") + "."
    end
  end
end
