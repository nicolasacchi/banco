require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/changelog_world"

# D-401, BANCO_CHANGELOG_OFF: the student keys whose «Novità» page is off. No menu entry, no dot, /novita goes to Oggi and no `changelog_viewed` is
# recorded; the teacher's preview follows the official student's setting and the teacher's own page does not change; a student who is not listed
# is unchanged.
class ChangelogOffTest < ActionDispatch::IntegrationTest
  include MultiUser
  include ChangelogWorld

  ROOT = "/teacher/preview".freeze

  setup do
    build_student_world
    @row = Student.find_by!(key: "student")
  end

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def visits(student = @row) = AppEvent.where(kind: "changelog_viewed", student_id: student.id)

  # ---- the parsing -------------------------------------------------------------------------------------------

  test "the list is parsed like the other per-student variables: blanks and repeats go, empty is nobody" do
    assert_equal [], Banco::EdgeProxy.changelog_off({})
    assert_equal [], Banco::EdgeProxy.changelog_off("BANCO_CHANGELOG_OFF" => " , ")
    assert_equal %w[student prova-1], Banco::EdgeProxy.changelog_off("BANCO_CHANGELOG_OFF" => " student, prova-1 ,,student")
    assert Banco::EdgeProxy.changelog_off?("prova-1", "BANCO_CHANGELOG_OFF" => "student,prova-1")
    assert_not Banco::EdgeProxy.changelog_off?("prova-2", "BANCO_CHANGELOG_OFF" => "student,prova-1")
    assert_not Banco::EdgeProxy.changelog_off?("student", {})
  end

  # ---- a listed student ---------------------------------------------------------------------------------------

  test "a listed student has no menu entry, no dot and no «Novità» page: it goes to Oggi and records nothing" do
    revise!
    with_env("BANCO_CHANGELOG_OFF" => "student") do
      page(OFFICIAL, "/today")
      assert_response :success
      assert_select "nav.student-menu a#menu-today"
      assert_select "a#menu-changelog", 0
      assert_select "#changelog-dot", 0
      assert_select ".topbar-menu .menu-dot", 0, "something is new, and the menu says nothing about it"
      assert_no_difference -> { visits.count } do
        page(OFFICIAL, "/novita")
      end
      assert_redirected_to "/today"
      assert_equal 0, visits.count
    end
  end

  test "an unlisted student is unchanged: the entry, the dot, the page and the visit" do
    revise!
    with_env("BANCO_CHANGELOG_OFF" => "student") do
      page(TRIAL, "/today")
      assert_select "#menu-changelog[href='/novita']", /Novità/
      assert_select "#changelog-dot", 1
      assert_select ".topbar-menu .menu-dot", 1
      trial = Student.find_by!(key: "prova-1")
      assert_difference -> { visits(trial).count }, 1 do
        page(TRIAL, "/novita")
      end
      assert_response :success
      assert_select "h1", "Novità"
    end
  end

  test "a trial student can be listed alone: the official student keeps the page" do
    with_env("BANCO_CHANGELOG_OFF" => "prova-1") do
      page(TRIAL, "/novita")
      assert_redirected_to "/today"
      page(OFFICIAL, "/novita")
      assert_response :success
      assert_equal 1, visits.count
      page(OFFICIAL, "/today")
      assert_select "#menu-changelog"
    end
  end

  test "with the variable empty or unset nothing changes" do
    [ nil, "", " , " ].each do |value|
      with_env("BANCO_CHANGELOG_OFF" => value) do
        page(OFFICIAL, "/today")
        assert_select "#menu-changelog"
        page(OFFICIAL, "/novita")
        assert_response :success
      end
    end
  end

  test "English or Italian, the listed student's other pages are untouched" do
    with_env("BANCO_CHANGELOG_OFF" => "student") do
      Diagnosis::Preferences.record(@row, language: "en")
      page(OFFICIAL, "/settings")
      assert_response :success
      assert_select "a#menu-changelog", 0
      assert_select "a#menu-settings"
    end
  end

  # ---- the preview ---------------------------------------------------------------------------------------------

  test "the preview follows the official student's setting, so it shows what he sees" do
    with_env("BANCO_CHANGELOG_OFF" => "student") do
      page(TEACHER, "#{ROOT}/today")
      assert_response :success
      assert_select "a#menu-changelog", 0
      assert_no_difference [ "AppEvent.count", "Comment.count" ] do
        page(TEACHER, "#{ROOT}/novita")
      end
      assert_redirected_to "#{ROOT}/today"
    end
  end

  test "the preview is unchanged when only a trial student is listed, and follows the official student when it is not" do
    with_env("BANCO_CHANGELOG_OFF" => "prova-1") do
      page(TEACHER, "#{ROOT}/today")
      assert_select "#menu-changelog[href='#{ROOT}/novita']"
      page(TEACHER, "#{ROOT}/novita")
      assert_response :success
      assert_select "h1", "Novità"
    end
  end

  # ---- the teacher's own page ----------------------------------------------------------------------------------

  test "the teacher's own changelog page is unaffected, and does not link to the page that is off" do
    revise!
    page(TEACHER, "/teacher/changelog")
    assert_response :success
    assert_select "a[href='#{ROOT}/novita']"
    with_env("BANCO_CHANGELOG_OFF" => "student") do
      page(TEACHER, "/teacher/changelog")
      assert_response :success
      assert_select "a[href='#{ROOT}/novita']", 0
      assert_select "#changelog-updates li[data-topic='#{TOPIC}']"
    end
  end

  test "a guest and the teacher still get 403 on the student's page, listed or not" do
    with_env("BANCO_CHANGELOG_OFF" => "student") do
      assert_equal 403, get_as(GUEST, "/novita")
      assert_equal 403, get_as(TEACHER, "/novita")
    end
  end
end
