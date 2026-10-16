module Search
  module Builders
    # The revisions worth indexing: the latest of each object and what a student may be shown (the topic revisions the
    # teacher approved, the lesson and item revisions they pin). Who may see which of them is Search::Scope, at query time.
    module Live
      module_function

      def approved_topic_revision_ids
        Decision.where(kind: "approve_topic").pluck(:payload_json).filter_map { |json| JSON.parse(json)["topic_revision_id"] }.uniq
      end

      def topic_revisions
        ids = Latest.ids("topic_revisions") | approved_topic_revision_ids
        TopicRevision.where(id: ids).includes(:lesson, :course_revision, :lesson_revision).order(:id).to_a
      end

      def lesson_revisions(topics = topic_revisions)
        ids = Latest.ids("lesson_revisions") | topics.map(&:lesson_revision_id)
        LessonRevision.where(id: ids).includes(lesson: :subject).order(:id).to_a
      end

      def pinned_item_revision_ids(topics = topic_revisions)
        topics.flat_map { |t| Array(t.body["practice"]).flat_map { |p| Array(p["items"]).map { |i| i["revision"] } } }.uniq
      end

      def item_revisions(topics = topic_revisions)
        ids = Latest.ids("item_revisions") | pinned_item_revision_ids(topics)
        ItemRevision.where(id: ids).includes(item: :subject).order(:id).to_a
      end
    end
  end
end
