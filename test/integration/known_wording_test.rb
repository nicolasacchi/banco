require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-378: one wording for a topic the entry test showed («Già sapevi», English «Already known») on the subject list, the topic page, the practice
# header and the exercise list, and one for a topic done with the exercises («Fatto»); a done topic's exercise list says so instead of «0 fatti su 3»;
# a counter and the line next to it never contradict each other. Invented content only.
class KnownWordingTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  # The entry test showed this one topic: its skill is seeded as demonstrated and the student never touched it.
  KNOWN = PROGRESS_TODO
  KNOWN_SKILL = "math.#{KNOWN.split('.').last}".freeze

  setup { build_progress_world }

  def page(path, headers: OFFICIAL) = on(:web, path, headers: headers, remote_addr: EDGE)

  def json(path)
    on(:web, path, headers: OFFICIAL.merge("Accept" => "application/json"), remote_addr: EDGE)
    response.parsed_body
  end

  def with_known(&block)
    seeds = { KNOWN_SKILL => Practice::Seed.new(skill: KNOWN_SKILL, state: "demonstrated", at: Time.current - 21.days, run_id: 1, implied: false) }
    Practice::Seeder.stub(:call, seeds, &block)
  end

  def english! = Diagnosis::Preferences.record(Student.find_by!(key: "student"), language: "en")

  def pills(selector) = css_select("#{selector} .pill").map { |pill| pill.text.squish }

  # ---- the subject list ---------------------------------------------------------------------------------------

  test "the list: «Già sapevi» for a topic the entry test showed, «Fatto» for one done with the exercises; both are done for the counts" do
    with_known do
      page("/subjects/math")
      assert_response :success
      assert_includes pills("li.topic[data-topic='#{KNOWN}']"), "Già sapevi"
      assert_not_includes pills("li.topic[data-topic='#{KNOWN}']"), "Fatto"
      assert_includes pills("li.topic[data-topic='#{TOPIC}']"), "Fatto"
      assert_not_includes pills("li.topic[data-topic='#{TOPIC}']"), "Già sapevi"
      assert_select "li.topic[data-topic='#{KNOWN}'][data-status=done]", 1, "the count of D-326 is unchanged: a known topic is done"
      assert_select "#subject-summary .progress-line[data-line=known]", "Già sapevi: 1"
    end
  end

  test "in English: «Already known» and «Done»" do
    english!
    with_known do
      page("/subjects/math")
      assert_includes pills("li.topic[data-topic='#{KNOWN}']"), "Already known"
      assert_includes pills("li.topic[data-topic='#{TOPIC}']"), "Done"
      assert_select "#subject-summary .progress-line[data-line=known]", "Already known: 1"
    end
  end

  # ---- the topic page and the practice header -----------------------------------------------------------------

  test "the topic page: the skill of a known topic is «Già sapevi» with its reason; the skill done with the exercises is «Dimostrata»" do
    with_known do
      page("/topics/#{KNOWN}")
      assert_select "li.skill[data-skill='#{KNOWN_SKILL}'] .skill-side .pill", "Già sapevi"
      assert_select "li.skill[data-skill='#{KNOWN_SKILL}'] .topic-why", /\AGià sapevi: l'hai dimostrato nel test d'ingresso del \d\d\/\d\d\/\d{4}\.\z/
      assert_select ".skill-side .pill", text: "Dimostrata", count: 0
      page("/topics/#{TOPIC}")
      assert_select "li.skill[data-skill='#{SKILL}'] .skill-side .pill", "Dimostrata"
      assert_select ".skill-side .pill", text: "Già sapevi", count: 0
    end
  end

  test "the practice header says the same words as the list and the topic page" do
    with_known do
      page("/topics/#{KNOWN}/practice/#{KNOWN_SKILL}")
      assert_select "#skill-state", "Già sapevi"
      assert_select "#skill-why", /\AGià sapevi: /
      page("/topics/#{TOPIC}/practice/#{SKILL}")
      assert_select "#skill-state", "Dimostrata"
    end
  end

  test "in English the header and the topic page say «Already known»" do
    english!
    with_known do
      page("/topics/#{KNOWN}/practice/#{KNOWN_SKILL}")
      assert_select "#skill-state", "Already known"
      assert_select "#skill-why", /\AAlready known: you showed it in the entry test of \d\d\/\d\d\/\d{4}\.\z/
      page("/topics/#{KNOWN}")
      assert_select "li.skill .skill-side .pill", "Already known"
    end
  end

  # ---- the exercise list --------------------------------------------------------------------------------------

  test "the exercise list says whether the topic is done and whether it was known, so the page can say it instead of «0 fatti su 3»" do
    with_known do
      known = json("/practice/exercises?topic=#{KNOWN}")
      assert_equal [ true, true ], [ known["done"], known["known"] ]
      assert known["skills"].flat_map { |s| s["exercises"] }.all? { |e| e["status"] == "todo" }, "none of its exercises was done: the list must not count them"
      assert_equal "Già sapevi", known["skills"].first["state_it"]
      studied = json("/practice/exercises?topic=#{TOPIC}")
      assert_equal [ true, false ], [ studied["done"], studied["known"] ]
      begun = json("/practice/exercises?topic=#{PROGRESS_STARTED}")
      assert_equal [ false, false ], [ begun["done"], begun["known"] ]
    end
  end

  test "the words of the list are in the page's labels, Italian and English: the topic done, the topic known, the optional exercise" do
    page("/topics/#{TOPIC}/practice/#{SKILL}")
    labels = JSON.parse(css_select("main.practice").first["data-practice-labels-value"])
    assert_equal [ "Questo argomento lo sapevi già", "Argomento fatto", "Facoltativo" ], labels.values_at("exercises_topic_known", "exercises_topic_done", "status_optional")
    english!
    page("/topics/#{TOPIC}/practice/#{SKILL}")
    labels = JSON.parse(css_select("main.practice").first["data-practice-labels-value"])
    assert_equal [ "You already knew this topic", "Topic done", "Optional" ], labels.values_at("exercises_topic_known", "exercises_topic_done", "status_optional")
  end

  # ---- «Corrette senza aiuto: N su 3» and what is missing ------------------------------------------------------

  test "two right without help: the line says «2 su 3» and what is missing never says «ti mancano 2» of the plain count" do
    1.times do # the world already played one right answer in this topic
      choice = serve!(student: @official, topic: @progress_topics.fetch(PROGRESS_STARTED), skill: "math.#{PROGRESS_STARTED.split('.').last}")
      answer!(choice, correct_raw(choice), student: @official)
    end
    page("/topics/#{PROGRESS_STARTED}/practice/math.#{PROGRESS_STARTED.split('.').last}")
    assert_select "#skill-why", "Corrette senza aiuto: 2 su 3."
    missing = css_select("#skill-missing").first.text.squish
    assert_no_match(/Ti mancano 2 esercizi giusti senza aiuto\./, missing, "«2 su 3» and «ti mancano 2» about the same count contradict each other")
  end
end
