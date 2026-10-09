module Teacher
  # What the teacher has looked at on a topic page (D-240), kept as app events like the views the gates read
  # (teacher_viewed_topic, teacher_viewed_item). Never a decision, and nothing the approval gate asks for:
  # the guided review reads them to mark its steps done.
  module TopicSeen
    LESSON_KIND = "teacher_read_lesson".freeze
    EXERCISE_KIND = "teacher_saw_exercise".freeze

    module_function

    def lesson_read?(topic_revision) = events(LESSON_KIND, topic_revision).exists?

    # Item revision ids of the pinned exercises the teacher has seen.
    def seen_item_ids(topic_revision)
      events(EXERCISE_KIND, topic_revision).pluck(:payload_json).filter_map { |j| JSON.parse(j)["item_revision_id"]&.to_i }.to_set
    end

    def record_lesson(topic_revision)
      AppEvent.create!(kind: LESSON_KIND, payload_json: { topic_revision_id: topic_revision.id }.to_json) unless lesson_read?(topic_revision)
    end

    # False when the item revision is not pinned by the topic revision.
    def record_exercise(topic_revision, item_revision_id)
      return false unless Approval::TopicGate.item_revision_ids(topic_revision).include?(item_revision_id)

      unless seen_item_ids(topic_revision).include?(item_revision_id)
        AppEvent.create!(kind: EXERCISE_KIND, payload_json: { topic_revision_id: topic_revision.id, item_revision_id: item_revision_id }.to_json)
      end
      true
    end

    def events(kind, topic_revision)
      AppEvent.where(kind: kind).where("json_extract(payload_json, '$.topic_revision_id') = ?", topic_revision.id)
    end
  end
end
