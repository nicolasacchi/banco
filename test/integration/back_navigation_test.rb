require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# What the browser is told so that its arrow back works (D-355; the system tests are test/system/back_navigation*_test.rb): every page of the
# student is `no-store` (the arrow asks the server again, so Oggi and the lists are never a frozen copy and the theme just chosen is on
# them), the front door and every form post answer 303 to a page (never a page of their own, so the arrow never meets «Conferma reinvio
# modulo»), and the preview's pages are the same.
class BackNavigationHeadersTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  PAGES = [ "/today", "/subjects", "/subjects/math", "/topics/#{TOPIC}", "/topics/#{TOPIC}/lesson", "/topics/#{TOPIC}/practice/#{SKILL}",
            "/settings", "/search", "/comments", "/diagnosis" ].freeze

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def post_form(headers, path, params = {})
    on(:web, "/settings", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge("X-CSRF-Token" => token.to_s), params: params, remote_addr: EDGE)
  end

  test "every page of the student is never kept by the browser, in the student's site and in the teacher's preview" do
    build_student_world
    PAGES.each do |path|
      page(OFFICIAL, path)
      assert_response :success, path
      assert_equal "no-store", response.headers["Cache-Control"], path
    end
    [ "", "/subjects", "/settings" ].each do |path|
      page(TEACHER, "/teacher/preview#{path}")
      assert_response :success, path
      assert_equal "no-store", response.headers["Cache-Control"], "/teacher/preview#{path}"
    end
  end

  test "the front door and the settings form answer 303 to a page, so no page of the student is the answer of a post" do
    build_student_world
    page(OFFICIAL, "/")
    assert_response :see_other
    assert_redirected_to "/today"
    post_form(OFFICIAL, "/diagnosis/preferences", { theme: "dark", size: "large" })
    assert_response :see_other
    assert_redirected_to "/settings"
    assert_equal %w[dark large], Diagnosis::Preferences.for(@official).values_at(:theme, :size)
  end
end
