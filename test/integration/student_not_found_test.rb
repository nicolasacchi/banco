require "test_helper"
require_relative "../support/multi_user"

# D-378: a mistyped or stale address gives the student his own 404 (D-361) in his language, with his menu and «Commenta»; everybody else keeps the bare
# 404 of the catch-all, and a POST or another listener is not touched.
class StudentNotFoundTest < ActionDispatch::IntegrationTest
  include MultiUser

  def page(path, headers: OFFICIAL) = on(:web, path, headers: headers, remote_addr: EDGE)

  def english! = Diagnosis::Preferences.record(Student.create_with(kind: "student").find_or_create_by!(key: "student"), language: "en")

  test "in Italian: his own page, with the menu and the comment box" do
    page("/zzz")
    assert_response :not_found
    assert_select "html[lang=it]"
    assert_select "#error-page h1", "Questa pagina non c'è"
    assert_select "#error-page a.button[href='/today']", "Torna a Oggi"
    assert_select "#student-menu-open", /Menu/
    assert_select "[data-comment-open]"
    assert_select "#comment-root[data-comment-page-path-value='/not-found/zzz']"
  end

  test "in English: the words, the language of the page and the menu are English" do
    english!
    %w[/zzz /topics /subjects/mathematics /topics/zz.nope/lesson].each do |path|
      page(path)
      assert_response :not_found, path
      assert_select "html[lang=en]", 1, path
      assert_select "#error-page h1", "This page is not there", path
      assert_select "#error-page p", "The address may be wrong, or the page has moved.", path
      assert_select "#error-page a.button", "Back to Today", path
      assert_select "#not-found-hint", /tap Comment/, path
      assert_no_match(/Questa pagina|Torna a|Commenta|Materie/, response.body, path)
    end
  end

  test "the teacher, a guest and someone unknown get the bare 404, with no menu and no student's cookie" do
    [ TEACHER, GUEST, {} ].each do |headers|
      page("/zzz", headers: headers)
      assert_response :not_found, headers.inspect
      assert_select "#error-page h1", "Questa pagina non c'è"
      assert_select "#error-page a.button[href='/']", "Torna all'inizio"
      assert_select "#student-menu-open", 0
      assert_nil response.headers["Set-Cookie"].to_s[/#{DecisionRecorder::DEVICE_COOKIE}/], "only a student's own request marks the computer"
    end
  end

  test "a HEAD to an unknown address is a read of a page like a GET: his own 404 is rendered, the body is dropped by the server (D-381)" do
    on(:web, "/zzz", method: :head, headers: OFFICIAL, remote_addr: EDGE)
    assert_response :not_found
    assert_predicate response.body, :empty?
    assert_includes response.headers["Link"].to_s, "rel=preload", "the student's layout was rendered (its stylesheets are preloaded), not a bare head"
  end

  test "a POST to an unknown address and an unconfigured student stay bare 404" do
    on(:web, "/zzz", method: :post, headers: OFFICIAL, remote_addr: EDGE)
    assert_response :not_found
    assert_select "#student-menu-open", 0
    page("/zzz", headers: UNMAPPED)
    assert_response :not_found
    assert_select "#student-menu-open", 0
  end
end
