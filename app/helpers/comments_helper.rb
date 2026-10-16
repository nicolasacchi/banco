# Comments anywhere (D-304): the student's control, the badge of unread replies and the place of a comment in words.
module CommentsHelper
  # The texts of the comment box's script (config/locales/comments.it.yml).
  def comment_labels = I18n.t("comments").slice(:whole_page, :chars, :reason_required, :sent, :queued, :error)

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
