require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"
require_relative "../support/lesson_events_world"
require_relative "../support/student_ui_rows"

# D-365, «Ti è piaciuto?»: the student's door. He rates an exercise that is OVER (right, solution shown, tries used up) and the lesson he reads,
# 1 to 5 stars and a comment, both optional, one of them at least; everything the row keeps is derived by the server from what he was shown.
# The preview, a guest, the teacher and a login nobody mapped never write; another student's serve is refused; a rating changes nothing else.
class RatingsTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup do
    build_student_world(approve: true, release: true)
    @saved_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @saved_forgery }

  def rid = "r-" + SecureRandom.hex(8)

  def token_for(headers, path = "/today")
    on(:web, path, headers: headers, remote_addr: EDGE)
    css_select("meta[name=csrf-token]").first&.[]("content").to_s
  end

  def post_json(headers, path, body = {}, token: nil)
    token ||= token_for(headers)
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def rate(headers = OFFICIAL, **body) = post_json(headers, "/ratings", { client_rating_id: rid }.merge(body))

  # An exercise of the student, over because the right answer was given.
  def finished_serve(student = @official)
    choice = serve!(student: student, topic: @topic_revision)
    answer!(choice, correct_raw(choice), student: student)
    choice.serve
  end

  def lesson_body_of(topic = TOPIC) = { kind: "lesson", topic: topic, lesson_revision_id: @lesson_revision.id }

  def other_tables = ActiveRecord::Base.connection.tables - %w[ratings students app_events schema_migrations ar_internal_metadata sqlite_sequence]
  def snapshot = other_tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] }

  # ---- an exercise ------------------------------------------------------------------------------------------

  test "the student rates an exercise after it is over: the row names the item, its revision, the serve, the subject and the topic" do
    serve = finished_serve
    reply = rate(kind: "item", serve_id: serve.id, stars: 4, text_it: "Bello, mi è piaciuto.")
    assert_response :success
    assert_equal({ "status" => "recorded", "rating" => { "stars" => 4, "text_it" => "Bello, mi è piaciuto." } }, reply)
    row = Rating.sole
    revision = serve.item_instance.item_revision
    assert_equal [ @official.id, "item", revision.item.key, revision.id, serve.id ], [ row.student_id, row.target_kind, row.target_key, row.item_revision_id, row.practice_serve_id ]
    assert_equal [ @subject.id, @topic_revision.id, nil, 4, "Bello, mi è piaciuto.", "it", false ],
                 [ row.subject_id, row.topic_revision_id, row.lesson_revision_id, row.stars, row.text_it, row.language, row.trial ]
  end

  test "an exercise whose solution was shown, or whose tries are used up, is over too; an open one is refused" do
    open = serve!(student: @official, topic: @topic_revision)
    reply = rate(kind: "item", serve_id: open.serve.id, stars: 3)
    assert_response :unprocessable_entity
    assert_equal({ "status" => "invalid", "error" => "not_over" }, reply)
    assert_equal 0, Rating.count

    assert_equal :open, Practice::Loader.status_of(open.serve.reload).state
    actions(student: @official).solution(serve_id: open.serve.id)
    assert_equal :closed, Practice::Loader.status_of(PracticeServe.find(open.serve.id)).state
    assert_equal({ "status" => "invalid", "error" => "not_over" }, rate(kind: "item", serve_id: open.serve.id, stars: 2), "the solution came but he never tried (D-377)")

    tried = serve!(student: @official, topic: @topic_revision, item: @revisions.second.item.key)
    answer!(tried, wrong_raw, student: @official)
    assert_equal :open, Practice::Loader.status_of(PracticeServe.find(tried.serve.id)).state
    actions(student: @official).solution(serve_id: tried.serve.id)
    assert_equal "recorded", rate(kind: "item", serve_id: tried.serve.id, stars: 2)["status"], "one try, then the solution was shown"

    tries = serve!(student: @trial, topic: @topic_revision)
    answer!(tries, wrong_raw, student: @trial)
    answer!(tries, other_wrong_raw, student: @trial)
    assert_equal :closed, Practice::Loader.status_of(PracticeServe.find(tries.serve.id)).state
    assert_equal "recorded", rate(TRIAL, kind: "item", serve_id: tries.serve.id, text_it: "Troppo difficile.")["status"], "the tries are used up"
    assert_equal [ 2, nil ], Rating.order(:id).map(&:stars)
  end

  test "D-377: a typical error closes the serve before the solution: not over until the solution is shown; a serve of a replaced revision takes no rating" do
    serve = serve!(student: @official, topic: @topic_revision)
    answer!(serve, slip_raw(serve), student: @official)
    status = Practice::Loader.status_of(PracticeServe.find(serve.serve.id))
    assert_equal [ :closed, :wrong, false, %i[prova_questo show_solution back] ], [ status.state, status.closed_by, status.solution_sent, status.actions ]
    assert_equal({ "status" => "invalid", "error" => "not_over" }, rate(kind: "item", serve_id: serve.serve.id, stars: 1), "he is told he is wrong and can still ask for the solution")
    assert_equal 0, Rating.count
    actions(student: @official).solution(serve_id: serve.serve.id)
    assert_equal "recorded", rate(kind: "item", serve_id: serve.serve.id, stars: 3)["status"], "the solution is shown: the exercise is over"

    open = serve!(student: @official, topic: @topic_revision, item: @revisions.second.item.key)
    answer!(open, wrong_raw, student: @official) # a try, the serve stays open
    newer = make_topic(@lesson_revision, { SKILL => @revisions }, course: @course)
    approve_topic!(newer)
    reply = rate(kind: "item", serve_id: open.serve.id, stars: 5)
    assert_response :unprocessable_entity
    assert_equal "serve_id", reply["error"], "a serve of a revision he is no longer shown is refused, over or not"
  end

  test "stars alone, a comment alone, and neither: the last is refused, so are a star out of 1 to 5 and a text over 2000 characters" do
    serve = finished_serve
    assert_equal "recorded", rate(kind: "item", serve_id: serve.id, stars: 5)["status"]
    assert_equal "recorded", rate(kind: "item", serve_id: serve.id, text_it: "  Solo parole.  ")["status"]
    assert_equal [ [ 5, nil ], [ nil, "Solo parole." ] ], Rating.order(:id).pluck(:stars, :text_it)

    { {} => "empty", { stars: "", text_it: "   " } => "empty", { stars: 0 } => "stars", { stars: 6 } => "stars", { stars: "tre" } => "stars", { stars: 3.5 } => "stars",
      { stars: 3, text_it: "x" * 2001 } => "text_it", { stars: 3, kind: "page" } => "kind" }.each do |extra, error|
      reply = rate(**{ kind: "item", serve_id: serve.id }.merge(extra))
      assert_response :unprocessable_entity, extra.inspect
      assert_equal [ "invalid", error ], reply.values_at("status", "error"), extra.inspect
    end
    assert_equal "recorded", rate(kind: "item", serve_id: serve.id, stars: 1, text_it: "x" * 2000)["status"]
    assert_equal 3, Rating.count
  end

  test "the same client_rating_id is recorded once; the id of another student's rating is refused" do
    serve = finished_serve
    one = rid
    2.times { assert_equal "recorded", rate(client_rating_id: one, kind: "item", serve_id: serve.id, stars: 4)["status"] }
    assert_equal 1, Rating.where(client_rating_id: one).count
    assert_equal [ "invalid", "client_rating_id" ], rate(TRIAL, client_rating_id: one, kind: "lesson", **lesson_body_of.except(:kind)).values_at("status", "error")
    assert_equal [ "invalid", "client_rating_id" ], rate(client_rating_id: "no", kind: "item", serve_id: serve.id, stars: 4).values_at("status", "error")
  end

  test "a later rating of the same exercise is a new row, and the latest is the current one" do
    serve = finished_serve
    rate(kind: "item", serve_id: serve.id, stars: 2, text_it: "Così così.")
    rate(kind: "item", serve_id: serve.id, stars: 5, text_it: "Ora mi piace.")
    assert_equal [ 2, 5 ], Rating.order(:id).pluck(:stars)
    assert_equal 5, Rating.latest_for(@official, "item", serve.item_instance.item_revision.item.key).stars
    assert_equal 1, Rating.current.count
  end

  test "another student's serve, a serve that does not exist and a serve of a topic he cannot see are refused" do
    theirs = finished_serve(@trial)
    assert_equal [ "invalid", "serve_id" ], rate(kind: "item", serve_id: theirs.id, stars: 4).values_at("status", "error")
    assert_equal [ "invalid", "serve_id" ], rate(kind: "item", serve_id: 999_999, stars: 4).values_at("status", "error")
    assert_equal [ "invalid", "serve_id" ], rate(kind: "item", stars: 4).values_at("status", "error")
    mine = finished_serve
    release_course!(@course, open: false) # the official student loses the pages when the release is withdrawn
    assert_equal [ "invalid", "serve_id" ], rate(kind: "item", serve_id: mine.id, stars: 4).values_at("status", "error")
    assert_equal 0, Rating.count
  end

  test "a trial student writes and the row is marked trial; the page's language is the row's" do
    serve = finished_serve(@trial)
    assert_equal "recorded", rate(TRIAL, kind: "item", serve_id: serve.id, stars: 3)["status"]
    assert Rating.sole.trial
    assert_equal @trial.id, Rating.sole.student_id
    Diagnosis::Preferences.record(@official, language: "en")
    mine = finished_serve
    assert_equal "recorded", rate(kind: "item", serve_id: mine.id, stars: 4)["status"]
    assert_equal [ "en", false ], Rating.order(:id).last.then { |row| [ row.language, row.trial ] }
  end

  # ---- a lesson ---------------------------------------------------------------------------------------------

  test "the student rates the lesson he reads: the key and the revision are the ones he was shown" do
    reply = rate(**lesson_body_of, stars: 5, text_it: "Chiara.")
    assert_equal "recorded", reply["status"]
    row = Rating.sole
    assert_equal [ "lesson", TOPIC, @lesson_revision.id, nil, nil ], [ row.target_kind, row.target_key, row.lesson_revision_id, row.item_revision_id, row.practice_serve_id ]
    assert_equal [ @subject.id, @topic_revision.id, 5 ], [ row.subject_id, row.topic_revision_id, row.stars ]
  end

  test "a lesson of another revision, a topic that is not there or not his, and a missing revision are refused" do
    other = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "1" * 64, rules_version: Validation::Rules.version.to_s, warnings_json: "[]",
                                   body_json: JSON.generate(lesson_body))
    assert_equal [ "invalid", "lesson_revision_id" ], rate(**lesson_body_of, lesson_revision_id: other.id, stars: 4).values_at("status", "error")
    assert_equal [ "invalid", "lesson_revision_id" ], rate(kind: "lesson", topic: TOPIC, stars: 4).values_at("status", "error")
    assert_equal [ "invalid", "topic" ], rate(**lesson_body_of("ripasso.math.nonesiste"), stars: 4).values_at("status", "error")
    assert_equal [ "invalid", "topic" ], rate(kind: "lesson", lesson_revision_id: @lesson_revision.id, stars: 4).values_at("status", "error")
    assert_equal 0, Rating.count
  end

  # ---- who may write ----------------------------------------------------------------------------------------

  test "the teacher, a guest, an unmapped login and no login cannot write a rating, and neither the preview nor the API listener has a route" do
    serve = finished_serve
    body = { client_rating_id: rid, kind: "item", serve_id: serve.id, stars: 4 }
    { "teacher" => TEACHER, "guest" => GUEST, "unmapped" => UNMAPPED, "nobody" => {} }.each do |who, headers|
      token = headers.empty? ? "x" : token_for(headers, "/teacher")
      on(:web, "/ratings", method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
      assert_includes [ 403, 422 ], response.status, who # 422: no token to give (the 403 page has none)
    end
    on(:web, "/teacher/preview/ratings", method: :post, headers: TEACHER.merge(JSON_HEADERS), params: body.to_json, remote_addr: EDGE)
    assert_response :not_found, "the preview has no route"
    on(:api, "/ratings", method: :post, headers: JSON_HEADERS, params: body.to_json)
    assert_response :not_found
    assert_equal 0, Rating.count
  end

  test "a POST without the student's CSRF token writes nothing" do
    serve = finished_serve
    on(:web, "/ratings", method: :post, headers: OFFICIAL.merge(JSON_HEADERS), params: { client_rating_id: rid, kind: "item", serve_id: serve.id, stars: 4 }.to_json, remote_addr: EDGE)
    assert_not_equal 200, response.status
    assert_equal 0, Rating.count
  end

  test "the preview student is refused by the writer itself" do
    preview = Student.current_preview
    result = Ratings::Intake.call(student: preview, course_view: Course::StudentView.new(preview, view: :official), language: "it",
                                  params: ActionController::Parameters.new(client_rating_id: rid, kind: "lesson", topic: TOPIC, lesson_revision_id: @lesson_revision.id, stars: 4))
    assert_equal [ :invalid, "not a student" ], [ result.status, result.error ]
    assert_equal 0, Rating.count
  end

  test "a rating writes nothing but the rating" do
    serve = finished_serve
    before = snapshot
    rate(kind: "item", serve_id: serve.id, stars: 4, text_it: "Bello.")
    rate(**lesson_body_of, stars: 5)
    assert_equal 2, Rating.count
    assert_equal before, snapshot
  end

  # ---- the pages --------------------------------------------------------------------------------------------

  def assert_box(kind, hidden: false)
    assert_select "section#rating-box.rating-box[data-controller=rating][data-nospeech][data-rating-kind-value=?]#{'[hidden]' if hidden}", kind do # «Ascolta» never reads it (D-381)
      assert_select "h3.rating-ask", text: kind == "item" ? "Ti è piaciuto questo esercizio? Se vuoi." : "Ti è piaciuta questa lezione? Se vuoi."
      assert_select "fieldset.rating-stars legend", text: "Da 1 a 5 stelle"
      assert_select "input[type=radio][name=rating-box-stars]", count: 5
      (1..5).each do |n|
        assert_select "input#rating-box-star-#{n}[value=?]", n.to_s
        assert_select "label[for=rating-box-star-#{n}] .sr-only", text: n == 1 ? "1 stella" : "#{n} stelle"
      end
      assert_select "label[for=rating-box-text]", text: "Vuoi aggiungere un commento?"
      assert_select "textarea#rating-box-text[maxlength=2000]"
      assert_select "button[type=submit]", text: "Invia"
      assert_select "button", text: "Cambia"
    end
  end

  test "the practice page has the box, shut until the exercise is over; the lesson page has it at its end for the revision he reads" do
    on(:web, "/topics/#{TOPIC}/practice/#{SKILL}", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    assert_box "item", hidden: true
    assert_select ".rating-box", 1

    on(:web, "/topics/#{TOPIC}/lesson", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    assert_box "lesson"
    assert_select "section#rating-box[data-rating-topic-value=?][data-rating-lesson-revision-value=?]", TOPIC, @lesson_revision.id.to_s
    assert_select "section#rating-box[data-rating-current-value=?]", "{}"
  end

  test "the page shows his latest rating of the lesson in the box, and the serve carries his latest rating of the exercise" do
    rate(**lesson_body_of, stars: 4, text_it: "Utile.")
    on(:web, "/topics/#{TOPIC}/lesson", headers: OFFICIAL, remote_addr: EDGE)
    assert_equal({ "stars" => 4, "text_it" => "Utile." }, JSON.parse(css_select("section#rating-box").first["data-rating-current-value"]))

    first = finished_serve
    reply = post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL, item: first.item_instance.item_revision.item.key })
    assert_nil reply["rating"], "none given yet"
    rate(kind: "item", serve_id: first.id, stars: 2)
    again = post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL, item: first.item_instance.item_revision.item.key })
    assert_equal({ "stars" => 2, "text_it" => nil }, again["rating"])
  end

  test "the English page has the English box and the teacher's preview has none" do
    Diagnosis::Preferences.record(@official, language: "en")
    on(:web, "/topics/#{TOPIC}/lesson", headers: OFFICIAL, remote_addr: EDGE)
    assert_select "h3.rating-ask", text: "Did you like this lesson? Only if you want to."
    assert_select "label[for=rating-box-star-1] .sr-only", text: "1 star"
    assert_select "label[for=rating-box-star-3] .sr-only", text: "3 stars"
    assert_select "button[type=submit]", text: "Send"

    [ "/topics/#{TOPIC}/lesson", "/topics/#{TOPIC}/practice/#{SKILL}" ].each do |path|
      on(:web, "/teacher/preview#{path}", headers: TEACHER, remote_addr: EDGE)
      assert_response :success, path
      assert_select ".rating-box", 0
    end
  end

  test "the list, the entry test and the other pages of the student have no box" do
    %w[/today /subjects /subjects/math /diagnosis /settings /comments].each do |path|
      on(:web, path, headers: OFFICIAL, remote_addr: EDGE)
      assert_select ".rating-box", 0, path
    end
  end
