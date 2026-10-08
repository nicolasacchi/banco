module Teacher
  # One topic as the teacher approves it (A10): the latest and the approved topic revision, the lesson, its
  # review, and per skill the pinned items with four sample instances each. Read-only; opening the page is
  # recorded by the controller (teacher_viewed_topic), approving is a decision.
  class TopicReview
    SkillBlock = Data.define(:skill, :label_it, :cards)
    ReviewRow = Data.define(:review, :model, :results, :checklist, :recomputed, :findings)

    attr_reader :subject, :lesson, :key

    def initialize(subject, key)
      @subject = subject
      @key = key
      @lesson = Lesson.find_by(subject: subject, key: key)
    end

    def present? = !lesson.nil?
    def entry = @entry ||= Approval::TopicGate.map_entry(subject, key)
    def latest = @latest ||= lesson && lesson.topic_revisions.max_by(&:seq)
    def approved_id = @approved_id ||= Course::Decisions.approved_topic_revision_id(key)
    def approved = approved_id && TopicRevision.find_by(id: approved_id)
    def approved_latest? = !latest.nil? && approved_id == latest.id
    def lesson_revision = latest&.lesson_revision
    def lesson_body = lesson_revision&.body
    def gate = @gate ||= Approval::TopicGate.mechanical(latest)
    def needs_reason? = Approval::TopicGate.findings_need_reason?(latest)
    def intro_it = latest&.body&.dig("intro_it")

    # Whether the teacher can approve now, ignoring the two form inputs (confirmation and reason).
    def approvable? = gate.approvable && !approved_latest?

    def send_backs = @send_backs ||= Course::LessonView.comments(lesson)
    def lesson_sent_back? = Course::Decisions.lesson_sent_back?(lesson_revision)

    def reviews
      @reviews ||= lesson_revision.reviews.includes(:agent_session).order(:id).map do |r|
        ReviewRow.new(r, r.agent_session.model, r.checklist.map { |c| c["result"] }.tally, r.checklist, r.recomputed, r.findings)
      end
    end

    # Blocker and major findings of the review the approval reads.
    def grave_findings = reviews.last ? reviews.last.findings.select { |f| %w[blocker major].include?(f["severity"]) } : []

    def labels
      @labels ||= begin
        course = CourseRevision.where(subject: subject).order(:seq).last
        graph = course && JSON.parse(course.skill_graph_revision.body_json)["skills"]
        (Array(graph) + Array(course&.body&.dig("skills"))).to_h { |s| [ s["key"], s["label_it"] ] }
      end
    end

    # Per skill of the topic revision: the pinned items as cards with four sample instances each.
    def skill_blocks
      @skill_blocks ||= begin
        ids = latest.body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } }
        revisions = ItemCard.load(ids)
        dispositions = ReviewFinding.dispositions
        back = SendBacks.by_revision(ids)
        latest.body["practice"].map do |p|
          cards = p["items"].filter_map { |i| revisions[i["revision"]] }.map { |rev| ItemCard.build(rev, dispositions, back) }
          SkillBlock.new(p["skill"], labels[p["skill"]] || p["skill"], cards)
        end
      end
    end

    def open_findings
      @open_findings ||= begin
        ids = latest.body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } }
        found = ReviewFinding.must_be_disposed.where(item_revision_id: ids).order(:id).reject { |f| ReviewFinding.dispositions.key?(f.id) }
        found.size
      end
    end
  end
end
