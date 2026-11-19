module Changelog
  # «Le tue segnalazioni» (D-375): for each of the student's comments on an exercise, a lesson or a topic whose topic got a newer approved
  # revision after the comment, one line: the topic was revised on that day, with the link to the thread. It never says the comment was fixed:
  # a revision is not an answer to it, and the teacher's reply is the thread's own. Read-only; his own comments only.
  #
  #   Changelog::Followups.for(student, course_view, Changelog::ContentUpdates.for_student(course_view)) # => [Followup] newest revision first
  module Followups
    PAGE_KINDS = %w[topic lesson practice].freeze

    Followup = Data.define(:comment_id, :place_it, :revised_at, :topic) do
      def date = revised_at.in_time_zone.to_date
    end

    module_function

    # +updates+: the updates this student may see (ContentUpdates.for_student). The first revision after the comment is the one named.
    def for(student, view, updates)
      return [] unless student && view && updates.any?

      Comment.where(student: student, page_kind: PAGE_KINDS).includes(:subject, :lesson_revision).order(:id).filter_map do |comment|
        place = Comments::Place.new(comment)
        topic = place.topic_key && view.find_topic(place.topic_key)&.last or next
        revised = updates.select { |u| u.topic == topic.key && u.at > comment.created_at }.min_by(&:at) or next

        Followup.new(comment_id: comment.id, place_it: place_text(place, topic), revised_at: revised.at, topic: topic.key)
      end.sort_by { |f| [ -f.revised_at.to_f, -f.comment_id ] }
    end

    # "Lezione: Le frazioni, scheda 3": the kind of page, the topic as his course names it and the card of a lesson (as «I miei commenti» says it).
    def place_text(place, topic)
      text = [ I18n.t("comments.place.#{place.kind}"), topic.title_it ].join(": ")
      place.comment.card ? "#{text}, #{I18n.t('comments.card', n: place.comment.card)}" : text
    end
  end
end
