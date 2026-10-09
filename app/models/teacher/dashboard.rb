module Teacher
  # The teacher's first page as a dashboard (D-240): "Da fare adesso", the teacher's pending actions across all
  # subjects with the most blocking first, and one row per subject. It reads Teacher::Home (the same numbers as
  # the pages behind it) and adds nothing of its own to the business rules. Read-only.
  class Dashboard
    # One line of "Da fare adesso". kind is the locale key under teacher.dashboard.todo; subject is nil for
    # the lines about the whole system. extra: the "di cui M con un parere chiaro" count and the link to the bulk section.
    Todo = Data.define(:kind, :subject, :count, :href, :extra, :extra_href, :reason)
    # What one student did in one subject: the diagnosis line (official student only), the last activity, the
    # skills the student practised.
    StudentCell = Data.define(:student, :diagnosis, :last_at, :practised)
    Release = Data.define(:approved, :total, :consent, :warmup, :open)

    # Seconds between two polls of the open page; the test sets it short.
    def self.poll_seconds = ENV.fetch("BANCO_DASHBOARD_POLL", "20").to_i.clamp(1, 600)

    attr_reader :home, :student

    def initialize(student: Student.official)
      @student = student
      @home = Home.new(student: student)
    end

    def rows = home.rows

    def students = @students ||= Student.real

    def release
      @release ||= begin
        subjects = Subject.order(:position).to_a
        official = Student.official
        Release.new(subjects.count { |s| SubjectStage.approved_graph(s) && SubjectStage.approved_blueprint(s) }, subjects.size,
                    home.consent_recorded?, !official.nil? && Diagnosis::Warmup.complete?(official), home.released?)
      end
    end

    # The pending actions, most blocking first: findings, graphs, tests ready, tests blocked, topics, corrections, release.
    def todos
      @todos ||= [ findings, graphs, tests_ready, tests_blocked, topics, corrections, release_line ].flatten
    end

    # The cell of one student in one subject (D-217 student list).
    def cell(student, subject)
      cells[student.id].fetch(subject.id)
    end

    private

    def findings
      rows.filter_map do |r|
        n = r.waiting.to_h[:findings].to_i
        next unless n.positive?

        test = r.has_blueprint
        Todo.new(:findings, r.subject, n, test ? href(:teacher_test_path, r, "#open-findings") : nil,
                 r.clear.positive? ? r.clear : nil, r.clear.positive? ? href(:teacher_test_path, r, "#follow-opinions-form") : nil, nil)
      end
    end

    def graphs = rows.select { |r| r.waiting.to_h.key?(:graph_to_approve) }.map { |r| Todo.new(:graph, r.subject, nil, href(:teacher_graph_path, r), nil, nil, nil) }

    def tests_ready = rows.select { |r| r.waiting.to_h.key?(:test_to_approve) }.map { |r| Todo.new(:test_ready, r.subject, nil, href(:teacher_test_path, r), nil, nil, nil) }

    def tests_blocked = rows.select(&:blocked).map { |r| Todo.new(:test_blocked, r.subject, nil, href(:teacher_test_path, r), nil, nil, r.blocked) }

    def topics
      rows.select { |r| r.course&.awaiting.to_i.positive? }.map { |r| Todo.new(:topics, r.subject, r.course.awaiting, href(:teacher_course_path, r), nil, nil, nil) }
    end

    def corrections
      home.corrections_by_subject.sort_by { |s, _| s.position.to_i }.map { |s, n| Todo.new(:corrections, s, n, with_student("/teacher/corrections"), nil, nil, nil) }
    end

    # Only when it is the teacher's turn: every subject is approved and the diagnosis is not open yet.
    def release_line
      return [] if release.open || release.approved < release.total || release.total.zero?

      [ Todo.new(:release, nil, nil, "#release-state", nil, nil, release_missing) ]
    end

    def release_missing = [ (:consent unless release.consent), (:warmup unless release.warmup) ].compact

    def href(helper, row, anchor = "")
      Rails.application.routes.url_helpers.public_send(helper, key: row.subject.key) + anchor
    end

    def with_student(path) = student && !student.official? ? "#{path}?#{{ student: student.key }.to_query}" : path

    # {student id => {subject id => StudentCell}}, a few grouped queries per student.
    def subject_ids = @subject_ids ||= Subject.pluck(:id)

    def cells
      @cells ||= students.to_h do |s|
        diagnosis = s.official? ? diagnosis_lines(s) : {}
        last = last_activity(s)
        practised = PracticeServe.where(student: s).joins(topic_revision: :lesson).group("lessons.subject_id").distinct.count(:skill_key)
        [ s.id, subject_ids.to_h { |id| [ id, StudentCell.new(s, diagnosis[id], last[id], practised[id].to_i) ] } ]
      end
    end

    def diagnosis_lines(student)
      Diagnosis::Availability.for(student).to_h { |r| [ r.subject.id, I18n.t(r.label_key, **r.label_args) ] }
    end

    def last_activity(student)
      found = []
      found << DiagnosisEvent.joins(:diagnosis_run).where(diagnosis_runs: { student_id: student.id }).group("diagnosis_runs.subject_id").maximum(:at)
      found << PracticeServe.where(student: student).joins(topic_revision: :lesson).group("lessons.subject_id").maximum(:created_at)
      found << PracticeAttempt.where(student: student).joins(practice_serve: { topic_revision: :lesson }).group("lessons.subject_id").maximum(:answered_at)
      found.each_with_object({}) do |h, out|
        h.each do |subject_id, at|
          at = Time.zone.parse(at.to_s) unless at.respond_to?(:utc)
          out[subject_id] = at if at && (out[subject_id].nil? || at > out[subject_id])
        end
      end
    end
  end
end
