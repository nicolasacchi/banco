module Course
  # The teacher's decisions about lessons and topics (A6.1), read where the agent side needs them. The agents
  # never write these: the browser does (S4). Payloads are those of DecisionRecorder.
  module Decisions
    module_function

    # {lesson revision id => [payload + "at"]} for send_back_lesson, oldest first (all when ids is nil).
    def lesson_send_backs(revision_ids = nil)
      rows = Decision.where(kind: "send_back_lesson").order(:id).to_a.map { |d| JSON.parse(d.payload_json).merge("at" => d.created_at.utc.iso8601, "decision_id" => d.id) }
      rows = rows.select { |p| revision_ids.include?(p["lesson_revision_id"]) } if revision_ids
      rows.group_by { |p| p["lesson_revision_id"] }
    end

    def lesson_sent_back?(revision) = lesson_send_backs([ revision.id ]).key?(revision.id)

    # The topic revision id the latest approve_topic of +key+ names, or nil.
    def approved_topic_revision_id(key)
      Decision.where(kind: "approve_topic").order(:id).reverse_each do |d|
        payload = JSON.parse(d.payload_json)
        return payload["topic_revision_id"] if payload["topic"] == key
      end
      nil
    end
  end
end
