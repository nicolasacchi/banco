# The page of a lesson/2 (R2): the texts, the addresses and the switches that lesson2_controller.js needs.
module LessonPagesHelper
  def lesson2?(body) = body.is_a?(Hash) && body["schema"] == "banco.lesson/2"

  # The stylesheets of the families whose diagrams the body draws (app/assets/stylesheets/lesson/FAMILY.css): a page links only what it uses.
  def lesson2_family_css(body)
    families = []
    walk = lambda do |node|
      case node
      when Hash
        entry = node["type"].is_a?(String) && node.key?("alt_it") ? Lessons::Types.entry(:diagram, node["type"]) : nil
        families << entry["family"] if entry && entry["family"] != "core"
        families << "computing" if node["component"] == "normalized_text" && node["input"] == "bits" # the switches of a register (T9)
        node.each_value(&walk)
      when Array then node.each(&walk)
      end
    end
    walk.call(body)
    families.uniq.map { |f| "lesson/#{f}" }
  end

  # The texts of the page, one nested object (config/locales/lesson.it.yml).
  def lesson2_texts = I18n.t("lesson2").deep_stringify_keys

  # The item templates' texts that the checks reuse (number, fraction, choice, text), and the accents label.
  def lesson2_item_texts = I18n.t("items").merge(accents_label: I18n.t("accents.label")).deep_stringify_keys

  # The addresses of the student's page: the check endpoint, the events batch, the solutions and the questions.
  def lesson2_urls(topic_key)
    { check: "/topics/#{topic_key}/lesson/checks", events: "/topics/#{topic_key}/lesson/events",
      solution: "/topics/#{topic_key}/lesson/exercises", questions: "/questions", practice: "/topics/#{topic_key}" }
  end
end
