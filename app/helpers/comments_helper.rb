# Comments anywhere (D-304): the student's control, the badge of unread replies and the place of a comment in words.
module CommentsHelper
  # The texts of the comment box's script (config/locales/comments.it.yml).
  def comment_labels = I18n.t("comments").slice(:whole_page, :chars, :reason_required, :sent, :queued, :error, :anchors)

  # A decorative icon of the ui sprite (bin/build-icons, config/banco/icons.yml): the word next to it carries the meaning.
  def comment_icon(name)
    tag.svg(tag.use(nil, href: Banco::Sprites.icon_href(name)), class: "comment-icon", "aria-hidden": "true", focusable: "false")
  end

  # The icon of a page kind in "I miei commenti" and on the teacher's cards (all in the structural sprite).
  PLACE_ICONS = { "today" => "compass", "subjects" => "map", "subject" => "map", "topic" => "compass", "lesson" => "book-open", "practice" => "notebook-pen",
                  "diagnosis" => "list-checks", "warmup" => "list-checks", "sitting" => "circle-help", "results" => "list-checks", "settings" => "text-settings",
                  "search" => "info", "comments" => "comment", "privacy" => "info", "account" => "info", "civics" => "map", "not_found" => "info", "schema" => "map", "schemas" => "map" }.freeze

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

  # The address the box files the comment under: the page's own, or the one the page names (the student's 404 says
  # "/not-found" + the address it could not open, D-361: the page path of a place that is not there is no page).
  def comment_page_path = content_for(:comment_page_path).presence || request.path

  # In a sitting the counted time stops while the box is open: the run's events address.
  def comment_events_url
    controller_name == "sittings" && action_name == "show" && @run ? "#{base_path}/runs/#{@run.id}/events" : ""
  end

  # The anchor of a comment in the student's own words ("Scheda 3 · Blocco 2 · La risposta"), the words the box showed him (`comments.anchors`, as
  # `describeAnchor` in items/comment_anchor.js: an unknown segment is left out, the last three are kept). Nil when no segment has a name: a raw
  # id (`id:my-path-title`) is never printed.
  def comment_anchor_words(comment)
    names = I18n.t("comments.anchors")
    words = comment.anchor.to_s.split("/").filter_map do |segment|
      name, value = segment.split(":", 2)
      template = names[name.to_s.to_sym]
      next unless template.is_a?(String)

      template.include?("%{n}") ? (value && template.sub("%{n}", value)) : template
    end
    words = words.chunk_while { |a, b| a == b }.map(&:first)
    words.empty? ? nil : words.last(3).join(" · ")
  end

  # "Lezione: Le frazioni, scheda 3" for the student's list.
  def comment_place_it(comment)
    parts = [ t("comments.place.#{comment.page_kind}") ]
    page = Comments::Pages.parse(comment.page_path)
    topic = page&.topic && course_view.find_topic(page.topic)&.last
    parts << topic.title_it if topic
    place = parts.join(": ")
    comment.card ? "#{place}, #{t('comments.card', n: comment.card)}" : place
  end

  # ---- the inbox and the conversation (D-349) ----

  # «15:40», in the school's zone.
  def comment_clock(time) = time.in_time_zone.strftime("%H:%M")

  # The time of a row of the inbox: «oggi 15:40», «ieri», «12 nov» (with the year when it is not this one).
  def comment_when(time)
    day = time.in_time_zone.to_date
    today = Time.zone.today
    return t("comments.when.today", time: comment_clock(time)) if day == today
    return t("comments.when.yesterday") if day == today - 1

    I18n.l(day, format: day.year == today.year ? "%-d %b" : "%-d %b %Y")
  end

  # The separator between the days of a conversation: «Oggi», «Ieri», «12 novembre».
  def comment_day_label(day)
    today = Time.zone.today
    return t("comments.thread.today") if day == today
    return t("comments.thread.yesterday") if day == today - 1

    I18n.l(day, format: day.year == today.year ? "%-d %B" : "%-d %B %Y")
  end

  # [who, text] of the last message of a row: «Tu:» / «Docente:» and the words; a first message without words says its reason.
  def comment_preview(row)
    last = row.last
    who = t(last.from == :teacher ? "comments.inbox.teacher" : "comments.inbox.you")
    text = last.text_it.presence || (last.event.nil? ? t("comments.reason.#{row.comment.reason}") : "")
    [ who, text.squish ]
  end

  # Where the comment was written, as an address of the student's pages, when that page is still there for this student:
  # the course pages need the topic or the subject to be visible. Nil for a test, a run or the comments themselves.
  def comment_place_link(comment)
    page = Comments::Pages.parse(comment.page_path) or return nil
    case page.kind
    when "today", "settings", "search", "privacy", "account", "changelog" then comment.page_path
    when "subjects" then comment.page_path if course_view.subjects.any?
    when "civics" then comment.page_path if Course::Civics.new(course_view).any?
    when "schemas" then comment.page_path if course_view.subjects.any?
    when "subject" then comment.page_path if course_view.subject(page.subject_key)
    when "topic", "practice", "schema" then comment.page_path if course_view.find_topic(page.topic)
    when "lesson" then (comment.card ? "#{comment.page_path}#scheda-#{comment.card}" : comment.page_path) if course_view.find_topic(page.topic)
    end
  end

  # The texts of the conversation's script (config/locales/comments.it.yml).
  def comment_thread_labels
    I18n.t("comments.thread").slice(:sending, :failed, :error, :today).merge(reply_error: I18n.t("comments.reply_error"), state_sent: I18n.t("comments.state.sent"))
  end

  # The query of a link inside «I miei commenti»: the tab is kept (the default one is left out).
  def comment_tab_query(tab) = tab.to_s == "all" ? {} : { tab: tab }
end
