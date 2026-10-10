module Approval
  # The mechanical half of approving a topic revision (A6.1): approve_topic is possible only when
  #
  #   1. the topic is in the subject's latest course map with the same skills,
  #   2. nothing pinned is stale: the lesson revision is the newest of its lesson and each item
  #      revision is the newest passed revision of its item,
  #   3. the lesson revision has a review by an independent session and the teacher did not send it back,
  #   4. every pinned item revision passes Review::Gate,
  #   5. the teacher opened the topic review page of this very revision (app_event teacher_viewed_topic),
  #   6. the teacher confirmed reading the lesson and the sample instances (confirm_seen), and
  #   7. when the latest review of the lesson revision has blocker or major findings, the teacher gave a
  #      reason for approving anyway (3..1000 chars).
  #
  # Nothing here decides: it says what is still missing, in the teacher's words (Teacher::Wording).
  # Reasons 6 and 7 come from the form, so the page asks for reasons 1-5 with .mechanical.
  module TopicGate
    Result = Struct.new(:approvable, :reasons, keyword_init: true) do
      def to_h = { approvable: approvable, reasons: reasons }
    end

    REASON_RANGE = (3..1000)
    VIEW_KIND = "teacher_viewed_topic".freeze
    CONFIRM = "the teacher did not confirm reading the lesson and the sample instances".freeze
    LESSON2_PAGES = "the lesson is banco.lesson/2 and the lesson pages cannot show it yet".freeze
    REASON_NEEDED = "a reason is required to approve despite the blocker or major findings of the lesson review".freeze

    module_function

    def check(revision, confirm_seen: false, lesson_findings_reason_it: nil)
      reasons = mechanical_reasons(revision)
      reasons << CONFIRM unless confirm_seen
      if findings_need_reason?(revision)
        text = lesson_findings_reason_it.to_s.strip
        reasons << REASON_NEEDED unless REASON_RANGE.cover?(text.length)
      end
      Result.new(approvable: reasons.empty?, reasons: reasons)
    end

    # Reasons 1 to 5: what the page shows before the teacher confirms.
    def mechanical(revision)
      reasons = mechanical_reasons(revision)
      Result.new(approvable: reasons.empty?, reasons: reasons)
    end

    def mechanical_reasons(revision)
      reasons = []
      subject = revision.lesson.subject
      entry = map_entry(subject, revision.lesson.key)
      if entry.nil? || entry["skills"].sort != Course::Catalog.skills_of(revision)
        reasons << "the topic #{revision.lesson.key} is not in the latest course map of #{subject.key} with the same skills"
      end
      stale, lesson_pin = Course::TopicStage.stale_pins(revision)
      reasons << "the pinned lesson revision #{lesson_pin[:pinned]} is not the newest revision of its lesson (#{lesson_pin[:latest]})" if lesson_pin[:pinned] != lesson_pin[:latest]
      stale.each { |pin| reasons << "item revision #{pin[:pinned]} is no longer the newest passed revision of its item: #{pin[:newest_passed]} replaced it" }
      lesson_revision = revision.lesson_revision
      reasons << "the lesson revision has no review by an independent session" unless lesson_revision.reviews.exists?
      reasons << "the teacher sent the lesson revision back" if Course::Decisions.lesson_sent_back?(lesson_revision)
      # R1 guard: the lesson pages do not read banco.lesson/2 yet (R2 switches them to Lessons::StudentBody); remove this line then.
      reasons << LESSON2_PAGES if lesson_revision.body["schema"] == "banco.lesson/2"
      ItemRevision.where(id: item_revision_ids(revision)).order(:id).each do |item_revision|
        gate = Review::Gate.check(item_revision)
        reasons << "item revision #{item_revision.id} is not approvable: #{gate.reasons.join('; ')}" unless gate.approvable
      end
      reasons << "the topic review page of revision #{revision.id} was not opened" unless viewed?(revision)
      reasons
    end

    def item_revision_ids(revision) = revision.body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } }

    def map_entry(subject, key)
      course = CourseRevision.where(subject: subject).order(:seq).last or return nil
      course.body["topics"].find { |t| t["key"] == key }
    end

    # The latest review of the lesson revision (the one the teacher reads) has a blocker or major finding.
    def findings_need_reason?(revision)
      review = revision.lesson_revision.reviews.max_by(&:id) or return false
      review.findings.any? { |f| %w[blocker major].include?(f["severity"]) }
    end

    def viewed?(revision)
      AppEvent.where(kind: VIEW_KIND).where("json_extract(payload_json, '$.topic_revision_id') = ?", revision.id).exists?
    end
  end
end
