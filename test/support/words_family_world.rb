require_relative "lesson2_page_world"

# The galleries of the words family (test/fixtures/lesson2/gallery/words.md and words-english.md) as the lesson of the student's page: the
# stored body (answers and all), which the page projects with Lessons::StudentBody, as for a real lesson. Invented content only.
module WordsFamilyWorld
  include Lesson2PageWorld

  GALLERIES = { spanish: "gallery/words.md", english: "gallery/words-english.md" }.freeze

  # The stored body of a gallery, under the topic key of the world.
  def gallery_body(which = @gallery || :spanish)
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(Rails.root.join("test/fixtures/lesson2", GALLERIES.fetch(which)).read, findings).body
    raise "gallery #{which} has findings: #{findings.errors.map(&:to_h)}" if findings.errors.any?

    body.merge("key" => TOPIC)
  end

  def lesson_body = gallery_body
end
