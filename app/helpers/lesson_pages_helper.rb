# The page of a lesson/2 (R2): the texts, the addresses and the switches that lesson2_controller.js needs.
module LessonPagesHelper
  def lesson2?(body) = body.is_a?(Hash) && body["schema"] == "banco.lesson/2"

  # The texts of the page, one nested object (config/locales/lesson.it.yml), with the texts of each family of diagram types
  # (config/locales/lesson_FAMILY.it.yml, keys named for their family: chart_*) beside them.
  def lesson2_texts
    families = Lessons::Types.data.fetch("diagrams").values.map { |e| e["family"] }.uniq - [ "core" ]
    families.reduce(I18n.t("lesson2").deep_stringify_keys) { |all, f| all.merge(I18n.t("lesson_#{f}", default: {}).to_h.deep_stringify_keys) }
  end

  # The families of diagram types a body uses besides the core: their stylesheets are linked only when the lesson needs them (D-264).
  def lesson_families(body)
    types = Lessons::Types.data.fetch("diagrams")
    found = Set.new
    walk = lambda do |node|
      case node
      when Hash
        t = node["type"]
        found << types.dig(t, "family") if t.is_a?(String) && types[t]
        node.each_value { |v| walk.call(v) }
      when Array then node.each { |v| walk.call(v) }
      end
    end
    walk.call(body)
    (found - [ nil, "core" ]).sort
  end

  def lesson_family_stylesheets(body) = safe_join(lesson_families(body).map { |f| stylesheet_link_tag("lesson/#{f}") })

  # The item templates' texts that the checks reuse (number, fraction, choice, text), and the accents label.
  def lesson2_item_texts = I18n.t("items").merge(accents_label: I18n.t("accents.label")).deep_stringify_keys

  # The addresses of the student's page: the check endpoint, the events batch, the solutions and the questions.
  def lesson2_urls(topic_key)
    { check: "/topics/#{topic_key}/lesson/checks", events: "/topics/#{topic_key}/lesson/events",
      solution: "/topics/#{topic_key}/lesson/exercises", questions: "/questions", practice: "/topics/#{topic_key}" }
  end
end
