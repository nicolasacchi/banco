require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-348: «Da riprendere» is gone from the student's words. A skill the entry test found unsure reads «Dal test: da ripassare»; the first tag on
# Oggi, Materia and the topic page carries one line saying what it means, the others do not. Teacher texts keep their own wording.
class RecoverWordingTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  TAG = "Dal test: da ripassare".freeze
  NOTE = "Vuol dire che nel test d'ingresso questa parte non era sicura: si chiude con gli esercizi.".freeze
  UNTOUCHED = [ PROGRESS_TODO, PROGRESS_EXTRA_TODO ].freeze

  setup { build_progress_world }

  def page(path) = on(:web, path, headers: OFFICIAL, remote_addr: EDGE)

  # The seeds of the entry test: every untouched skill of the world is to_recover.
  def with_seeds(&block)
    at = Time.current
    seeds = UNTOUCHED.to_h do |key|
      skill = "math.#{key.split('.').last}"
      [ skill, Practice::Seed.new(skill: skill, state: "to_recover", at: at, run_id: 1, implied: false) ]
    end
    Practice::Seeder.stub(:call, seeds, &block)
  end

  test "the state and the words read «Dal test: da ripassare»" do
    assert_equal TAG, I18n.t("states.to_recover")
    assert_equal TAG, Practice::Messages.state_it("to_recover")
    assert_equal "Da ripassare", Practice::Messages.state_it("to_review")
    assert_equal "Dal test d'ingresso: da ripassare.", I18n.t("why.seed_to_recover")
    assert_equal "Dal test è risultata da ripassare: Potenze.", I18n.t("today.reason.to_recover", skill: "Potenze")
  end

  test "Materia: the tag on each topic, the explanation once, on the first" do
    with_seeds do
      page("/subjects/math")
      assert_response :success
      UNTOUCHED.each { |key| assert_select "li.topic[data-topic=?] .row-end .pill", key, text: TAG }
      assert_select "[data-recover-note]", 1
      assert_select "[data-recover-note=to_recover]", text: NOTE
      first_tagged = css_select("li.topic").find { |li| li.css(".row-end .pill").any? { |p| p.text == TAG } }
      assert_equal 1, first_tagged.css("[data-recover-note]").size, "the line sits on the first tagged topic"
      assert_no_match(/Da riprendere/i, response.body)
    end
  end

  test "the topic page: the skill's state in the new words, the explanation once" do
    with_seeds do
      page("/topics/#{PROGRESS_TODO}")
      assert_response :success
      assert_select "#skills li.skill .pill", text: TAG
      assert_select "[data-recover-note=to_recover]", text: NOTE
      assert_select "[data-recover-note]", 1
      assert_no_match(/Da riprendere/i, response.body)
    end
  end

  test "Oggi: the reason line in the new words, the explanation once" do
    with_seeds do
      page("/today")
      assert_response :success
      assert_select "#suggestions li[data-reason=to_recover] .topic-why", text: /\ADal test è risultata da ripassare: /
      assert_select "[data-recover-note=to_recover]", text: NOTE
      assert_select "[data-recover-note]", 1
      assert_no_match(/Da riprendere/i, response.body)
    end
  end

  test "a page without the tag has no explanation" do
    page("/subjects/math")
    assert_select "[data-recover-note]", 0
    assert_select ".pill", text: TAG, count: 0
  end

  test "a skill that went wobbly after practice is «Da ripassare» with its own line, not the test's" do
    choice = serve!(student: @official, topic: @topic_revision, skill: SKILL)
    answer!(choice, wrong_raw, student: @official)
    assert_equal "to_review", Course::StudentView.new(@official).state(SKILL).state
    page("/subjects/math")
    assert_select "li.topic[data-topic=?] .row-end .pill", TOPIC, text: "Da ripassare"
    assert_select "[data-recover-note=to_review]", text: I18n.t("topic.recover_note.to_review")
    assert_select "[data-recover-note=to_recover]", 0
  end

  test "the sitting's summary says «Da ripassare», and the teacher's page keeps its words" do
    assert_equal "Da ripassare: 2.", I18n.t("summary.line_recover", n: 2)
    assert_equal "Da ripassare", I18n.t("summary.recover")
    assert_equal "Da riprendere, ancora senza argomento", I18n.t("teacher.practice.without_topic")
  end
end
