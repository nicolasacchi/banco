require "application_system_test_case"
require_relative "../support/student_session"
require_relative "../support/course_path_world"

class TeacherCourseShotsTest < ApplicationSystemTestCase
  include DecisionWorld
  include StudentSession
  include CoursePathWorld

  setup do
    build_course_path_world
    path_finding!(@ready_items.first)
    path_finding!(@ready_items[1], severity: "minor", opinions: [ "author_right" ])
    practice_on_ready!
    sign_in_as :teacher
  end
  teardown { sign_out_env }

  # Screenshots of the path and the review at a laptop and a phone size; only when BANCO_SHOT_DIR names a folder.
  test "shots" do
    dir = ENV["BANCO_SHOT_DIR"].presence or skip "BANCO_SHOT_DIR is not set"
    prefix = ENV.fetch("BANCO_SHOT_PREFIX", "shot")
    [ [ 1366, 900, "1366" ], [ 390, 844, "390" ] ].each do |w, h, label|
      page.driver.resize(w, h)
      visit "/teacher/subjects/math/course"
      assert_selector "h1"
      sleep 0.5
      page.driver.save_screenshot(File.join(dir, "#{prefix}-course-#{label}.png"), full: true)
      visit "/teacher/subjects/math/topics/#{CoursePathWorld::READY}"
      assert_selector "h1"
      sleep 1.5
      page.driver.save_screenshot(File.join(dir, "#{prefix}-topic-#{label}.png"), full: true)
    end
  end
end
