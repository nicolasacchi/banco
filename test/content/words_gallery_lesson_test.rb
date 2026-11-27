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
      # The galleries are the block types of the words family in the old format (Italian text, the language in spans): a gallery is no new spanish
      # or english submission, so the D-404 and D-405 requirement (bilingual: true) is not its business, as the structure is not.
      result = Validation::Rules.with(lang: { bilingual_required: [] }) { Lesson2Fixtures.check(Lesson2Fixtures.read(file), subject) }
      assert_empty result.findings.errors.reject { |e| STRUCTURE.include?(e.code) }.map(&:to_h), file
    end
  end
end
