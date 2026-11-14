require_relative "lesson_events_world"

# LessonEventsWorld's lesson (the real parse of test/fixtures/lesson2/demo.md, answers and all) with one sentence of its first card that
# links to two topics: one the course opens (the lesson's own) and one it does not have (never approved, never released).
module LessonLinksWorld
  include LessonEventsWorld

  OPEN_LINK_TEXT = "le equazioni".freeze
  CLOSED_LINK_TEXT = "le potenze".freeze
  CLOSED_KEY = "ripasso.math.non-aperto".freeze

  def lesson_body
    md = File.read(Rails.root.join("test/fixtures/lesson2/demo.md"))
    linked = md.sub("Una **soluzione** è il numero", "Ripassa [#{OPEN_LINK_TEXT}](argomento:#{TOPIC}) e [#{CLOSED_LINK_TEXT}](argomento:#{CLOSED_KEY}). Una **soluzione** è il numero")
    @linked_lesson2 ||= Lessons::Parser2.call(linked, Validation::Findings.new).body.merge("key" => TOPIC)
  end
end
