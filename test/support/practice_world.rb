require_relative "course_rows"
require_relative "practice_rows"

# A small practice world on top of CourseRows and PracticeRows: one visible topic with one skill and
# pinned items of invented number questions, a clock, and short ways to serve and answer.
module PracticeWorld
  include CourseRows
  include PracticeRows

  SKILL = "math.linear-equation-integer".freeze
  CLOCK_START = Time.utc(2026, 11, 2, 8, 0, 0)

  def build_practice_world(items: 2, instances: 12)
    build_course
    @student = practice_student
    @skill = SKILL
    @lesson_revision = make_lesson("ripasso.math.demo", skills: [ SKILL ])
    @clock = Diagnosis::FakeClock.new(CLOCK_START)
    pin_items(items, instances)
  end

  # New pinned items (and a new topic revision) for the same lesson; the previous serves stay.
  def pin_items(items, instances, prefix: "math-p#{Item.count}")
    @revisions = Array.new(items) { |i| make_practice_item("#{prefix}-#{i + 1}", SKILL, instances: instances) }
    @topic = make_topic(@lesson_revision, { SKILL => @revisions })
  end

  def advance(seconds = 60) = @clock.advance(seconds)

  def serve!(student: @student, topic: @topic, skill: @skill, follow: nil)
    Practice::Selector.next(student: student, topic_revision: topic, skill: skill, follow: follow, now: @clock.now)
  end

  def recorder(student: @student) = Practice::AnswerRecorder.new(student: student, clock: @clock)
  def actions(student: @student) = Practice::Actions.new(student: student, clock: @clock)

  def instance_of(choice) = choice.respond_to?(:instance) ? choice.instance : choice.item_instance

  def correct_raw(serve) = JSON.parse(instance_of(serve).answer_json).to_s
  def slip_raw(serve) = JSON.parse(instance_of(serve).errors_json).first.fetch("value").to_s
  def wrong_raw = "99999"

  # Answers a serve (a PracticeServe or a Choice) and moves the clock on a minute.
  def answer!(serve, raw, student: @student, id: nil)
    serve = serve.serve if serve.respond_to?(:serve)
    advance
    recorder(student: student).call(serve_id: serve.id, client_attempt_id: id || "cid-#{SecureRandom.hex(6)}", raw: raw, source: "text")
  end

  # Plays n serves answered correctly and unaided, one per day (default), returns the serves.
  def correct_serves!(count, days_apart: 1)
    Array.new(count) do
      choice = serve!
      answer!(choice, correct_raw(choice))
      advance(days_apart * 86_400)
      choice.serve
    end
  end
end
