require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/search_world"

# The teacher's search (D-299): every kind, every status, the latest revision of each object, the student's answers on a tab for
# the teacher alone. Guests read content and nothing a student typed.
class SearchTeacherDoorTest < ActionDispatch::IntegrationTest
  include MultiUser
  include SearchWorld

  setup do
    build_search_world
    add_draft_revision!
    add_orphan_lesson!
    add_other_course!
    add_answers!(@official, ANSWER_WORD, refused: REFUSED_WORD)
    add_answers!(@trial_student, TRIAL_ANSWER_WORD)
    add_diagnosis_answer!(@official, DIAGNOSIS_ANSWER_WORD)
    rebuild_search!
  end

  def search(headers, query, extra = "")
    on(:web, "/teacher/search?q=#{CGI.escape(query)}#{extra}", headers: headers, remote_addr: EDGE)
    response
  end

  def hits = css_select(".search-hit")

  def kinds = hits.map { |h| h["data-kind"] }.uniq

  test "the teacher finds drafts, orphans, other courses, entry-test items, hints and error texts, but not keys or solutions" do
    [ DRAFT_WORD, ORPHAN_WORD, OTHER_WORD, DIAGNOSIS_WORD, LEAKS[:hint], LEAKS[:error] ].each do |word|
      search(TEACHER, word)
      assert_response :success
      assert_predicate hits, :any?, word
    end
    [ LEAKS[:key], LEAKS[:solution], "27182", "31415" ].each do |word|
      search(TEACHER, word)
      assert_empty hits, "#{word} is an answer key or a solution: no document holds it"
    end
  end

  test "the teacher sees the latest revision of an object, the student the approved one" do
    search(TEACHER, "bilancia")
    assert_empty hits, "the newest lesson revision has no scale"
    search(TEACHER, DRAFT_WORD)
    assert_includes kinds, "lesson_card"
  end

  test "a key written whole leads to its object first" do
    search(TEACHER, TOPIC)
    assert_equal "topic", hits.first["data-kind"]
    search(TEACHER, SKILL)
    assert_equal "skill", hits.first["data-kind"]
    search(TEACHER, "leaky-item-1")
    assert_equal "item", hits.first["data-kind"]
  end

  test "keys are shown by their Italian name with the card, never bare" do
    search(TEACHER, SKILL)
    assert_select ".search-hit[data-kind=skill] .ref [data-ref-key], .search-hit[data-kind=skill] .ref[data-ref-key='#{SKILL}']"
    assert_select ".search-hit[data-kind=skill] .ref .ref-name", text: /Equazioni lineari/
    assert_select ".ref-card", minimum: 1
  end

  test "results link to the pages the teacher already has" do
    search(TEACHER, "equazione")
    links = css_select(".search-hit a").map { |a| a["href"] }
    assert(links.any? { |l| l.start_with?("/teacher/subjects/math/topics/#{TOPIC}") })
    search(TEACHER, "radice quadrata")
    assert(css_select(".search-hit a").map { |a| a["href"] }.any? { |l| l.match?(%r{\A/teacher/items/\d+\z}) })
  end

  test "the answers tab is the teacher's: the official student's answers, typed, refused and from the entry test" do
    [ ANSWER_WORD, REFUSED_WORD, DIAGNOSIS_ANSWER_WORD ].each do |word|
      search(TEACHER, word, "&tab=answers")
      assert_response :success
      assert_equal [ "student_answer" ], kinds, word
      assert_includes css_select(".search-answer").map(&:text).join, word
    end
    search(TEACHER, TRIAL_ANSWER_WORD, "&tab=answers")
    assert_empty hits, "a trial student's answers are on the page of that student"
    search(TEACHER, TRIAL_ANSWER_WORD, "&tab=answers&student=prova-1")
    assert_equal [ "student_answer" ], kinds
    search(TEACHER, ANSWER_WORD, "&tab=answers&student=prova-1")
    assert_empty hits, "one student's answers never come with another's"
  end

  test "the content tab never returns an answer" do
    [ ANSWER_WORD, TRIAL_ANSWER_WORD, REFUSED_WORD, DIAGNOSIS_ANSWER_WORD ].each do |word|
      search(TEACHER, word)
      assert_empty hits, word
      search(TEACHER, word, "&kind=student_answer")
      assert_response :forbidden, "the answers kind is not a kind of the content tab"
    end
  end

  test "a guest reads the content and never the answers, by tab or by kind or by student" do
    search(GUEST, "equazione")
    assert_response :success
    assert_predicate hits, :any?
    assert_select "#search-tab-answers", count: 0
    [ "&tab=answers", "&tab=answers&student=prova-1", "&kind=student_answer" ].each do |extra|
      search(GUEST, ANSWER_WORD, extra)
      assert_response :forbidden, extra
    end
    search(GUEST, ANSWER_WORD)
    assert_empty hits
  end

  test "the student and an anonymous caller are refused" do
    [ OFFICIAL, TRIAL, UNMAPPED ].each do |login|
      search(login, "equazione")
      assert_response :forbidden
    end
    on(:web, "/teacher/search?q=equazione", headers: TEACHER, remote_addr: "127.0.0.1")
    assert_response :forbidden
  end

  test "the filters narrow by subject, kind and status" do
    search(TEACHER, "equazione", "&subject=italian")
    assert_empty hits
    search(TEACHER, "equazione", "&kind=topic")
    assert_equal [ "topic" ], kinds
    search(TEACHER, DRAFT_WORD, "&status=draft")
    assert_predicate hits, :any?
    search(TEACHER, DRAFT_WORD, "&status=approved")
    assert_empty hits
    search(TEACHER, "equazione", "&kind=nonsense")
    assert_response :forbidden
  end

  test "the teacher's menu has Cerca and the page marks it" do
    search(TEACHER, "")
    assert_select "#menu-search[href='/teacher/search'][aria-current='page']", text: "Cerca"
    assert_select "#search-hint"
  end

  test "before the index is built the page says how to build it" do
    Search::Index.clear!
    search(TEACHER, "equazione")
    assert_select "#search-not-ready"
  end
end
