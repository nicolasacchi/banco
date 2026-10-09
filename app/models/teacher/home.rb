module Teacher
  # The teacher's first page (C-04): each subject with its stage, its counts, what waits
  # for the teacher and the minutes spent so far. Read-only.
  class Home
    def initialize(student: Student.official)
      @student = student
    end

    Row = Data.define(:subject, :stage, :items, :waiting, :minutes, :has_graph, :has_blueprint, :course, :clear, :blocked)
    # The course line of a subject (A10): topics approved against the topics of the map, and whether it is open.
    # awaiting: topics the teacher may approve; in_review: topics the agents still work on; missing: topics not written.
    CourseLine = Data.define(:approved, :total, :open, :awaiting, :in_review, :missing)

    def rows
      @rows ||= Subject.order(:position).map { |s| row(s) }
    end

    def corrections = corrections_by_subject.values.sum

    # {Subject => answers that wait for the teacher in it} (the evening screen's list).
    def corrections_by_subject
      @corrections_by_subject ||= Corrections.call(student: @student).then { |c| (c.short_answers.map(&:subject) + c.verdicts.map(&:subject)).tally }
    end

    def minutes = @minutes ||= Minutes.summary

    def consent_recorded? = Decision.exists?(kind: "record_consent")

    def released? = Diagnosis::Release.open?

    # How many subjects wait for the teacher in some way.
    def waiting_total = rows.count { |r| r.waiting.any? }

    private

    # waiting: [[code, count-or-nil], ...] in the order the teacher should take them.
    def row(subject)
      info = SubjectStage.for(subject)
      graph = SkillGraphRevision.where(subject: subject).order(:seq).last
      blueprint = BlueprintRevision.where(subject: subject).order(:seq).last
      waiting = []
      waiting << [ :graph_to_approve, nil ] if graph && info[:graph][:approved_revision_id] != graph.id
      review = blueprint && TestReview.new(subject)
      findings = review ? review.open_finding_list.size : undisposed_without_blueprint(subject)
      waiting << [ :findings, findings ] if findings.positive?
      sent = info[:items][:sent_back]
      waiting << [ :sent_back, sent ] if sent.positive?
      pending_test = blueprint && info[:blueprint][:approved_revision_id] != blueprint.id
      gate = pending_test ? Approval::BlueprintGate.check(blueprint) : nil
      waiting << [ :test_to_approve, nil ] if gate&.approvable
      Row.new(subject, info[:stage], info[:items], waiting, minutes[:by_subject][subject.key].to_i, !graph.nil?, !blueprint.nil?, course_line(subject),
              review ? review.clear_open_list.size : 0, blocked_reason(info[:stage], gate))
    end

    # One short reason why a test that only waits for the teacher cannot be approved yet, in Italian; nil otherwise.
    # The findings the teacher has not decided are the "findings" line, not a reason of their own.
    def blocked_reason(stage, gate)
      return nil unless stage == "awaiting_teacher" && gate && !gate.approvable

      reasons = gate.reasons.reject { |r| r.include?("without the teacher's disposition") }
      reasons.first && Wording.italian(reasons.first)
    end

    def course_line(subject)
      rows = Course::TopicStage.rows(subject) or return nil
      approved = rows.values.count { |r| %w[approved approved_newer_pending].include?(r.stage) }
      stages = rows.values.map(&:stage).tally
      CourseLine.new(approved, rows.size, !Course::State.released_revision_id(subject).nil?, stages["awaiting_teacher"].to_i, stages["in_review"].to_i, stages["missing"].to_i)
    end

    # Blocker and major findings the teacher has not decided, with no blueprint yet (with one, the
    # list is the test overview's, the pinned revisions): the latest revision of each item that is
    # not a reserve item (D-125), shown without a link.
    def undisposed_without_blueprint(subject)
      latest = Item.diagnosis.where(subject: subject).where.not(id: Item.reserve(subject).select(:id)).includes(:revisions).filter_map { |i| i.revisions.max_by(&:seq)&.id }
      dispositions = ReviewFinding.dispositions
      ReviewFinding.must_be_disposed.where(item_revision_id: latest).count { |f| !dispositions.key?(f.id) }
    end
  end
end
