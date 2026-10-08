module Course
  # Where a topic of the latest course map stands for the agent (A4): missing, in_review, awaiting_teacher,
  # approved, approved_newer_pending. The agent-side gate reasons are the mechanical half of the teacher's
  # approval; the rest of it (the teacher read the page, the confirmation) is Approval::TopicGate (S4). The
  # agent stops at awaiting_teacher: no command goes further (firm rule 2).
  module TopicStage
    Row = Struct.new(:topic, :stage, :latest, :approved_revision_id, :stale_pins, :lesson_pin, :gate_reasons, keyword_init: true)

    module_function

    # {topic key => Row} for each topic of the subject's latest course map, in map order; nil without a map.
    def rows(subject)
      course = CourseRevision.where(subject: subject).order(:seq).last or return nil
      entries = JSON.parse(course.body_json)["topics"]
      latest = TopicRevision.where(lesson: Lesson.where(key: entries.map { |t| t["key"] })).includes(:lesson).group_by { |r| r.lesson.key }.transform_values { |l| l.max_by(&:seq) }
      entries.to_h { |entry| [ entry["key"], row(entry, latest[entry["key"]]) ] }
    end

    def row(entry, revision)
      return Row.new(topic: entry, stage: "missing", stale_pins: [], gate_reasons: []) unless revision

      stale, lesson_pin = stale_pins(revision)
      reasons = reasons(revision, entry, stale, lesson_pin)
      approved_id = Decisions.approved_topic_revision_id(entry["key"])
      stage =
        if approved_id == revision.id then "approved"
        elsif approved_id then "approved_newer_pending"
        elsif reasons.any? then "in_review"
        else "awaiting_teacher"
        end
      Row.new(topic: entry, stage: stage, latest: revision, approved_revision_id: approved_id, stale_pins: stale, lesson_pin: lesson_pin, gate_reasons: reasons)
    end

    # [pins whose item has a newer passed revision, {pinned:, latest:} of the lesson]
    def stale_pins(revision)
      stale = []
      revision.body["practice"].each do |entry|
        entry["items"].each do |pin|
          item = Item.joins(:revisions).find_by(item_revisions: { id: pin["revision"] }) or next
          newest = item.revisions.includes(:validations).select { |r| r.status == "passed" }.max_by(&:seq)
          stale << { skill: entry["skill"], item: pin["item"], pinned: pin["revision"], newest_passed: newest.id } if newest && newest.id != pin["revision"]
        end
      end
      [ stale, { pinned: revision.lesson_revision_id, latest: revision.lesson.latest_revision.id } ]
    end

    def reasons(revision, entry, stale, lesson_pin)
      out = []
      practice = revision.body["practice"].map { |p| p["skill"] }.sort
      out << "the skills of the topic differ from the course map (#{practice.join(', ')} against #{entry['skills'].sort.join(', ')})" if practice != entry["skills"].sort
      out << "the pinned lesson revision is not the newest (#{lesson_pin[:pinned]}, newest #{lesson_pin[:latest]})" if lesson_pin[:pinned] != lesson_pin[:latest]
      out << "#{stale.size} pinned item revision(s) are not the newest passed revision of their item" if stale.any?
      lesson_revision = revision.lesson_revision
      out << "the lesson revision has no review by an independent session" unless lesson_revision.reviews.exists?
      out << "the teacher sent the lesson revision back" if Decisions.lesson_sent_back?(lesson_revision)
      item_revisions = ItemRevision.where(id: revision.body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } }).includes(:validations, :reviews, :blind_solves)
      out << "#{item_revisions.count { |r| r.status != 'passed' }} pinned item revision(s) have not passed validation" if item_revisions.any? { |r| r.status != "passed" }
      out << "#{item_revisions.count { |r| !Review::Gate.worked?(r) }} pinned item revision(s) lack an expert review or a blind solve" if item_revisions.any? { |r| !Review::Gate.worked?(r) }
      sent = item_revisions.select { |r| Teacher::SendBacks.sent_back?(r) }
      out << "the teacher sent #{sent.size} pinned item revision(s) back" if sent.any?
      out
    end
  end
end
