module Changelog
  # «Le tue segnalazioni» (D-375): for each of the student's comments on an exercise, a lesson or a topic whose topic got a newer approved
  # revision after the comment, one follow-up; the page shows them grouped by topic (D-378): one card per topic with how many comments he wrote
  # there and the day of the latest revision. It never says the comment was fixed: a revision is not an answer to it, and the teacher's reply is the
  # thread's own. Read-only; his own comments only. The page says «commento», as the rest of the app does, never «segnalazione».
  #
  #   Changelog::Followups.for(student, course_view, Changelog::ContentUpdates.for_student(course_view)) # => [Followup] newest revision first
  #   Changelog::Followups.group(followups)                                                              # => [Group] one per topic, newest revision first
  module Followups
    PAGE_KINDS = %w[topic lesson practice].freeze

    # revised_at: the latest approval of the topic after the comment.
    Followup = Data.define(:comment_id, :title_it, :revised_at, :topic) do
      def date = revised_at.in_time_zone.to_date
    end

    # One topic: the ids of his comments on it (oldest first) and the latest revision after any of them.
    Group = Data.define(:topic, :title_it, :comment_ids, :revised_at) do
      def count = comment_ids.size
      def date = revised_at.in_time_zone.to_date
      # The thread to open when there is only one comment; with several, the list of his comments.
      def comment_id = comment_ids.last
    end

    module_function

    # +updates+: the updates this student may see (ContentUpdates.for_student).
    def for(student, view, updates)
      return [] unless student && view && updates.any?

      Comment.where(student: student, page_kind: PAGE_KINDS).includes(:subject, :lesson_revision).order(:id).filter_map do |comment|
        place = Comments::Place.new(comment)
        topic = place.topic_key && view.find_topic(place.topic_key)&.last or next
        revised = updates.select { |u| u.topic == topic.key && u.at > comment.created_at }.max_by(&:at) or next

        Followup.new(comment_id: comment.id, title_it: topic.title_it, revised_at: revised.at, topic: topic.key)
      end.sort_by { |f| [ -f.revised_at.to_f, -f.comment_id ] }
    end

    # One group per topic, newest revision first.
    def group(followups)
      followups.group_by(&:topic).map do |topic, list|
        Group.new(topic: topic, title_it: list.first.title_it, comment_ids: list.map(&:comment_id).sort, revised_at: list.map(&:revised_at).max)
      end.sort_by { |g| [ -g.revised_at.to_f, -g.comment_id ] }
    end
  end
end
