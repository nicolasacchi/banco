# The page of a lesson/2 (R2): the texts, the addresses and the switches that lesson2_controller.js needs.
module LessonPagesHelper
  def lesson2?(body) = body.is_a?(Hash) && body["schema"] == "banco.lesson/2"

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
