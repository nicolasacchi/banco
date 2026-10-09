require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson2_page_world"

# The page of a lesson/2 (R2, A10): the projection in the page, the controller's values, the switch, the
# preferences the page saves, and the generated files that the browser's code depends on.
class Lesson2PageTest < ActionDispatch::IntegrationTest
  include MultiUser
  include Lesson2PageWorld

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  test "a lesson/2 is drawn by the page of version 2 from the student's projection" do
    build_lesson2_world(approve: false, release: false)
    page(TRIAL, "/topics/#{TOPIC}/lesson")
    assert_response :success
    assert_select "#lesson-root[data-controller=lesson2]"
    assert_select "#lesson-root[data-lesson2-safe-value=false]"
    assert_select "#lesson-root[data-lesson2-view-value=cards]"
    assert_select "link[href*='lesson']", minimum: 2
    json = css_select("script#lesson-body").first.text
    body = JSON.parse(json)
    assert_equal "banco.lesson/2", body["schema"]
    assert_equal 13, body["cards"].size
    assert_select "section#section-why", 0
    labels = JSON.parse(css_select("#lesson-root").first["data-lesson2-labels-value"])
    assert_equal "Comincia", labels["start"]
  end

  test "BANCO_LESSON2_ENABLED=0 draws the page in safe mode (the long column)" do
    build_lesson2_world(approve: false, release: false)
    ENV["BANCO_LESSON2_ENABLED"] = "0"
    page(TRIAL, "/topics/#{TOPIC}/lesson")
    assert_select "#lesson-root[data-lesson2-safe-value=true][data-lesson2-view-value=scroll]"
  ensure
    ENV.delete("BANCO_LESSON2_ENABLED")
  end

  test "a lesson/1 still uses its own page" do
    build_student_world(approve: false, release: false)
    page(TRIAL, "/topics/#{TOPIC}/lesson")
    assert_select "#section-why"
    assert_select "#lesson-root", 0
  end

  test "the health report shows the switch" do
    assert_equal true, Health.check(chrome: false)[:lesson2][:enabled]
    ENV["BANCO_LESSON2_ENABLED"] = "0"
    assert_equal false, Health.check(chrome: false)[:lesson2][:enabled]
  ensure
    ENV.delete("BANCO_LESSON2_ENABLED")
  end

  test "the lesson keys of the preferences are kept apart from theme and size" do
    build_lesson2_world(approve: false, release: false)
    student = Student.find_by!(key: "prova-1")
    assert_equal({ theme: "cream", size: "normal" }, Diagnosis::Preferences.for(student))
    assert_equal({ lesson_view: "cards", reduce_motion: false }, Diagnosis::Preferences.lesson(student))
    Diagnosis::Preferences.record(student, theme: "dark")
    Diagnosis::Preferences.record(student, lesson_view: "scroll", reduce_motion: "true")
    assert_equal({ theme: "dark", size: "normal" }, Diagnosis::Preferences.for(student))
    assert_equal({ lesson_view: "scroll", reduce_motion: true }, Diagnosis::Preferences.lesson(student))
    Diagnosis::Preferences.record(student, lesson_view: "nonsense")
    assert_equal "scroll", Diagnosis::Preferences.lesson(student)[:lesson_view]
  end

  test "the generated files equal their build" do
    root = Rails.root
    %w[bin/build-palette bin/build-diagram-schema bin/build-icons].each do |script|
      assert system(root.join(script).to_s, "--check", out: File::NULL), "#{script} --check"
    end
  end
end
