module Teacher
  # The teacher's first page (C-04): each subject with its stage, its counts, what waits
  # for the teacher and the minutes spent so far. Read-only.
  class Home
    def initialize(student: Student.official)
      @student = student
    end

    Row = Data.define(:subject, :stage, :items, :waiting, :minutes, :has_graph, :has_blueprint)

    def rows
      @rows ||= Subject.order(:position).map { |s| row(s) }
    end

    def corrections = @corrections ||= Corrections.call(student: @student).count

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
      findings = undisposed(subject, blueprint)
      waiting << [ :findings, findings ] if findings.positive?
      sent = info[:items][:sent_back]
      waiting << [ :sent_back, sent ] if sent.positive?
      waiting << [ :test_to_approve, nil ] if blueprint && info[:blueprint][:approved_revision_id] != blueprint.id && Approval::BlueprintGate.approvable?(blueprint)
      Row.new(subject, info[:stage], info[:items], waiting, minutes[:by_subject][subject.key].to_i, !graph.nil?, !blueprint.nil?)
    end

    # Blocker and major findings the teacher has not decided. With a blueprint: the same list as
    # the test overview (the pinned revisions). Without one: the latest revision of each item
    # that is not a reserve item (D-125), shown without a link.
    def undisposed(subject, blueprint)
      return TestReview.new(subject).open_finding_list.size if blueprint

      latest = Item.diagnosis.where(subject: subject).where.not(id: Item.reserve(subject).select(:id)).includes(:revisions).filter_map { |i| i.revisions.max_by(&:seq)&.id }
      dispositions = ReviewFinding.dispositions
      ReviewFinding.must_be_disposed.where(item_revision_id: latest).count { |f| !dispositions.key?(f.id) }
    end
  end
end
