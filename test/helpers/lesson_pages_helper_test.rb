require "test_helper"

# The texts and addresses a lesson page hands to lesson2_controller.js: the button texts of a bilingual lesson's «Traduzione» (D-402) and the address its opening is told to.
class LessonPagesHelperTest < ActionView::TestCase
  include LessonPagesHelper

  test "the texts of the page carry the translation button's texts, as items/translation.js reads them" do
    texts = lesson2_texts
    assert_equal I18n.t("translation.toggle"), texts.dig("translation", "toggle")
    assert_includes texts.dig("translation", "unit"), "%{words}"
  end

  test "the English interface has them too" do
    I18n.with_locale(:en) do
      assert_equal "Translation", lesson2_texts.dig("translation", "toggle")
    end
  end

  test "the student's page tells where an opened translation is posted, the teacher's preview writes nothing" do
    def spath(path) = path
    def base_path = ""
    def preview? = false
    assert_equal "/translations", lesson2_urls("lezione.english.can")[:translations]
    def preview? = true
    assert_not lesson2_urls("lezione.english.can").key?(:translations)
  end
end
