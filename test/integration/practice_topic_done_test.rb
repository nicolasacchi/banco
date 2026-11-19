require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# The end of a topic (D-366): when every skill of the topic is demonstrated (by the practice or by the entry test), the practice page serves no
# more exercises on its own: the reply is the closing screen, which names the next topic (the one of Course::StudentView#next_topic) and the way
# back to Oggi, and speaks of this topic only. An exercise chosen from the list is still served: it is a screen, not a lock. The preview shows
# the same, with its own addresses; the English twin is the page's language; the entry test has none.
class PracticeTopicDoneTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  PREVIEW = "/teacher/preview".freeze
  KEYS = %w[next offer_it skill title_it today type].freeze
  TITLE_IT = "Hai finito questo argomento!".freeze
  OFFER_IT = "Vuoi farne un altro? Eccolo:".freeze

  # TOPIC (done, played by the official student), PROGRESS_STARTED (one right of three), PROGRESS_TODO, and the optional PROGRESS_EXTRA_DONE (done).
  setup { build_progress_world }

  # The world's own topic holds SKILL; the topics of the progress world each hold math.<last word of the key>.
  def skill_for(topic) = topic == TOPIC ? SKILL : "math.#{topic.split('.').last}"

  def post_json(headers, path, body = {}, root: "")
    on(:web, "#{root}/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(headers, topic, root: "", **extra) = post_json(headers, "#{root}/practice/serves", { topic: topic, skill: skill_for(topic), **extra }, root: root)

  def answer_right(headers, serve, root: "")
    raw = correct_raw(PracticeServe.find(serve["serve_id"]))
    post_json(headers, "#{root}/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: raw, source: "text" }, root: root)
  end

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  # The seeds of the entry test: these skills come out demonstrated.
  def with_demonstrated_seeds(*topics, &block)
    seeds = topics.to_h do |topic|
      skill = skill_for(topic)
      [ skill, Practice::Seed.new(skill: skill, state: "demonstrated", at: Time.current - 30.days, run_id: 1, implied: false) ]
    end
    Practice::Seeder.stub(:call, seeds, &block)
  end

  test "the last skill demonstrated: the next call is the closing screen, with the next topic and the way back to Oggi" do
    topic = PROGRESS_STARTED
    first = serve_for(OFFICIAL, topic)
    assert_equal "item", first["type"], "the topic is not done yet: an exercise"
    assert_equal "correct", answer_right(OFFICIAL, first)["outcome"]
    second = serve_for(OFFICIAL, topic, advance: true)
    assert_equal "item", second["type"], "two right of three"
    assert_equal "in_study", Course::StudentView.new(Student.find_by!(key: "student")).state(skill_for(topic)).state
    last = answer_right(OFFICIAL, second)
    assert_equal "correct", last["outcome"]
    assert_equal "demonstrated", last.dig("skill", "state"), "the third right without help demonstrates the skill: the topic is done"
    serves = PracticeServe.count

    done = serve_for(OFFICIAL, topic, advance: true)
    assert_response :success
    assert_equal KEYS, done.keys.sort
    assert_equal [ "topic_done", TITLE_IT, OFFER_IT ], done.values_at("type", "title_it", "offer_it")
    assert_equal({ "topic" => PROGRESS_TODO, "title_it" => "Potenze", "label_it" => "Vai al prossimo argomento", "url" => "/topics/#{PROGRESS_TODO}" }, done["next"])
    assert_equal({ "label_it" => "Torna a Oggi", "url" => "/today" }, done["today"])
    assert_equal "demonstrated", done.dig("skill", "state")
    assert_equal serves, PracticeServe.count, "nothing was served"
    assert_equal 0, PracticePoolExhaustion.count

    assert_equal done, serve_for(OFFICIAL, topic), "a reload of the page says the same"
    assert_equal done, serve_for(OFFICIAL, topic, follow: { serve_id: second["serve_id"], kind: "after_solution" }), "also after «Un altro esercizio»"
    pick = Course::StudentView.new(Student.find_by!(key: "student")).then { |view| view.next_topic(view.find_topic(topic).first) }
    assert_equal pick.topic.key, done.dig("next", "topic"), "the same choice as Course::StudentView#next_topic"
  end

  test "it speaks of this topic only: no subject, no progress, no other word" do
    done = serve_for(OFFICIAL, TOPIC)
    assert_equal "topic_done", done["type"]
    assert_equal KEYS, done.keys.sort
    texts = [ done["title_it"], done["offer_it"], done.dig("next", "label_it"), done.dig("today", "label_it") ]
    assert_equal [ TITLE_IT, OFFER_IT, "Vai al prossimo argomento", "Torna a Oggi" ], texts
    assert_no_match(/materia|tutti|%|\d/i, texts.join(" "))
  end

  test "not a lock: an exercise chosen from the list is served, the list still has it, and the next call is the closing screen again" do
    assert_equal "topic_done", serve_for(OFFICIAL, TOPIC)["type"]
    key = JSON.parse(get_exercises(OFFICIAL, TOPIC)).dig("skills", 0, "exercises", 0, "item")
    redo_serve = serve_for(OFFICIAL, TOPIC, item: key)
    assert_equal "item", redo_serve["type"], "the exercise is served as before"
    assert_equal key, redo_serve.dig("exercise", "item")
    assert_equal "topic_done", serve_for(OFFICIAL, TOPIC, advance: true)["type"]
    assert_equal "topic_done", serve_for(OFFICIAL, TOPIC)["type"], "even with that exercise left open: only a chosen exercise is served"
  end

  def get_exercises(headers, topic, root: "")
    on(:web, "#{root}/practice/exercises?topic=#{topic}", headers: headers.merge("Accept" => "application/json"), remote_addr: EDGE)
    response.body
  end

  test "a topic known from the entry test: the screen shows as soon as he opens practice on it" do
    with_demonstrated_seeds(PROGRESS_TODO) do
      done = serve_for(OFFICIAL, PROGRESS_TODO)
      assert_equal "topic_done", done["type"]
      assert_equal "demonstrated", done.dig("skill", "state")
      assert_equal PROGRESS_STARTED, done.dig("next", "topic"), "the topic Oggi proposes now"
      assert_equal 0, PracticeServe.where(topic_revision: @progress_topics.fetch(PROGRESS_TODO)).count
    end
  end

  test "an optional topic has the screen too, and its next topic is a programme one" do
    done = serve_for(OFFICIAL, PROGRESS_EXTRA_DONE)
    assert_equal "topic_done", done["type"]
    assert_equal PROGRESS_STARTED, done.dig("next", "topic")
  end

  test "when no topic is left the screen has no offer: the title and the way back to Oggi" do
    with_demonstrated_seeds(PROGRESS_STARTED, PROGRESS_TODO) do
      done = serve_for(OFFICIAL, TOPIC)
      assert_equal [ "topic_done", TITLE_IT, nil, nil ], done.values_at("type", "title_it", "offer_it", "next")
      assert_equal({ "label_it" => "Torna a Oggi", "url" => "/today" }, done["today"])
    end
  end

  test "a topic that is not done is served as before" do
    first = serve_for(OFFICIAL, PROGRESS_TODO)
    assert_equal "item", first["type"]
    assert_equal "item", serve_for(OFFICIAL, PROGRESS_TODO, advance: true)["type"]
  end

  test "the English page: the screen's words are English, the topic's name stays Italian" do
    Diagnosis::Preferences.record(Student.find_by!(key: "student"), language: "en")
    done = serve_for(OFFICIAL, TOPIC)
    assert_equal [ "topic_done", "You have finished this topic!", "Want to do another one? Here it is:" ], done.values_at("type", "title_it", "offer_it")
    assert_equal({ "topic" => PROGRESS_STARTED, "title_it" => "Frazioni", "label_it" => "Go to the next topic", "url" => "/topics/#{PROGRESS_STARTED}" }, done["next"])
    assert_equal({ "label_it" => "Back to Today", "url" => "/today" }, done["today"])
    assert_no_match(/Hai finito|Vuoi farne|Torna a Oggi|Vai al prossimo/, done.to_json)
  end

  test "the practice page holds the closing screen, hidden, with a free slot after the buttons and no link to a schema" do
    page(OFFICIAL, "/topics/#{TOPIC}/practice/#{SKILL}")
    assert_response :success
    assert_select "main.practice section#topic-done[hidden][data-practice-target=done]" do
      assert_select "h2#topic-done-title[data-practice-target=doneTitle]"
      assert_select "p#topic-done-offer[hidden]"
      assert_select "#topic-done-actions[data-practice-target=doneActions]"
      assert_select "#topic-done-extra", text: ""
      assert_select "a", 0
    end
    assert_select "#topic-done-extra", 1
    assert_select "a[href*=schema]", 0
  end

  test "the preview: the same screen, with the preview's addresses, for the preview student alone" do
    topic = PROGRESS_STARTED
    3.times do
      serve = serve_for(TEACHER, topic, root: PREVIEW, advance: true)
      assert_equal "item", serve["type"]
      assert_equal "correct", answer_right(TEACHER, serve, root: PREVIEW)["outcome"]
    end
    done = serve_for(TEACHER, topic, root: PREVIEW, advance: true)
    assert_equal [ "topic_done", TITLE_IT, OFFER_IT ], done.values_at("type", "title_it", "offer_it")
    assert_equal({ "topic" => TOPIC, "title_it" => TOPIC_TITLE, "label_it" => "Vai al prossimo argomento", "url" => "#{PREVIEW}/topics/#{TOPIC}" }, done["next"],
                 "the preview student has not done the first topic: it comes first in the course")
    assert_equal({ "label_it" => "Torna a Oggi", "url" => "#{PREVIEW}/today" }, done["today"])
    assert_equal [ Student.current_preview.id ], PracticeServe.where(topic_revision: @progress_topics.fetch(PROGRESS_STARTED)).where.not(student_id: Student.find_by!(key: "student").id).pluck(:student_id).uniq

    page(TEACHER, "#{PREVIEW}/topics/#{topic}/practice/#{skill_for(topic)}")
    assert_response :success
    assert_select "main.practice[data-practice-base-url-value='#{PREVIEW}/practice'] section#topic-done[hidden]"
  end

  test "the entry test has no closing screen: nothing of the sitting's pages or scripts knows it" do
    files = Dir[Rails.root.join("app/views/{sittings,diagnosis,warmup}/**/*").to_s, Rails.root.join("app/javascript/items/**/*.js").to_s,
                Rails.root.join("app/controllers/{sittings,diagnosis,warmup}_controller.rb").to_s].select { |f| File.file?(f) }
    assert_not_empty files
    files.each { |f| assert_no_match(/topic[_-]done/, File.read(f), f) }
  end

  test "the rule is a screen: no state, no row, no number changed by showing it" do
    before = [ PracticeServe.count, PracticeAttempt.count, PracticeDraft.count, PracticePoolExhaustion.count ]
    3.times { serve_for(OFFICIAL, TOPIC) }
    assert_equal before, [ PracticeServe.count, PracticeAttempt.count, PracticeDraft.count, PracticePoolExhaustion.count ]
    assert_equal "demonstrated", Course::StudentView.new(Student.find_by!(key: "student")).state(SKILL).state
  end
end
