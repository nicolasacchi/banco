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

    # Whether some topic of the course map has an approval whose skills match the map's (A6.1).
    def approved_topic_in?(course)
      keys = course.body["topics"].to_h { |t| [ t["key"], t["skills"].sort ] }
      Decision.where(kind: "approve_topic", subject_id: course.subject_id).pluck(:payload_json).any? do |json|
        payload = JSON.parse(json)
        wanted = keys[payload["topic"]] or next false
        revision = TopicRevision.find_by(id: payload["topic_revision_id"])
        revision && Catalog.skills_of(revision) == wanted
      end
    end

    # Why the latest course map cannot be opened to the official student yet (A6.1), as plain reasons.
    def release_reasons(subject, course)
      return [ "there is no course map for #{subject.key}" ] unless course

      reasons = []
      approved = SubjectStage.approved_graph(subject)
      reasons << "the course map was not validated against the approved graph of #{subject.key}" unless approved && approved.id == course.skill_graph_revision_id
      reasons << "no topic of the course map is approved" unless approved_topic_in?(course)
      reasons << "the course is already open with this map" if State.released_revision_id(subject) == course.id
      reasons
    end
  end
end
