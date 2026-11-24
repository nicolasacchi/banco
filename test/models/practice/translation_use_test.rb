require "test_helper"
require_relative "../../support/student_course_world"

# The Italian translation opened in an exercise (D-402) as the teacher reads it: `served.translations` of the attempts log, «Traduzione aperta in N
# esercizi su M» on the practice progress and on the topic review. Informational: nothing here is an aid and no skill state moves.
class PracticeTranslationUseTest < ActiveSupport::TestCase
  include StudentCourseWorld

  setup do
    build_student_world
    @serves = Array.new(3) do
      choice = serve!(student: @official, topic: @topic_revision, skill: SKILL)
      answer!(choice, correct_raw(choice), student: @official)
      advance(86_400)
      choice.serve
    end
  end

  def opened(serve_id, scope: "item", student: @official, extra: {})
    AppEvent.create!(kind: "translation_opened", student: student, payload_json: { surface: "practice", scope: scope, serve_id: serve_id }.merge(extra).to_json)
  end

  test "by_serve groups the openings of the named serves, oldest first, and ignores events with no serve and other kinds" do
    opened(@serves[0].id)
    opened(@serves[0].id, scope: "block")
    AppEvent.create!(kind: "translation_opened", student: @official, payload_json: { surface: "lesson", scope: "card", topic: TOPIC, card: 1 }.to_json)
    AppEvent.create!(kind: "student_preference", student: @official, payload_json: { serve_id: @serves[1].id }.to_json)
    found = Practice::TranslationUse.by_serve(@serves.map(&:id))
    assert_equal [ @serves[0].id ], found.keys
    assert_equal %w[item block], found[@serves[0].id].map(&:scope)
    assert_equal({}, Practice::TranslationUse.by_serve([]))
  end

  test "line says N of M, once per exercise however many times it was opened, and nothing when none was" do
    assert_nil Practice::TranslationUse.line(@serves.map(&:id))
    opened(@serves[0].id)
    opened(@serves[0].id, scope: "block")
    opened(@serves[2].id)
    assert_equal [ 2, 3 ], Practice::TranslationUse.count(@serves.map(&:id))
    assert_equal "Traduzione aperta in 2 esercizi su 3", Practice::TranslationUse.line(@serves.map(&:id))
    assert_equal "Traduzione aperta in 1 esercizio su 1", Practice::TranslationUse.line([ @serves[0].id ])
  end

  test "the attempts log carries the openings of the serve, and none when there was none" do
    attempts = @serves.map { |serve| PracticeAttempt.where(practice_serve: serve).order(:try_number).first }
    opened(@serves[1].id)
    opened(@serves[1].id, scope: "block")
    log = Practice::AttemptLog.new(@official)
    with = log.detail(attempts[1].id)
    assert_equal %w[item block], with[:served][:translations].map { |t| t[:scope] }
    assert(with[:served][:translations].all? { |t| t[:at].present? })
    refute Practice::AttemptLog.new(@official).detail(attempts[0].id)[:served].key?(:translations)
  end

  test "a student's progress counts his own serves only" do
    opened(@serves[0].id)
    assert_nil Teacher::PracticeProgress.new(@subject, @trial).translation_line
  end

  test "the practice progress says it for the subject and for a skill" do
    progress = Teacher::PracticeProgress.new(@subject, @official)
    assert_nil progress.translation_line
    opened(@serves[0].id)
    opened(@serves[1].id)
    fresh = Teacher::PracticeProgress.new(@subject, @official)
    assert_equal "Traduzione aperta in 2 esercizi su 3", fresh.translation_line
    assert_equal "Traduzione aperta in 2 esercizi su 3", fresh.translation_line(SKILL)
    assert_nil fresh.translation_line("math.unknown")
  end

  test "the topic review says it over the real students' serves of the topic, not the preview's" do
    review = Teacher::TopicReview.new(@subject, TOPIC)
    assert_nil review.translation_line
    opened(@serves[0].id)
    preview = Student.current_preview
    preview_serve = serve!(student: preview, topic: @topic_revision, skill: SKILL).serve
    opened(preview_serve.id, student: preview)
    assert_equal "Traduzione aperta in 1 esercizio su 3", Teacher::TopicReview.new(@subject, TOPIC).translation_line
  end

  test "opening is not an aid: the skill state and the counts are what they were" do
    before = Practice::Fold.call(seeds: {}, tries: Practice::Loader.for(@official, subject: @subject).tries, serves: Practice::Loader.for(@official, subject: @subject).serves, skills: [ SKILL ])[SKILL].counts
    @serves.each { |serve| opened(serve.id) }
    input = Practice::Loader.for(@official, subject: @subject)
    after = Practice::Fold.call(seeds: {}, tries: input.tries, serves: input.serves, skills: [ SKILL ])[SKILL].counts
    assert_equal before, after
    assert_equal 0, after[:hints]
    assert_equal 0, PracticeAttempt.where(aided: true).count
  end
end
