module Approval
  # The mechanical half of approving a topic revision (A6.1): approve_topic is possible only when
  #
  #   1. the topic is in the subject's latest course map with the same skills,
  #   2. nothing pinned is stale: the lesson revision is the newest of its lesson and each item
  #      revision is the newest passed revision of its item,
  #   3. the lesson revision has a review by an independent session and the teacher did not send it back,
  #   3b. a lesson/2 revision has a render check without errors (D-249: its cards were drawn in Chrome and read),
  #   4. every pinned item revision passes Review::Gate,
  #   5. the teacher opened the topic review page of this very revision (app_event teacher_viewed_topic),
  #   6. the teacher confirmed reading the lesson and the sample instances (confirm_seen), and
  #   7. when the latest review of the lesson revision has blocker or major findings, the teacher gave a
  #      reason for approving anyway (3..1000 chars),
  #   8. (D-289) every free page the lesson revision pins has a passed validation in Chrome, a review by an
  #      independent session and no blocker in its latest review (a major needs the reason of 7), and
  #   9. the teacher ticked "Ho provato «title»" for each of them (pages_confirmed): the one explicit act per page.
  #
  # Nothing here decides: it says what is still missing, in the teacher's words (Teacher::Wording).
  # Reasons 6 and 7 come from the form, so the page asks for reasons 1-5 with .mechanical.
  #
  # The console attestation (D-260) waives exactly requirements 5 and 6 (the page opened and the confirmation
  # that goes with it) and nothing else; the operator's own words are recorded in the decision instead.
  module TopicGate
    Result = Struct.new(:approvable, :reasons, keyword_init: true) do
      def to_h = { approvable: approvable, reasons: reasons }
    end

    REASON_RANGE = (3..1000)
    VIEW_KIND = "teacher_viewed_topic".freeze
    CONFIRM = "the teacher did not confirm reading the lesson and the sample instances".freeze
    PAGE_CONFIRM = "the teacher did not confirm having tried the page %s (revision %d)".freeze
    REASON_NEEDED = "a reason is required to approve despite the blocker or major findings of the lesson review".freeze

    module_function

    WAIVED = "topic_review_page_not_opened".freeze

    def check(revision, confirm_seen: false, lesson_findings_reason_it: nil, waive_page_opened: false, pages_confirmed: [])
      reasons = mechanical_reasons(revision, waive_page_opened: waive_page_opened)
      reasons << CONFIRM unless confirm_seen || waive_page_opened
      reasons.concat(unconfirmed_pages(revision, pages_confirmed))
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

    def mechanical_reasons(revision, waive_page_opened: false)
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
      render_reason = LessonRenders.gate_reason(lesson_revision)
      reasons << render_reason if render_reason
      page_revisions(revision).each do |page_revision|
        reason = Pages::Validations.gate_reason(page_revision, key: page_revision.page.key)
        reasons << reason if reason
      end
      ItemRevision.where(id: item_revision_ids(revision)).order(:id).each do |item_revision|
        gate = Review::Gate.check(item_revision)
        reasons << "item revision #{item_revision.id} is not approvable: #{gate.reasons.join('; ')}" unless gate.approvable
      end
      reasons << "the topic review page of revision #{revision.id} was not opened" unless waive_page_opened || viewed?(revision)
      reasons
    end

    # The free page revisions the topic's lesson revision pins (D-289), in card order.
    def page_revisions(revision)
      ids = Pages::Embeds.revision_ids(revision.lesson_revision.body).uniq
      PageRevision.where(id: ids).includes(:page).sort_by { |r| ids.index(r.id) }
    end

    # One reason per pinned page that the teacher did not tick (pages_confirmed holds revision ids, as strings or integers).
    def unconfirmed_pages(revision, confirmed)
      ticked = Array(confirmed).map(&:to_s)
      page_revisions(revision).reject { |r| ticked.include?(r.id.to_s) }.map { |r| format(PAGE_CONFIRM, r.page.key, r.id) }
    end

    def item_revision_ids(revision) = revision.body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } }

    def map_entry(subject, key)
      course = CourseRevision.where(subject: subject).order(:seq).last or return nil
      course.body["topics"].find { |t| t["key"] == key }
    end

    # The latest review of the lesson revision (the one the teacher reads) has a blocker or major finding.
    def findings_need_reason?(revision)
      serious = ->(review) { review&.findings&.any? { |f| %w[blocker major].include?(f["severity"]) } }
      serious.call(revision.lesson_revision.reviews.max_by(&:id)) || page_revisions(revision).any? { |r| serious.call(r.reviews.max_by(&:id)) }
    end

    def viewed?(revision)
      AppEvent.where(kind: VIEW_KIND).where("json_extract(payload_json, '$.topic_revision_id') = ?", revision.id).exists?
    end
  end
end
