require "application_system_test_case"
require_relative "../support/student_course_world"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# D-321: an item's figure is seen by the student, in a sitting and in practice, at 390 px.
class ItemFiguresSystemTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentUiRows
  include StudentSession

  SHOT_DIR = ENV.fetch("BANCO_SHOT_DIR", File.join(Dir.tmpdir, "banco-shots"))
  SVG = <<~SVG.freeze
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 200">
      <rect x="2" y="2" width="296" height="196" fill="#fffbe8" stroke="#555"/>
      <polygon points="50,170 250,170 50,40" fill="#cfe8ff" stroke="#1a4f8b" stroke-width="3"/>
      <text x="140" y="190" font-size="16" font-family="sans-serif">base 12 cm</text>
      <text x="8" y="110" font-size="16" font-family="sans-serif">h</text>
    </svg>
  SVG

  setup do
    @dir = Dir.mktmpdir
    Rails.application.config.x.item_assets_dir = @dir
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    FileUtils.mkdir_p(SHOT_DIR)
  end

  teardown do
    sign_out_env
    Rails.application.config.x.item_assets_dir = nil
    FileUtils.rm_rf(@dir)
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  def assert_picture_shown(width)
    assert_selector ".prompt figure img.figure[alt^='Un triangolo']", wait: 30
    loaded = page.evaluate_script("(function(){ var i = document.querySelector('.prompt img.figure'); return i.complete && i.naturalWidth > 0 })()")
    assert loaded, "the image did not load"
    box = page.evaluate_script("(function(){ var r = document.querySelector('.prompt img.figure').getBoundingClientRect(); return [r.width, r.height, r.right] })()")
    assert_operator box[0], :>, 150, "the picture is readable"
    assert_operator box[2], :<=, width
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
  end

  test "a sitting shows the figure at 390 px" do
    rows = build_ui_subject(components: %w[choice], figure_svg: SVG)
    release_diagnosis!
    assert rows
    ENV.delete("BANCO_STUDENT_USERS")
    sign_in_as :student
    page.driver.resize(390, 844)
    visit "/diagnosis"
    click_button "Comincia"
    assert_text "Test d'ingresso · Matematica"
    click_button "Comincia"
    assert_picture_shown(390)
    page.driver.save_screenshot(File.join(SHOT_DIR, "sitting-390.png"), full: true)
  end

  test "practice shows the figure at 390 px and at 1280 px" do
    build_student_world(figure_svg: SVG)
    sign_in_as :student
    page.driver.headers = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }
    page.driver.resize(390, 844)
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_picture_shown(390)
    page.driver.execute_script("document.querySelector('.prompt img.figure').scrollIntoView({block: 'center'})")
    page.driver.save_screenshot(File.join(SHOT_DIR, "practice-390.png"))
    page.driver.resize(1280, 900)
    assert_picture_shown(1280)
    height = page.evaluate_script("document.querySelector('.prompt img.figure').getBoundingClientRect().height")
    assert_operator height, :<=, 26 * 20 + 1, "capped in height"
    page.driver.save_screenshot(File.join(SHOT_DIR, "practice-1280.png"), full: true)
  end
end
