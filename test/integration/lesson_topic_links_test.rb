require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson_links_world"

# A link to another topic inside a lesson's text (argomento:KEY): S opens it when her course has the topic, and when it does not (not
# approved, not released) the page draws the words with «(non ancora disponibile)» instead of an address that answers 404. The same page
# is the teacher's preview, whose view says which topics are open (official: as S sees them; drafts: the unapproved ones too).
class LessonTopicLinksTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonLinksWorld

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def unavailable(headers, path)
    page(headers, path)
    assert_response :success
    JSON.parse(css_select("#lesson-root").first["data-lesson2-unavailable-value"])
  end

  test "S's lesson page names the linked topics her course does not open, and only those" do
    build_student_world
    assert_equal [ CLOSED_KEY ], unavailable(OFFICIAL, "/topics/#{TOPIC}/lesson")
    assert_includes css_select("#lesson-body").first.text, "](argomento:#{TOPIC})"
  end

  test "a trial student's page does the same" do
    build_student_world(approve: false, release: false)
    assert_equal [ CLOSED_KEY ], unavailable(TRIAL, "/topics/#{TOPIC}/lesson")
  end

  test "the teacher's preview says it for the view it is in: official sees what S sees, drafts what a trial student sees" do
    build_student_world(approve: false, release: false)
    page(TEACHER, "/teacher/preview/topics/#{TOPIC}/lesson")
    assert_response :not_found, "nothing is released: the official view has no topic"
    on(:web, "/teacher/preview/view", method: :post, headers: TEACHER.merge("X-CSRF-Token" => csrf_for(TEACHER)), params: { view: "drafts" }, remote_addr: EDGE)
    assert_equal [ CLOSED_KEY ], unavailable(TEACHER, "/teacher/preview/topics/#{TOPIC}/lesson")
  end

  test "the preview in its official view of a released course says it too" do
    build_student_world
    assert_equal [ CLOSED_KEY ], unavailable(TEACHER, "/teacher/preview/topics/#{TOPIC}/lesson")
  end

  def csrf_for(headers)
    page(headers, "/teacher/preview/today")
    css_select("meta[name=csrf-token]").first&.[]("content").to_s
  end
end
