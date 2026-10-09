require_relative "student_course_world"

# A lesson/2 revision for the student's page (R2). The body is the *served* form (what the browser is told),
# written by hand from invented content in test/fixtures/lesson2/served/. Until Lessons::StudentBody (R1) is
# loaded, a stand-in returns the stored body as it is, which is only right for these fixtures. When the real
# projection exists, this world must store the author form of the same lessons instead (see the R2 report).
unless defined?(Lessons::StudentBody)
  module Lessons
    module StudentBody
      def self.for(revision, seed:) = revision.body
    end
  end
end

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
