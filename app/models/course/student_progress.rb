module Course
  # What one student sees of their progress (D-328), for GET /api/v1/students/:key/progress: per subject the topics of
  # the programme and the extra ones with their status (done, in_progress, todo), the counts of skills by state, the
  # skill states, and for every subject with an entry test its state in the student's list. It reads
  # Course::StudentView (what the course pages read) and Diagnosis::Availability (the list of the diagnosis); no query of
  # its own, nothing written.
  class StudentProgress
    def initialize(student, now: Time.current)
      @student = student
      @view = StudentView.new(student, now: now)
    end

    def as_json(*)
      { student: { key: @student.key, official: @student.official? }, subjects: course_subjects, closed_subjects: @view.closed_subjects.map { |sv| { key: sv.subject.key, name_it: sv.subject.name_it } },
        entry_tests: entry_tests }
    end

    private

    def course_subjects
      @view.subjects.map do |sv|
        programme = @view.programme_topics(sv)
        extra = @view.extra_topics(sv)
        {
          key: sv.subject.key, name_it: sv.subject.name_it, released: sv.released, mode: sv.mode, course_revision_id: sv.course_revision.id,
          topics: programme.map { |t| topic(t) }, extra_topics: extra.map { |t| topic(t) },
          topic_counts: tally(programme), skill_counts: @view.counts(sv),
          skills: skills_of(sv), skills_without_topic: @view.skills_without_topic(sv)
        }
      end
    end

    def topic(topic)
      { key: topic.key, kind: topic.kind, title_it: topic.title_it, term: topic.term, minutes: topic.minutes, skills: topic.skills, after: topic.after,
        status: @view.status(topic).to_s, lesson_read: @view.lesson_read?(topic), to_recover: @view.recover_tag?(topic), approved: topic.approved }
    end

    def tally(topics)
      counts = topics.map { |t| @view.status(t).to_s }.tally
      { done: counts["done"].to_i, in_progress: counts["in_progress"].to_i, todo: counts["todo"].to_i, total: topics.size }
    end

    # The state of every skill of the visible topics of the subject (programme and extra), in the order of the topics.
    def skills_of(sv)
      sv.topics.flat_map(&:skills).uniq.map do |key|
        state = @view.state(key)
        { key: key, label_it: @view.label(key), state: state&.state || "not_seen", since: state&.since&.utc&.iso8601 }
      end
    end

    def entry_tests
      Diagnosis::Availability.for(@student).map do |row|
        { subject: row.subject.key, name_it: row.subject.name_it, status: row.status, done: row.done, startable: row.startable, suggested: row.suggested,
          label_it: I18n.t(row.label_key, **row.label_args), run_id: row.run_id }
      end
    end
  end
end
