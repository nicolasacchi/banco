require "test_helper"
require_relative "../support/lesson2_fixtures"

# The galleries of the words family as whole lessons: the full checks of Validation::LessonChecks (blocks, cards, leaks, apparatus, readability),
# not only the parse. Invented content, the contexts of test/fixtures/lesson2/context.json.
class WordsGalleryLessonTest < ActiveSupport::TestCase
  FILES = { "gallery/words.md" => "spanish", "gallery/words-english.md" => "english" }.freeze

  # A gallery is a lesson only in its blocks: the counts of cards, checks and visuals, and the refs of a whole lesson, are not its business.
  STRUCTURE = %w[E-LESSON-REFS E-LESSON-CARDS E-CARD-NO-VISUAL E-LESSON-VISUALS E-LESSON-CHECKS].freeze

  FILES.each do |file, subject|
    test "#{file} passes the checks of a lesson of #{subject} with no error" do
      result = Lesson2Fixtures.check(Lesson2Fixtures.read(file), subject)
      assert_empty result.findings.errors.reject { |e| STRUCTURE.include?(e.code) }.map(&:to_h), file
    end
  end
end
