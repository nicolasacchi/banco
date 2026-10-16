# Views of the content search (D-299): the snippet with its matched words, the icons and names of the kinds.
module SearchHelper
  KIND_ICONS = { "lesson_card" => "book-open", "glossary_term" => "book-a", "topic" => "compass", "practice_item" => "notebook-pen",
                 "item" => "circle-help", "item_instance" => "circle-help", "course" => "map", "skill" => "list-checks", "finding" => "triangle-alert",
                 "reference_article" => "book-open", "syllabus_line" => "list-checks", "student_answer" => "pencil-ruler" }.freeze
  SUBJECTS = %w[math italian chemistry biology computer_science business english spanish geography history law_economics].freeze

  # The snippet of a hit, the words that matched in <mark>. Everything else is escaped text.
  def search_snippet(hit, result)
    safe_join(hit.segments(result.terms, result.variants).map { |text, matched| matched ? content_tag(:mark, text) : text })
  end

  # An icon of the structural/ui sprite (bin/build-icons), decorative: the label next to it carries the meaning.
  def search_icon(kind)
    name = KIND_ICONS.fetch(kind, "info")
    tag.svg(tag.use(nil, href: "/vendor/lucide@1.54.0/banco-sprite.svg##{name}"), class: "search-icon", "aria-hidden": "true", focusable: "false")
  end

  def search_kind_name(kind) = t("search.kinds.#{kind}")

  # The subject colour band of a result (config/banco/lesson_palette.yml accents), nothing for a hit with no subject.
  def search_accent_style(subject)
    SUBJECTS.include?(subject) ? "--search-accent: var(--accent-#{subject})" : nil
  end

  def search_subject_name(subject) = (@search_subject_names ||= Subject.pluck(:key, :name_it).to_h)[subject]
end
