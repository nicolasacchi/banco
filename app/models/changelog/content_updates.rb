module Changelog
  # What changed in the course, read from the ledger (D-375): every `approve_topic` that replaced an earlier approved revision of the same topic is
  # one update. No table of its own: the decisions are the record. The teacher reads the reason and the two revision ids; the student reads only
  # that the topic was revised, and only for the topics his course view shows (Course::Catalog), never the teacher's reason.
  #
  #   Changelog::ContentUpdates.all                       # => [Update] newest first, every topic
  #   Changelog::ContentUpdates.for_student(course_view)  # => [Update] for the topics this student sees, from when his course was open
  #   Changelog::ContentUpdates.by_day(updates)           # => [[Date, [Update]]] newest day first, one update per topic and day
  module ContentUpdates
    Update = Data.define(:decision_id, :at, :subject_key, :topic, :title_it, :old_revision_id, :new_revision_id, :reason_it, :via) do
      def date = at.in_time_zone.to_date
    end

    module_function

    def all
      approvals = Decision.where(kind: "approve_topic").includes(:subject).order(:id).to_a
      current = {}
      found = approvals.filter_map do |decision|
        payload = JSON.parse(decision.payload_json)
        key = payload["topic"]
        new_id = payload["topic_revision_id"]
        old_id = current[key]
        current[key] = new_id
        next if old_id.nil? || old_id == new_id

        Update.new(decision_id: decision.id, at: decision.created_at, subject_key: decision.subject&.key, topic: key, title_it: title_of(key, new_id),
                   old_revision_id: old_id, new_revision_id: new_id, reason_it: reason_of(payload), via: payload["via"].presence || "web")
      end
      found.reverse
    end

    # The updates of the topics this student's course view shows. An official student never saw a topic before the teacher opened its subject, so
    # an approval from before that is no news to him; the title is the one his course shows.
    def for_student(view, updates = all)
      return [] unless view

      opened = first_open_release_ids
      updates.filter_map do |update|
        subject_view, topic = view.find_topic(update.topic)
        next unless topic
        next if subject_view.mode == :official && update.decision_id < opened.fetch(subject_view.subject.id, Float::INFINITY)

        update.with(title_it: topic.title_it)
      end
    end

    # One update per topic and day, grouped by day, newest day first (the day in the school's zone).
    def by_day(updates)
      updates.group_by(&:date).sort_by { |date, _| -date.jd }
             .map { |date, list| [ date, list.uniq(&:topic) ] }
    end

    # {subject id => id of its first open release_course}.
    def first_open_release_ids
      Decision.where(kind: "release_course").order(:id).each_with_object({}) do |decision, ids|
        next if ids.key?(decision.subject_id) || JSON.parse(decision.payload_json)["open"] != true

        ids[decision.subject_id] = decision.id
      end
    end

    # The teacher's words on the approval: the findings reason, else the operator's or the bot's note, else the attestation.
    def reason_of(payload)
      %w[lesson_findings_reason_it console_reason api_reason attest_it].filter_map { |key| payload[key].to_s.strip.presence }.first
    end

    # The title the course map gives the topic, from the revision it was approved with.
    def title_of(key, revision_id)
      revision = TopicRevision.find_by(id: revision_id)
      entry = revision&.course_revision&.body&.dig("topics")&.find { |t| t["key"] == key }
      entry&.dig("title_it") || key
    end
  end
end
