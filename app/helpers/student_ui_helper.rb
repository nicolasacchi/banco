# Small helpers of the student's pages (D-307, docs/ui.md): the top bar's title, the menu icons, the subject chip and the
# tones of a skill state. The look is in app/assets/stylesheets/student.css on the shared components (D-306).
module StudentUiHelper
  MENU_ICONS = { today: "nav-today", subjects: "nav-subjects", search: "nav-search", diagnosis: "nav-diagnosis", comments: "comment",
                 settings: "nav-settings", logout: "back" }.freeze
  SUBJECT_ICONS = %w[math italian chemistry biology computer_science business english spanish geography history law_economics].freeze

  # The tone of a skill's state: never red and green. Done is teal, in study blue, to recover or review brass.
  STATE_TONES = { "demonstrated" => :success, "consolidated" => :success, "in_study" => :info, "to_recover" => :nearly, "to_review" => :nearly,
                  "to_learn" => :nearly, "not_seen" => :muted }.freeze
  TOPIC_TONES = { "todo" => :muted, "in_progress" => :info, "done" => :success }.freeze

  def student_menu_icon(key) = MENU_ICONS.fetch(key, "info")

  # The section name in the top bar: the menu entry of the page, or the name of the app on a page with no entry.
  def student_bar_title(current)
    return t("student.menu.bar_default") if current.nil?

    key = current == :diagnosis && !diagnosis_open? ? :warmup : current
    t("student.menu.#{key}", default: t("student.menu.bar_default"))
  end

  # The subject's colour and icon as a round-cornered chip; the colour is the palette accent of the subject (lesson_roles.css).
  def subject_chip(key)
    safe = key.to_s.match?(/\A[a-z_]+\z/) ? key.to_s : "none"
    icon = SUBJECT_ICONS.include?(safe) ? "subject-#{safe.tr("_", "-")}" : "book-open"
    tag.span(ui_icon(icon), class: "subject-chip", style: "--subject: var(--accent-#{safe}, var(--soft-primary))", "aria-hidden": "true")
  end

  def skill_state_tone(state) = STATE_TONES.fetch(state.to_s, :muted)

  def topic_status_tone(status) = TOPIC_TONES.fetch(status.to_s, :muted)

  # The progress of a subject for a card: the share of skills shown and the non-zero counts as words.
  def subject_progress(counts)
    total = counts.values.sum
    parts = [ [ :demonstrated, :success ], [ :in_study, :info ], [ :to_recover, :nearly ], [ :not_seen, :muted ] ].filter_map do |key, tone|
      n = counts[key]
      ui_pill(t("subjects.progress.#{key}", count: n), tone) if n.positive?
    end
    { total: total, done: counts[:demonstrated], percent: total.zero? ? 0 : (100.0 * counts[:demonstrated] / total).round, pills: parts }
  end
end
