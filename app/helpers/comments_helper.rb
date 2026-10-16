# Comments anywhere (D-304): the student's control, the badge of unread replies and the place of a comment in words.
module CommentsHelper
  # The texts of the comment box's script (config/locales/comments.it.yml).
  def comment_labels = I18n.t("comments").slice(:whole_page, :chars, :reason_required, :sent, :queued, :error, :anchors)

  # A decorative icon of the ui sprite (bin/build-icons, config/banco/icons.yml): the word next to it carries the meaning.
  def comment_icon(name)
    tag.svg(tag.use(nil, href: "/vendor/lucide@1.54.0/banco-sprite.svg##{name}"), class: "comment-icon", "aria-hidden": "true", focusable: "false")
  end

  # The icon of a page kind in "I miei commenti" and on the teacher's cards (all in the structural sprite).
  PLACE_ICONS = { "today" => "compass", "subjects" => "map", "subject" => "map", "topic" => "compass", "lesson" => "book-open", "practice" => "notebook-pen",
                  "diagnosis" => "list-checks", "warmup" => "list-checks", "sitting" => "circle-help", "results" => "list-checks", "settings" => "text-settings",
                  "search" => "info", "comments" => "comment" }.freeze

  STATE_ICONS = { "sent" => "send", "read" => "show", "answered" => "teacher-reply", "closed" => "check" }.freeze

  def comment_state_icon(state) = comment_icon(STATE_ICONS.fetch(state, "info"))

  def comment_place_icon(comment) = comment_icon(PLACE_ICONS.fetch(comment.page_kind, "info"))

  # The subject colour of a comment's place, a CSS variable of the palette (lesson_roles.css) or the neutral line.
  def comment_accent_style(comment)
    key = comment.subject&.key
    key.to_s.match?(/\A[a-z_]+\z/) ? "--comment-accent: var(--accent-#{key}, var(--line)); --comment-badge: var(--accent-#{key}, var(--bg))" : nil
  end

  # The comment box is on every student page and nowhere in the teacher's preview (the preview writes none).
  def comment_box? = !preview? && respond_to?(:acting_student)

  # Replies of the teacher this student has not read yet; memoised for the request.
  def comment_unread_count
    return 0 unless respond_to?(:acting_student) && !preview?

    @_comment_unread ||= Comment.unread_reply_count(acting_student)
  end

  # In a sitting the counted time stops while the box is open: the run's events address.
  def comment_events_url
    controller_name == "sittings" && action_name == "show" ? "#{base_path}/runs/#{@run.id}/events" : ""
  end

  # "Lezione: Le frazioni, scheda 3" for the student's list.
  def comment_place_it(comment)
    parts = [ t("comments.place.#{comment.page_kind}") ]
    page = Comments::Pages.parse(comment.page_path)
    topic = page&.topic && course_view.find_topic(page.topic)&.last
    parts << topic.title_it if topic
    parts << t("comments.card", n: comment.card) if comment.card
    parts.join(": ").sub(/: (scheda)/, ", \\1")
  end
end