end

# The lesson of version 2 keeps the box in a template that lesson/render.js copies into its last card (nowhere else, and not in the preview).
class RatingsLesson2PageTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  setup { build_student_world(approve: true, release: true) }

  test "the page of a lesson/2 holds the box in a template for the student and none for the teacher's preview" do
    on(:web, "/topics/#{TOPIC}/lesson", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    assert_select "#lesson-root[data-controller=lesson2]"
    assert_select "template#rating-template" do
      assert_select "section.rating-box[data-rating-kind-value=lesson][data-rating-topic-value=?][data-rating-lesson-revision-value=?]", TOPIC, @lesson_revision.id.to_s
      assert_select "input[type=radio]", count: 5
    end
    assert_select "section.rating-box", 1

    on(:web, "/teacher/preview/topics/#{TOPIC}/lesson", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#rating-template", 0
    assert_select ".rating-box", 0
  end
end

# The entry test is not rated: no box on the sitting's page, and the one door takes no serve of a diagnosis run.
class RatingsSittingTest < ActionDispatch::IntegrationTest
  include StudentUiRows

  EDGE = ListenerHelpers::EDGE_IP
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze

  setup do
    @saved = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    ENV["BANCO_TEACHER_USERS"] = "nik"
  end

  teardown { %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS].each { |k| @saved.key?(k) ? ENV[k] = @saved[k] : ENV.delete(k) } }

  test "a sitting of the entry test has no rating box, and the list of the tests has none" do
    rows = build_ui_subject
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    [ "/diagnosis", "/diagnosis/runs/#{run.id}" ].each do |path|
      on(:web, path, headers: STUDENT, remote_addr: EDGE)
      assert_response :success, path
      assert_select ".rating-box", 0, path
      assert_select "[data-controller~=rating]", 0, path
      assert_select "#rating-template", 0, path
    end
  end
end
