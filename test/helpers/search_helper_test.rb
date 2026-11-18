require "test_helper"

# D-364: the small words that the code puts between the links of a «did you mean» line belong to the language of the page.
class SearchHelperTest < ActionView::TestCase
  Result = Struct.new(:suggestions) do
    def only_corrected? = true
  end

  def result = Result.new([ [ "costituzione", "sostituzione", "sostituzione" ], [ "costituzione", "costituzioni", "costituzioni" ] ])

  test "two corrections are joined with the word of the page's language" do
    english = I18n.with_locale(:en) { search_did_you_mean(result, "/search", "search.did_you_mean_html") }
    assert_includes english, "</a> or <a"
    assert_not_includes english, "</a> o <a"
    italian = search_did_you_mean(result, "/search", "search.did_you_mean_html")
    assert_includes italian, "</a> o <a"
  end
end
