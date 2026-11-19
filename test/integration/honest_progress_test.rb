require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-367: the progress is told honestly. «Già sapevi» (done because the entry test showed it, never studied) is apart from «Fatti con gli
# esercizi», per subject and overall, on Materie, Materia and Oggi and over the API; the time still to study is in round hours, never a
# percentage; Materia adds «Esercizi giusti». No count of D-326 changes: done = known + exercises. Invented content only.
class HonestProgressTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  Tally = Course::StudentView::Tally

  # The entry test showed this one topic: its skill is seeded as demonstrated and the student never touched it.
  KNOWN = PROGRESS_TODO

  setup { build_progress_world }

  def page(path, headers: OFFICIAL) = on(:web, path, headers: headers, remote_addr: EDGE)

  # The diagnosis seeds the skill of KNOWN as demonstrated, when the entry test was done (20 days ago, as the world's clock).
  def with_known(topic = KNOWN, &block)
    skill = "math.#{topic.split('.').last}"
    seeds = { skill => Practice::Seed.new(skill: skill, state: "demonstrated", at: Time.current - 21.days, run_id: 1, implied: false) }
    Practice::Seeder.stub(:call, seeds, &block)
  end

  def lines(selector) = css_select("#{selector} .progress-line").to_h { |li| [ li["data-line"], li.text.squish ] }

  test "a topic the entry test showed is «Già sapevi», the others «Fatti con gli esercizi»; done stays their sum" do
    with_known do
      page("/subjects")
      assert_response :success
      math = lines("li.subject[data-subject=math]")
      assert_equal "Obbligatori: 3 argomenti", math["required"]
      assert_equal "Già sapevi: 1", math["known"]
      assert_equal "Fatti con gli esercizi: 1", math["exercises"]
      assert_equal "Da studiare ancora: meno di un'ora", math["time"], "only the topic begun is left, 20 minutes"
      assert_equal "Facoltativi: 2. Già sapevi: 0. Fatti con gli esercizi: 1.", math["optional"]
      assert_select "li.subject[data-subject=math] [role=progressbar]", 0
      assert_no_match(/%/, css_select("li.subject[data-subject=math]").text)
      api_progress = Course::StudentProgress.new(@official).as_json
      assert_equal 2, api_progress.dig(:overall, :programme, :done), "the seeded topic is done, as before (D-326): the count does not change"
    end
  end

  test "Materia: the split in the summary, in each section's count, and the right exercises" do
    with_known do
      page("/subjects/math")
      summary = lines("#subject-summary")
      assert_equal "Già sapevi: 1", summary["known"]
      assert_equal "Fatti con gli esercizi: 1", summary["exercises"]
      assert_equal "Esercizi giusti: 7", summary["correct"], "3 + 1 in the programme, 3 in the optional topic: the seeded skill has none"
      assert_select "#programme-section [data-section-count=known]", "Già sapevi: 1"
      assert_select "#programme-section [data-section-count=exercises]", "Con gli esercizi: 1"
      assert_select "#extra-topics-section [data-section-count=known]", "Già sapevi: 0"
      assert_select "#extra-topics-section [data-section-count=exercises]", "Con gli esercizi: 1"
      assert_select "#topics li[data-topic=?][data-status=done]", KNOWN, 1, "a known topic is Fatto on Materia as before"
    end
  end

  test "Oggi: the same lines overall" do
    with_known do
      page("/today")
      path = lines("#my-path")
      assert_equal [ "Obbligatori: 3 argomenti", "Già sapevi: 1", "Fatti con gli esercizi: 1" ], path.values_at("required", "known", "exercises")
      assert_equal "Da studiare ancora: meno di un'ora", path["time"]
      assert_select "#my-path [role=progressbar]", 0
    end
  end

  test "a topic whose skill was seeded but then answered wrong and recovered counts with the exercises" do
    skill = "math.#{KNOWN.split('.').last}"
    seeded_before = Time.current - 40.days
    seeds = { skill => Practice::Seed.new(skill: skill, state: "demonstrated", at: seeded_before, run_id: 1, implied: false) }
    Practice::Seeder.stub(:call, seeds) do
      choice = serve!(student: @official, topic: @progress_topics.fetch(KNOWN), skill: skill)
      answer!(choice, wrong_raw, student: @official)
      page("/subjects")
      math = lines("li.subject[data-subject=math]")
      assert_equal "Già sapevi: 0", math["known"], "the skill went to review: it is not done, and not known"
      assert_equal "Fatti con gli esercizi: 1", math["exercises"]
    end
  end

  test "the hours: the minutes of the topics not done, rounded and kind; never a percentage" do
    t = ->(minutes) { Tally.new(total: 5, done: 1, in_progress: 0, known: 0, minutes_left: minutes) }
    assert_equal 0, t.(0).hours_left
    assert_equal 0, t.(40).hours_left, "less than three quarters of an hour is «meno di un'ora»"
    assert_equal 1, t.(45).hours_left
    assert_equal 2, t.(100).hours_left
    assert_equal 8, t.(450).hours_left
    assert_equal 19, t.(1_130).hours_left
    assert_equal 20, t.(1_200).hours_left, "from 20 hours the nearest five"
    assert_equal 150, t.(9_000).hours_left
    assert_equal 150, t.(9_100).hours_left
    assert_equal 155, t.(9_300).hours_left
    summed = t.(600) + t.(300)
    assert_equal [ 900, 15 ], [ summed.minutes_left, summed.hours_left ]
    assert_equal 2, (Tally.new(total: 2, done: 1, in_progress: 0, known: 1) + Tally.new(total: 3, done: 3, in_progress: 0, known: 1)).known, "the tallies sum"
  end

  test "the lines in words: the hours, in Italian and in English, with no percentage" do
    render = lambda do |tally, locale|
      I18n.with_locale(locale) { ApplicationController.render(partial: "course/required_lines", locals: { required: tally }) }.then { |html| Nokogiri::HTML.fragment(html).css("li").map { |li| li.text.squish } }
    end
    big = Tally.new(total: 250, done: 19, in_progress: 0, known: 18, minutes_left: 9_000)
    assert_equal [ "Obbligatori: 250 argomenti", "Già sapevi: 18", "Fatti con gli esercizi: 1", "Da studiare ancora: circa 150 ore" ], render.(big, :it)
    assert_equal [ "Required: 250 topics", "Already known: 18", "Done with the exercises: 1", "Still to study: about 150 hours" ], render.(big, :en)
    one = Tally.new(total: 2, done: 1, in_progress: 0, known: 0, minutes_left: 60)
    assert_equal "Da studiare ancora: circa 1 ora", render.(one, :it).last
    assert_equal "Still to study: about 1 hour", render.(one, :en).last
    assert_equal "Non resta niente da studiare.", render.(Tally.new(total: 2, done: 2, in_progress: 0, known: 2), :it).last
    assert_equal "Nothing is left to study.", render.(Tally.new(total: 2, done: 2, in_progress: 0, known: 2), :en).last
    assert_equal [ "Obbligatori: nessuno" ], render.(Tally.new(total: 0, done: 0, in_progress: 0), :it)
  end

  test "in English the pages carry the English twins" do
    Diagnosis::Preferences.record(Student.find_by!(key: "student"), language: "en")
    with_known do
      page("/subjects/math")
      summary = lines("#subject-summary")
      assert_equal "Required: 3 topics", summary["required"]
      assert_equal "Already known: 1", summary["known"]
      assert_equal "Done with the exercises: 1", summary["exercises"]
      assert_equal "Still to study: less than an hour", summary["time"]
      assert_equal "Correct exercises: 7", summary["correct"]
      assert_equal "Optional: 2. Already known: 0. Done with the exercises: 1.", summary["optional"]
      assert_select "#programme-section [data-section-count=known]", "Already known: 1"
      assert_select "#programme-section [data-section-count=exercises]", "Done with exercises: 1"
      page("/today")
      assert_equal "Already known: 1", lines("#my-path")["known"]
    end
  end
end
