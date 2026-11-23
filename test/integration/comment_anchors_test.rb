require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/finished_run"

# D-397: the points a student can pick for a comment. The topic page and its steps, Materie and the subject page, the lesson's sections
# and «Prova tu», the practice page's skill status and exercise list and the results of a sitting carry `data-comment-anchor`; every new
# name has its words in Italian and in English; and the server's check (Comments::Intake) takes each of them.
class CommentAnchorsTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  # name => whether its words carry the number (%{n})
  NEW_NAMES = { "step_lesson" => false, "step_practice" => false, "skill" => true, "skill_status" => false, "exercise_list" => false, "subject" => false,
                "topic" => false, "section" => false, "try" => false, "try_exercise" => true, "group" => false, "result" => true }.freeze

  def page(path) = on(:web, path, headers: OFFICIAL, remote_addr: EDGE)

  def send_comment(path, anchor)
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content").to_s
    body = { client_comment_id: "c-#{SecureRandom.hex(8)}", reason: "other", text_it: "Un punto da scegliere.", page_path: path, anchor: anchor, refs: {} }
    on(:web, "/comments", method: :post, headers: OFFICIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  test "every new anchor name has its words in Italian and in English, with a number only where the anchor has one" do
    NEW_NAMES.each do |name, numbered|
      %i[it en].each do |locale|
        words = I18n.t("comments.anchors.#{name}", locale: locale, default: nil)
        assert words.is_a?(String) && words.present?, "#{name} in #{locale}"
        assert_equal numbered, words.include?("%{n}"), "#{name} in #{locale}"
      end
    end
  end

  test "the topic page, Materie, the subject page, the lesson and the practice page have points to comment on" do
    build_student_world
    page("/topics/#{TOPIC}")
    assert_select "#step-lesson[data-comment-anchor=step_lesson]"
    assert_select "#step-practice .step-head[data-comment-anchor=step_practice]"
    assert_select "#skills li.skill[data-comment-anchor='skill:1']"
    page("/subjects")
    assert_select "#subjects li.subject[data-subject=math][data-comment-anchor='subject:math']"
    page("/subjects/math")
    assert_select "li.topic[data-topic='#{TOPIC}'][data-comment-anchor='topic:ripasso_math_demo']"
    page("/topics/#{TOPIC}/lesson")
    assert_select "section[data-section=why][data-comment-anchor='section:why']"
    assert_select "section[data-section=mistakes][data-comment-anchor='section:mistakes']"
    assert_select "#section-try[data-comment-anchor=try]"
    assert_select "#section-try li.exercise[data-comment-anchor='try_exercise:1']"
    page("/topics/#{TOPIC}/practice/#{SKILL}")
    assert_select ".skill-status[data-comment-anchor=skill_status]"
    assert_select "#exercise-list[data-comment-anchor=exercise_list]"
  end

  test "the server takes a comment on each new point and keeps the anchor" do
    build_student_world
    {
      "/topics/#{TOPIC}" => %w[step_lesson step_practice skill:1],
      "/subjects" => %w[subject:math],
      "/subjects/math" => %w[topic:ripasso_math_demo],
      "/topics/#{TOPIC}/lesson" => %w[section:why try try/try_exercise:1],
      "/topics/#{TOPIC}/practice/#{SKILL}" => %w[skill_status exercise_list]
    }.each do |path, anchors|
      anchors.each do |anchor|
        assert_equal "recorded", send_comment(path, anchor)["status"], "#{path} #{anchor}"
        assert_equal [ path, anchor ], Comment.order(:id).last.then { |c| [ c.page_path, c.anchor ] }
      end
    end
  end
end

class CommentAnchorsResultsTest < ActionDispatch::IntegrationTest
  include MultiUser
  include FinishedRun

  JSON_HEADERS = CommentAnchorsTest::JSON_HEADERS

  test "the results of a sitting have a point for each group and each solution, and the server takes a comment on them" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    conductor = Diagnosis::Conductor.new(run)
    recorder = Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis")
    5.times do
      step = conductor.step!
      break unless step.type == :item

      recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "6", source: "text")
    end
    path = "/diagnosis/runs/#{run.id}/results"
    on(:web, path, headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    assert_select "section.result-group", minimum: 1
    css_select("section.result-group").each { |n| assert_match(/\Agroup:[a-z_]+\z/, n["data-comment-anchor"].to_s) }
    assert_select "article.solution[data-attempt]", minimum: 1
    assert_select "article.solution[data-comment-anchor='result:1']", 1
    css_select("article.solution").each_with_index { |n, i| assert_equal "result:#{i + 1}", n["data-comment-anchor"] }
    %w[result:1 group:known].each do |anchor|
      on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
      token = css_select("meta[name=csrf-token]").first&.[]("content").to_s
      body = { client_comment_id: "c-#{SecureRandom.hex(8)}", reason: "other", text_it: "Qui.", page_path: path, anchor: anchor, refs: {} }
      on(:web, "/comments", method: :post, headers: OFFICIAL.merge(JSON_HEADERS, "X-CSRF-Token" => token), params: body.to_json, remote_addr: EDGE)
      assert_equal "recorded", response.parsed_body["status"], anchor
    end
    assert_equal [ "results", "group:known" ], Comment.order(:id).last.then { |c| [ c.page_kind, c.anchor ] }
  end
end
