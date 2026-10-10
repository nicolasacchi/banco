module Teacher
  # One topic as the teacher approves it (A10): the latest and the approved topic revision, the lesson, its
  # review, and per skill the pinned items with four sample instances each. Read-only; opening the page is
  # recorded by the controller (teacher_viewed_topic), approving is a decision.
  class TopicReview
    SkillBlock = Data.define(:skill, :label_it, :cards)
    # One exercise of the guided review: the card, the level, one line on what it trains, the four samples with what the
    # student's templates draw, and whether the teacher has seen it.
    Exercise = Data.define(:card, :skill, :skill_label, :level, :purpose_it, :samples, :seen)
    Sample = Data.define(:view, :presentation)
    Check = Data.define(:name, :done, :reasons)
    CHECK_GROUPS = { map: /not in the latest course map/, versions: /pinned lesson revision|no longer the newest passed/,
                     lesson: /no review by an independent|sent the lesson revision back/, exercises: /is not approvable/, viewed: /was not opened/, render: /render check/ }.freeze
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

    # The one line of the render check of a lesson/2 revision (D-249), or nil for lesson/1.
    def render_line = lesson_revision&.lesson2? ? LessonRenders.teacher_line(lesson_revision) : nil

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

    # ---- the guided review (D-241)

    def lesson_read? = TopicSeen.lesson_read?(latest)
    def seen_ids = @seen_ids ||= TopicSeen.seen_item_ids(latest)

    # The exercises in level order (then in the order of the topic's skills).
    def exercises
      @exercises ||= begin
        order = skill_blocks.each_with_index.to_h { |b, i| [ b.skill, i ] }
        flat = skill_blocks.flat_map { |b| b.cards.map { |c| [ b, c ] } }
        flat.sort_by { |b, c| [ c.body["level"].to_i, order[b.skill], c.revision.id ] }.map { |b, c| build_exercise(b, c) }
      end
    end

    def exercises_seen? = exercises.all?(&:seen)

    def build_exercise(block, card)
      rows = card.revision.instances.sort_by(&:id).first(ItemCard::SAMPLES)
      samples = card.samples.zip(rows).map { |view, row| Sample.new(view, StoredPresentation.call(row, card.revision)) }
      purpose = I18n.t("teacher.path.exercise.purpose", skill: block.label_it, component: Refs.component_name(card.body["component"] || card.body["kind"]),
                                                        errors: ItemCard.catalogue_of(card.body).size)
      Exercise.new(card, block.skill, block.label_it, card.body["level"].to_i, purpose, samples, seen_ids.include?(card.revision.id))
    end

    # Every finding to read: the lesson reviews' and each item's (with the third reviewer's opinions).
    def lesson_findings = reviews.flat_map(&:findings)
    def item_cards = skill_blocks.flat_map(&:cards)
    def cards_with_findings = item_cards.select { |c| c.findings.any? }
    def findings_count = lesson_findings.size + item_cards.sum { |c| c.findings.size }

    # Nothing blocks: every blocker and major finding of an item is dismissed by the teacher, and the lesson was not sent back.
    def findings_clear?
      !lesson_sent_back? && item_cards.all? { |c| c.findings.reject { |f| f.finding.severity == "minor" }.all? { |f| f.disposition == "dismissed" } }
    end

    # The gate's reasons grouped into the lines of the checklist of the last step.
    def checks
      @checks ||= CHECK_GROUPS.reject { |name, _| name == :render && !lesson_revision&.lesson2? }.map do |name, pattern|
        reasons = gate.reasons.select { |r| pattern.match?(r) }
        Check.new(name, reasons.empty?, reasons)
      end
    end

    def other_reasons = gate.reasons.reject { |r| CHECK_GROUPS.values.any? { |p| p.match?(r) } }

    def steps_done
      { lesson: lesson_read?, exercises: exercises_seen?, findings: findings_clear?, approve: approved_latest? }
    end

    # The next topic of the path that waits for the teacher, after this one: a CourseReview step, or nil.
    def next_ready
      @next_ready ||= Teacher::CourseReview.new(subject).steps.find { |st| st.ready? && st.entry["key"] != key }
    end
  end
end
