require_relative "lesson2_page_world"
require_relative "lesson2_fixtures"

# The gallery of the docs family (test/fixtures/lesson2/gallery/docs.md) as the lesson of the student's page: the stored body (answers and all),
# which the page projects with Lessons::StudentBody, as for a real lesson. Invented content only.
module DocsFamilyWorld
  include Lesson2PageWorld

  GALLERY = Lesson2Fixtures::DIR.join("gallery/docs-lesson.md")

  # The stored body of the gallery lesson, under the topic key of the world.
  def gallery_body
    body = Lesson2Fixtures.check(GALLERY.read, "business").body
    body.merge("key" => TOPIC)
  end

  def lesson_body = gallery_body
end
