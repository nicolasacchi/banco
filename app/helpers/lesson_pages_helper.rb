# The page of a lesson/2 (R2): the texts, the addresses and the switches that lesson2_controller.js needs.
module LessonPagesHelper
  def lesson2?(body) = body.is_a?(Hash) && body["schema"] == "banco.lesson/2"

  # The families of wave 2 each have their texts in config/locales/lesson_FAMILY.it.yml; the page gets them as t.FAMILY (t.docs, t.words...).
  LESSON_FAMILIES = %w[graph time maps chart science computing words docs].freeze

  # The texts of the page, one nested object (config/locales/lesson.it.yml, then lesson_FAMILY.it.yml under the family's name).
  def lesson2_texts
    LESSON_FAMILIES.to_h { |family| [ family, I18n.t("lesson_#{family}", default: {}).deep_stringify_keys ] }.merge(I18n.t("lesson2").deep_stringify_keys)
  end

  # The stylesheets of the families whose blocks or figures a lesson uses (app/assets/stylesheets/lesson/FAMILY.css): the page head reads the
  # body, so a lesson of release 1 loads none of them. ["lesson/docs", ...] for stylesheet_link_tag.
  def lesson2_family_stylesheets(body)
    families = Set.new
    walk = lambda do |node|
      case node
      when Hash
        if (type = node["type"]).is_a?(String)
          [ :block, :diagram ].each { |kind| (f = Lessons::Types.entry(kind, type)&.fetch("family", nil)) && f != "core" && families << f }
        end
        node.each_value(&walk)
      when Array then node.each(&walk)
      end
    end
    walk.call(body)
    families.sort.map { |f| "lesson/#{f}" }
  end

  # The item templates' texts that the checks reuse (number, fraction, choice, text), and the accents label.
  def lesson2_item_texts = I18n.t("items").merge(accents_label: I18n.t("accents.label")).deep_stringify_keys

  # The addresses of the student's page: the check endpoint, the events batch, the solutions and the questions.
  def lesson2_urls(topic_key)
    { check: "/topics/#{topic_key}/lesson/checks", events: "/topics/#{topic_key}/lesson/events",
      solution: "/topics/#{topic_key}/lesson/exercises", questions: "/questions", practice: "/topics/#{topic_key}" }
  end
end
