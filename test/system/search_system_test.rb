require "application_system_test_case"
require_relative "../support/search_world"
require_relative "../support/student_session"

# The student's search in Chrome (D-299): type, submit, see the groups, follow a link to the lesson card and to the practice page,
# clear the box. No script is involved in the page.
class SearchSystemTest < ApplicationSystemTestCase
  include SearchWorld
  include StudentSession

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV.delete("BANCO_STUDENT_USERS")
    build_search_world
    rebuild_search!
    sign_in_as :student
  end

  teardown do
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  test "the student types a word and finds a section of the lesson, the topic and the exercises" do
    visit "/search"
    assert_selector "#search-hint"
    fill_in "q", with: "equazioni"
    click_button "Cerca"
    assert_selector ".search-group[data-kind=lesson_card] .search-hit"
    assert_selector ".search-group[data-kind=topic] .search-hit"
    assert_selector ".search-snippet mark", text: /equazion/i
    assert_equal "equazioni", find_field("q").value
    click_link "Equazioni di primo grado", match: :first
    assert_current_path %r{\A/topics/}
  end

  test "an exercise leads to the practice page of its skill" do
    visit "/search?q=radice+quadrata"
    assert_selector ".search-group[data-kind=practice_item]"
    first(".search-group[data-kind=practice_item] a.search-title").click
    assert_current_path "/topics/#{TOPIC}/practice/#{SKILL}"
  end

  test "a word nothing matches, a typo and the clear link" do
    visit "/search?q=qzxwvutsrq"
    assert_selector "#search-empty"
    click_link "Cancella"
    assert_current_path "/search"
    assert_field "q", with: ""
    visit "/search?q=equazone"
    assert_selector ".search-hit"
  end

  test "the menu offers the search and marks it on its page" do
    visit "/subjects"
    click_link "Cerca"
    assert_current_path "/search"
    assert_selector "#menu-search[aria-current=page]"
    assert_selector "input[type=search]:focus"
  end
end
