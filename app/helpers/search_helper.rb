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

  # «Non ho trovato «costituzione». Forse cercavi «sostituzione»?» when the hits come only from the typo fallback: each corrected word is
  # a link that runs the search with it. +path+ is the page ("/search"), +extra+ the filters to keep; +key+ the i18n key (..._html).
  def search_did_you_mean(result, path, key, extra: {})
    return unless result.only_corrected?

    sentences = result.suggestions.group_by(&:first).first(2).map do |term, items|
      links = items.map { |_, word, query| link_to("«#{word}»", "#{path}?#{extra.merge(q: query).to_query}", class: "search-correction") }
      t(key, term: term, options: safe_join(links, " o "))
    end
    sentences.any? ? safe_join(sentences, " ") : nil
  end

  # The "Simili" button needs vectors: shown on the teacher's pages only when an embedding service is set up.
  def search_similar_enabled? = Search::Embedder.configured?

  # The teacher's search with the neighbours of an object (ref: Search::Links.address or a key).
  def search_similar_path(ref) = "/teacher/search?#{{ like: ref }.to_query}"
end
