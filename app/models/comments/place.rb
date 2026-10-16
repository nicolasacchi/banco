module Comments
  # Where a comment was written, for the teacher: the kind of page, the topic or run it belonged to, the exact
  # card and block of a lesson, the item, and the link to the teacher's own page about it. Read from the comment's
  # row and the frozen revisions it names (what the student saw), never from the live course.
  class Place
    attr_reader :comment

    def initialize(comment) = @comment = comment

    def page = @page ||= Pages.parse(comment.page_path)
    def kind = comment.page_kind
    def anchor_segments = comment.anchor.to_s.split("/")
    def topic_key = page&.topic
    def subject_key = comment.subject&.key
    def item_revision = comment.item_revision
    def lesson_revision = comment.lesson_revision

    # The card of a lesson/2 the comment was written on: [n, title], nil when none or not a lesson/2.
    def card
      return nil unless comment.card && lesson_revision&.lesson2?

      found = lesson_revision.body["cards"].find { |c| c["n"] == comment.card }
      found && [ found["n"], found["title_it"] ]
    end

    # The block of that card the anchor names: [n, type], nil when the anchor names none.
    def block
      n = anchor_segments.find { |s| s.start_with?("block:") }&.delete_prefix("block:")&.to_i
      return nil unless n && comment.card && lesson_revision&.lesson2?

      cards = lesson_revision.body["cards"].find { |c| c["n"] == comment.card } or return nil
      found = Array(cards["blocks"]).find { |b| b["n"] == n }
      found && [ n, found["type"] ]
    end

    # The teacher's page about the place, nil when there is none.
    def link
      key = subject_key
      return nil unless key

      case kind
      when "lesson", "topic" then topic_key && "/teacher/subjects/#{key}/topics/#{topic_key}"
      when "practice" then item_revision ? "/teacher/items/#{item_revision.id}" : "/teacher/subjects/#{key}/practice"
      when "sitting", "results" then item_revision ? "/teacher/items/#{item_revision.id}" : "/teacher/subjects/#{key}/test"
      when "subject" then "/teacher/subjects/#{key}/course"
      end
    end
  end
end
