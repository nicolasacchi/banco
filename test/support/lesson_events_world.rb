require_relative "student_course_world"

# A lesson/2 with its answers, for the endpoints of R3 (events, checks, full.json). The body is the real parse of the
# invented fixture test/fixtures/lesson2/demo.md, stored as the app stores it; the course around it is
# StudentCourseWorld's. The helpers find a check by what it is, and the shown id of an option for this student.
module LessonEventsWorld
  include StudentCourseWorld

  def lesson_body
    md = File.read(Rails.root.join("test/fixtures/lesson2/demo.md"))
    @parsed_lesson2 ||= Lessons::Parser2.call(md, Validation::Findings.new).body.merge("key" => TOPIC)
  end

  def stored_body = @lesson_revision.reload.body

  # [card n, block n, block] of the first block that satisfies the condition
  def find_block(&condition)
    stored_body["cards"].each { |c| c["blocks"].each { |b| return [ c["n"], b["n"], b ] if condition.call(c, b) } }
    nil
  end

  def student_key_of(student) = student.key

  # The id the page shows for the option whose stored id is +stored+ (choice) for this student's seed.
  def shown_id(student, card, block, stored)
    check = stored_body["cards"].find { |c| c["n"] == card }["blocks"].find { |b| b["n"] == block }
    seed = Lessons::StudentBody.seed_for(student.key, @lesson_revision.id, card, block)
    Lessons::Checks.id_map(check, seed).key(stored)
  end
end
