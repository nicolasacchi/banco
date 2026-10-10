require_relative "student_course_world"

# A lesson/2 revision for the student's page (R2). The body is the *served* form (what the browser is told),
# written by hand from invented content in test/fixtures/lesson2/served/. The real projection
# (Lessons::StudentBody) is applied to it by the page; it keeps a served body as it is.

module Lesson2PageWorld
  include StudentCourseWorld

  SERVED = Rails.root.join("test/fixtures/lesson2/served")

  def served_body(name) = JSON.parse(File.read(SERVED.join("#{name}.json")))

  # The course of StudentCourseWorld with its lesson replaced by a lesson/2 of the given fixture.
  def build_lesson2_world(name: "equations", **options)
    @lesson2_name = name
    build_student_world(**options)
  end

  def lesson_body = @lesson2_name ? served_body(@lesson2_name).merge("key" => TOPIC) : super
end
