require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# What is still needed to close a topic (D-340): the rule once on the topic page, what each skill not yet demonstrated lacks (topic page, practice page,
# the practice answer's skill), and one line in Oggi's «Riprendi» card. The rule itself (practice/6 section 5) is untouched.
class CloseHintTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  RULE = "Per chiudere l'argomento: in ogni abilità, 3 esercizi giusti senza aiuto, almeno 2 da scrivere, abbinare o mettere in ordine.".freeze
  ONE_MORE = "Ti manca un esercizio giusto senza aiuto.".freeze

  setup do
    build_student_world
    # Mid-morning in Rome, so the answers of one test never straddle midnight.
    @clock = Diagnosis::FakeClock.new(Time.current.in_time_zone(Practice::Rules::V6::ZONE).change(hour: 10))
  end

  # n exercises answered right without help, one minute apart; the last answer's body.
  def play(count)
    count.times.map do
      choice = serve!(student: @official, topic: @topic_revision)
      answer!(choice, correct_raw(choice), student: @official)
    end.last
  end

  def page(path) = on(:web, path, headers: OFFICIAL, remote_addr: EDGE)

  test "two right without help: the topic page, the practice page and Oggi say what is missing" do
    result = play(2)
    assert_equal ONE_MORE, result.body.dig(:skill, :missing_it)

    page("/topics/#{TOPIC}")
    assert_response :success
    assert_select "#step-practice #close-rule", RULE
    assert_select "li.skill[data-skill='#{SKILL}'] .topic-why", text: "Corrette senza aiuto: 2 su 3."
    assert_select "li.skill[data-skill='#{SKILL}'] .topic-missing", text: ONE_MORE

    page("/topics/#{TOPIC}/practice/#{SKILL}")
    assert_response :success
    assert_select "#skill-why", "Corrette senza aiuto: 2 su 3."
    assert_select "#skill-missing:not([hidden])", text: ONE_MORE

    page("/topics/#{TOPIC}/lesson")
    page("/today")
    assert_select "#now-resume #now-close", text: /\APer chiuderlo: in .+ fai ancora un esercizio giusto senza aiuto\.\z/
  end

  test "three right on the same day demonstrate the skill: no missing line and Oggi no line for the topic, while the topic page keeps the rule" do
    play(3)

    page("/topics/#{TOPIC}")
    assert_select "li.skill[data-skill='#{SKILL}'][data-state=demonstrated]"
    assert_select "li.skill[data-skill='#{SKILL}'] .topic-why", text: /\ADimostrata il \d\d\/\d\d\/\d{4}: 3 esercizi giusti senza aiuto\.\z/
    assert_select "li.skill .topic-missing", 0
    assert_select "#step-practice #close-rule", RULE
    page("/topics/#{TOPIC}/practice/#{SKILL}")
    assert_select "#skill-missing[hidden]", text: ""
    page("/topics/#{TOPIC}/lesson")
    page("/today")
    assert_select "#now-close", 0
  end

  test "the sentences of what is missing, skill by skill" do
    missing = ->(why) { Practice::Messages.missing_it(why) }
    assert_equal "Ti mancano 3 esercizi giusti senza aiuto. 2 devono essere da scrivere, abbinare o mettere in ordine.", missing.({ code: :not_seen })
    assert_equal "Ti mancano 2 esercizi giusti senza aiuto. 2 devono essere da scrivere, abbinare o mettere in ordine.", missing.({ code: :in_study, n: 1, low: 0 })
    assert_equal "Ti mancano 2 esercizi giusti senza aiuto. Uno deve essere da scrivere, abbinare o mettere in ordine.", missing.({ code: :in_study, n: 1, low: 1 })
    assert_equal "Ti manca un esercizio giusto senza aiuto di quelli da scrivere, abbinare o mettere in ordine.", missing.({ code: :in_study, n: 3, low: 1 })
    assert_equal "Ti mancano 2 esercizi giusti senza aiuto di quelli da scrivere, abbinare o mettere in ordine.", missing.({ code: :in_study, n: 3, low: 0 })
    [ { code: :demonstrated }, { code: :consolidated }, { code: :to_review, previous: "consolidated" } ].each do |why|
      assert_nil missing.(why), why.inspect
    end
  end
end
