require "test_helper"
require "rake"
require_relative "../support/multi_user"
require_relative "../support/lesson_events_world"

# D-304, comments anywhere (C1): the student's door (what is checked against what the student was shown), "I miei
# commenti", the badge and the Oggi line, the teacher's page and its four actions under the decisions' guards, the
# guest's counts, the console, and the promise that a comment changes nothing else.
class CommentsTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  MARKER = "parola-segreta-del-commento".freeze

  setup do
    build_student_world(approve: true, release: true)
    ENV["BANCO_DECISIONS_ENABLED"] = "1"
    @saved_forgery = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown { ActionController::Base.allow_forgery_protection = @saved_forgery }

  def lesson_path = "/topics/#{TOPIC}/lesson"
  def cid = "c-" + SecureRandom.hex(8)

  def token_for(headers, path = "/today")
    on(:web, path, headers: headers, remote_addr: EDGE)
    css_select("meta[name=csrf-token]").first&.[]("content").to_s
  end

  def post_json(headers, path, body = {}, token: nil, listener: :web)
    token ||= token_for(headers)
    on(listener, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def comment_body(**over)
    { client_comment_id: cid, reason: "not_understood", text_it: "Non capisco il passaggio.", page_path: lesson_path, anchor: "card:2/block:1",
      refs: { lesson_revision_id: @lesson_revision.id }, viewport_width: 390, viewport_height: 800, theme: "cream", text_size: "normal" }.merge(over)
  end

  def send_comment(headers = OFFICIAL, **over)
    post_json(headers, "/comments", comment_body(**over))
  end

  def teacher_post(action, comment, params = {}, headers: TEACHER, token: nil, extra: {}, listener: :web)
    token ||= token_for(headers, "/teacher/comments")
    cookies.delete(DecisionRecorder::DEVICE_COOKIE) # the student pages of this test left the student's mark on the jar
    on(listener, "/teacher/comments/#{comment.id}/#{action}", method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token).merge(extra),
                                                              params: params.to_json, remote_addr: EDGE)
  end

  def other_tables = ActiveRecord::Base.connection.tables - %w[comments comment_events students app_events schema_migrations ar_internal_metadata sqlite_sequence]
  def snapshot = other_tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] }

  # ---- the student's door ------------------------------------------------------------------------------

  test "a comment on a lesson card is stored with the places derived by the server" do
    reply = send_comment
    assert_response :success
    assert_equal({ "status" => "recorded" }, reply)
    c = Comment.last
    assert_equal [ "not_understood", "lezione", @official.id, false ], [ c.reason, "lezione", c.student_id, c.trial ]
    assert_equal [ "lesson", lesson_path, "card:2/block:1", 2 ], [ c.page_kind, c.page_path, c.anchor, c.card ]
    assert_equal [ @lesson_revision.id, @topic_revision.id, @subject.id ], [ c.lesson_revision_id, c.topic_revision_id, c.subject_id ]
    assert_equal [ 390, 800, "cream", "normal" ], [ c.viewport_width, c.viewport_height, c.theme, c.text_size ]
    assert_equal "sent", c.state
  end

  test "the same client_comment_id again is recorded once, and a trial student's comment is marked trial" do
    one = cid
    2.times { assert_equal "recorded", send_comment(client_comment_id: one)["status"] }
    assert_equal 1, Comment.where(client_comment_id: one).count
    assert_equal "recorded", send_comment(TRIAL)["status"]
    trial = Comment.order(:id).last
    assert trial.trial
    assert_equal @trial.id, trial.student_id
  end

  test "another student's client_comment_id is refused, not overwritten or shown" do
    one = cid
    send_comment(OFFICIAL, client_comment_id: one)
    reply = send_comment(TRIAL, client_comment_id: one)
    assert_equal "invalid", reply["status"]
    assert_equal 1, Comment.count
  end

  test "ids the student was not shown are refused and nothing is written" do
    before = Comment.count
    bad = [
      { refs: { lesson_revision_id: @lesson_revision.id + 1000 } },
      { anchor: "card:99" },
      { anchor: "../etc/passwd" },
      { anchor: "card:2/" + "block:1/" * 9 },
      { reason: "angry" },
      { reason: nil },
      { text_it: "x" * 501 },
      { page_path: "/teacher/comments" },
      { page_path: "/topics/ripasso.math.nonesiste/lesson", refs: {} },
      { page_path: lesson_path, refs: { served_event_id: 1 } },
      { page_path: lesson_path, refs: { serve_id: 1 } },
      { page_path: "/today", refs: { lesson_revision_id: @lesson_revision.id }, anchor: nil },
      { client_comment_id: "short" },
      { page_path: "/subjects/physics", refs: {}, anchor: nil }
    ]
    bad.each do |over|
      reply = send_comment(OFFICIAL, **over)
      assert_equal "invalid", reply["status"], over.inspect
    end
    assert_equal before, Comment.count
  end

  test "a topic the student cannot see (the course not released) is refused" do
    release_course!(@course, open: false)
    assert_equal "invalid", send_comment["status"]
    assert_equal 0, Comment.count
  end

  test "a comment on a page without a place stores the page only" do
    reply = send_comment(OFFICIAL, page_path: "/settings", anchor: "setting:theme", refs: {})
    assert_equal "recorded", reply["status"]
    c = Comment.last
    assert_equal [ "settings", "setting:theme", nil, nil, nil ], [ c.page_kind, c.anchor, c.lesson_revision_id, c.item_revision_id, c.topic_revision_id ]
  end

  test "a practice comment names a serve of this student; another student's serve is refused" do
    serve = post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL })
    assert_equal "item", serve["type"]
    path = "/topics/#{TOPIC}/practice/#{SKILL}"
    ok = send_comment(OFFICIAL, page_path: path, anchor: "exercise/item/option:2", refs: { serve_id: serve["serve_id"] })
    assert_equal "recorded", ok["status"]
    c = Comment.last
    row = PracticeServe.find(serve["serve_id"])
    assert_equal [ row.id, row.item_instance_id, row.item_instance.item_revision_id ], [ c.practice_serve_id, c.item_instance_id, c.item_revision_id ]
    assert_equal "invalid", send_comment(TRIAL, page_path: path, refs: { serve_id: serve["serve_id"] })["status"]
    assert_equal "invalid", send_comment(OFFICIAL, page_path: path, refs: { serve_id: 999_999 })["status"]
    assert_equal 1, Comment.count
  end

  test "writing a comment changes no other table: no grade, attempt, serve, event, decision" do
    serve = post_json(OFFICIAL, "/practice/serves", { topic: TOPIC, skill: SKILL })
    token = token_for(OFFICIAL)
    before = snapshot
    post_json(OFFICIAL, "/comments", comment_body, token: token)
    post_json(OFFICIAL, "/comments", comment_body(page_path: "/topics/#{TOPIC}/practice/#{SKILL}", refs: { serve_id: serve["serve_id"] }, anchor: nil), token: token)
    assert_equal 2, Comment.count
    assert_equal before, snapshot
  end

  test "the teacher, a guest, an unmapped login and no login cannot write a comment, and the API listener has no such route" do
    [ TEACHER, GUEST, UNMAPPED, {} ].each do |who|
      token = who.empty? ? "x" : token_for(who, "/teacher")
      on(:web, "/comments", method: :post, headers: who.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: comment_body.to_json, remote_addr: EDGE)
      assert_includes [ 403, 422 ], response.status, who.inspect # 422: no token to give (the 403 page has none)
    end
    on(:api, "/comments", method: :post, headers: JSON_HEADERS, params: comment_body.to_json)
    assert_response :not_found
    assert_equal 0, Comment.count
  end

  test "without a CSRF token the student's post is refused" do
    on(:web, "/comments", method: :post, headers: OFFICIAL.merge(JSON_HEADERS), params: comment_body.to_json, remote_addr: EDGE)
    assert_not_equal 200, response.status
    assert_equal 0, Comment.count
  end

  test "the teacher's preview writes none: no route, and no comment box in its pages" do
    on(:web, "/teacher/preview/comments", method: :post, headers: TEACHER.merge(JSON_HEADERS), params: comment_body.to_json, remote_addr: EDGE)
    assert_response :not_found
    on(:web, "/teacher/preview", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_select "#comment-root", 0
    assert_select "[data-comment-open]", 0
    assert_equal 0, Comment.count
  end

  # ---- I miei commenti ---------------------------------------------------------------------------------

  test "the student sees only their own comments, with state; a trial student's are theirs alone" do
    send_comment(OFFICIAL, text_it: "Del ragazzo #{MARKER}")
    send_comment(TRIAL, text_it: "Della prova segreta")
    on(:web, "/comments", headers: OFFICIAL, remote_addr: EDGE)
    assert_response :success
    assert_select "#my-comments li", 1
    assert_includes response.body, MARKER
    assert_not_includes response.body, "Della prova segreta"
    assert_select ".comment-state", "Inviato"
    on(:web, "/comments", headers: TRIAL, remote_addr: EDGE)
    assert_includes response.body, "Della prova segreta"
    assert_not_includes response.body, MARKER
    assert_includes response.body, "Account di prova"
  end

  test "a reply shows in I miei commenti and in Oggi with a badge, and reading it clears them" do
    send_comment(OFFICIAL, text_it: "Non capisco")
    comment = Comment.last
    teacher_post("reply", comment, { text_it: "Guarda la scheda 2." })
    assert_response :redirect
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    assert_select "#comment-replies", /Il docente ti ha risposto/
    assert_select "#comments-badge", "1"
    on(:web, "/comments", headers: OFFICIAL, remote_addr: EDGE)
    assert_select ".comment-reply", /Guarda la scheda 2\./
    assert_select ".comment-state", "Risposto"
    assert_select "#comments-badge", 0, "the page that shows the reply has marked it seen"
    assert_equal "reply_seen", comment.events.reload.last.kind
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    assert_select "#comment-replies", 0
    assert_select "#comments-badge", 0
    # another student never has the badge
    on(:web, "/today", headers: TRIAL, remote_addr: EDGE)
    assert_select "#comments-badge", 0
  end

  test "the comment control is on every student page" do
    %w[/today /subjects /settings /search /comments /diagnosis /diagnosis/warmup].each do |path|
      on(:web, path, headers: OFFICIAL, remote_addr: EDGE)
      assert_select "#comment-root[data-controller=comment]", 1, path
      assert_select "[data-comment-open]", minimum: 1
    end
    [ "/topics/#{TOPIC}", lesson_path, "/topics/#{TOPIC}/practice/#{SKILL}", "/subjects/math" ].each do |path|
      on(:web, path, headers: OFFICIAL, remote_addr: EDGE)
      assert_select "#comment-root", 1, path
    end
    on(:web, lesson_path, headers: OFFICIAL, remote_addr: EDGE)
    assert_select "#lesson-root[data-comment-lesson-revision-id='#{@lesson_revision.id}']"
  end

  # ---- the teacher's page and actions ---------------------------------------------------------------------

  test "the teacher sees the comments and the questions; a guest sees the counts and no text" do
    send_comment(OFFICIAL, text_it: "Testo #{MARKER}")
    StudentQuestion.create!(student: @official, client_question_id: "q-" + SecureRandom.hex(6), text_it: "Domanda vecchia", created_at: Time.current)
    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    assert_includes response.body, MARKER
    assert_includes response.body, "Domanda vecchia"
    assert_select "[data-comment]", 1
    assert_select "#menu-comments"
    on(:web, "/teacher/comments", headers: GUEST, remote_addr: EDGE)
    assert_response :success
    assert_not_includes response.body, MARKER
    assert_not_includes response.body, "Domanda vecchia"
    assert_select "#comment-counts li[data-state=sent]", /Nuovi: 1/
    assert_select "#comment-counts li[data-state=questions]", /1/
    assert_select "#comment-inbox", 0
    [ OFFICIAL, TRIAL ].each do |who|
      on(:web, "/teacher/comments", headers: who, remote_addr: EDGE)
      assert_response :forbidden
    end
  end

  test "the teacher's page filters by state, reason, who and kind of place" do
    send_comment(OFFICIAL, reason: "error", text_it: "Uno")
    send_comment(TRIAL, reason: "like", text_it: "Due", page_path: "/settings", anchor: nil, refs: {})
    on(:web, "/teacher/comments?reason=like", headers: TEACHER, remote_addr: EDGE)
    assert_select "[data-comment]", 1
    assert_select "[data-reason=like]"
    on(:web, "/teacher/comments?who=trial", headers: TEACHER, remote_addr: EDGE)
    assert_select "[data-comment]", 1
    on(:web, "/teacher/comments?kind=lesson", headers: TEACHER, remote_addr: EDGE)
    assert_select "[data-comment]", 1
    assert_select "[data-reason=error]"
    on(:web, "/teacher/comments?state=answered", headers: TEACHER, remote_addr: EDGE)
    assert_select "[data-comment]", 0
    assert_select "#comments-empty"
  end

  test "reply, read, resolve and reopen are rows of the teacher, in order, with the states derived" do
    send_comment
    c = Comment.last
    teacher_post("read", c)
    assert_response :redirect
    assert_equal "read", c.reload.state
    teacher_post("read", c)
    assert_response :redirect
    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_select ".flash.alert", /già/, "reading twice is refused with the reason, nothing written"
    assert_equal 1, c.events.count
    teacher_post("reply", c, { text_it: "Prova così." })
    assert_equal "answered", c.reload.state
    reply = c.events.last
    assert_equal [ "reply", "web", "nik", "Prova così." ], [ reply.kind, reply.origin, reply.actor, reply.text_it ]
    teacher_post("reopen", c)
    assert_equal 2, c.events.reload.count, "a reopen of an open comment writes nothing"
    teacher_post("resolve", c)
    assert_equal "closed", c.reload.state
    teacher_post("reply", c, { text_it: "Ancora." })
    assert_equal "closed", c.reload.state, "a closed comment takes no reply until reopened"
    teacher_post("reopen", c)
    assert_equal "answered", c.reload.state
    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_select "[data-event=reply]", /Prova così\./
  end

  test "an empty, too long or missing reply writes nothing and an unknown comment is a 404" do
    send_comment
    c = Comment.last
    teacher_post("reply", c, { text_it: "   " })
    teacher_post("reply", c, { text_it: "x" * 2001 })
    assert_equal 0, c.events.count
    ghost = Comment.new(id: 99_999)
    teacher_post("reply", ghost, { text_it: "Ciao" })
    assert_response :not_found
  end

  test "the actions are refused without the flag, the token, the group, on a student's computer, for a guest, a student and on the other listeners" do
    send_comment
    c = Comment.last
    good = token_for(TEACHER, "/teacher/comments")
    refusals = lambda do |what, **opts|
      teacher_post("reply", c, { text_it: "No" }, **opts)
      assert_response :forbidden, what
      assert_equal 0, c.events.count, what
    end
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    refusals.call("flag off", token: good)
    ENV["BANCO_DECISIONS_ENABLED"] = "1"
    refusals.call("no token", token: "wrong")
    refusals.call("guest", headers: GUEST, token: token_for(GUEST, "/teacher/comments"))
    refusals.call("student", headers: OFFICIAL, token: token_for(OFFICIAL))
    refusals.call("trial student", headers: TRIAL, token: token_for(TRIAL))
    refusals.call("student's computer", token: good, extra: { "Cookie" => "#{DecisionRecorder::DEVICE_COOKIE}=student" })
    refusals.call("a login outside the list", headers: { "Remote-User" => "intruder", "Remote-Groups" => "banco-teacher" }, token: good)
    %i[api harness].each do |listener|
      teacher_post("reply", c, { text_it: "No" }, token: good, listener: listener)
      assert_response :not_found, listener.to_s
    end
    assert_equal 0, c.events.count
  end

  test "a guest cannot read a reply through any teacher or student route" do
    send_comment
    c = Comment.last
    teacher_post("reply", c, { text_it: "Risposta #{MARKER}" })
    %w[/teacher/comments /teacher /teacher/findings /teacher/corrections /teacher/students].each do |path|
      on(:web, path, headers: GUEST, remote_addr: EDGE)
      assert_not_includes response.body, MARKER, path
    end
    on(:web, "/comments", headers: GUEST, remote_addr: EDGE)
    assert_response :forbidden
  end

  test "a comment's text is shown escaped" do
    send_comment(OFFICIAL, text_it: "<script>alert(1)</script>")
    on(:web, "/teacher/comments", headers: TEACHER, remote_addr: EDGE)
    assert_not_includes response.body, "<script>alert(1)</script>"
    assert_includes response.body, "&lt;script&gt;"
  end

  test "the teacher's actions change nothing outside the comment tables" do
    send_comment
    c = Comment.last
    token = token_for(TEACHER, "/teacher/comments")
    before = snapshot
    %w[read reply resolve reopen].each { |a| teacher_post(a, c, { text_it: "Ok" }, token: token) }
    assert_equal before, snapshot
  end

  # ---- the console -------------------------------------------------------------------------------------

  def console(action, **args) = Comments::Console.call(action: action, id: Comment.last.id, teacher: "nik", **args)

  test "the console replies as the teacher: a dry run writes nothing, CONFIRM writes a row with origin console" do
    send_comment
    result = console("reply", text_it: "Dalla console.")
    assert result.ok, result.errors.inspect
    assert_not result.recorded
    assert_equal 0, CommentEvent.count
    result = console("reply", text_it: "Dalla console.", confirm: true)
    assert result.recorded
    e = CommentEvent.last
    assert_equal [ "reply", "console", "nik", "console" ], [ e.kind, e.origin, e.actor, e.remote_addr ]
    assert_equal "answered", Comment.last.state
    result = console("resolve", reason: "Detto a voce.", confirm: true)
    assert result.ok
    assert_equal({ "reason_it" => "Detto a voce." }, JSON.parse(CommentEvent.last.payload_json))
    assert_equal "closed", Comment.last.state
    assert_equal "answered", (console("reopen", confirm: true); Comment.last.state)
  end

  test "the console refuses a login outside the teacher list, the flag off, an empty reply and an unknown id" do
    send_comment
    assert_not Comments::Console.call(action: "reply", id: Comment.last.id, teacher: "intruder", text_it: "No", confirm: true).ok
    ENV["BANCO_DECISIONS_ENABLED"] = "0"
    assert_not console("reply", text_it: "No", confirm: true).ok
    ENV["BANCO_DECISIONS_ENABLED"] = "1"
    assert_not console("reply", text_it: " ", confirm: true).ok
    assert_not Comments::Console.call(action: "reply", id: 99_999, teacher: "nik", text_it: "No", confirm: true).ok
    assert_not console("explode").ok
    assert_equal 0, CommentEvent.count
  end

  test "the rake tasks list, show and reply (dry run first)" do
    Rake::Task.clear
    Rails.application.load_tasks
    send_comment(OFFICIAL, text_it: "Per la console #{MARKER}")
    out, = capture_io { Rake::Task["banco:comments:list"].reenable; Rake::Task["banco:comments:list"].invoke }
    assert_includes out, MARKER
    saved = ENV.to_h.slice("ID", "TEACHER", "TEXT_IT", "CONFIRM")
    ENV.update("ID" => Comment.last.id.to_s, "TEACHER" => "nik", "TEXT_IT" => "Risposta.")
    ENV.delete("CONFIRM")
    out, = capture_io { Rake::Task["banco:comments:show"].reenable; Rake::Task["banco:comments:show"].invoke }
    assert_includes out, "not_understood"
    out, = capture_io { Rake::Task["banco:comments:reply"].reenable; Rake::Task["banco:comments:reply"].invoke }
    assert_match(/dry run/, out)
    assert_equal 0, CommentEvent.count
    ENV["CONFIRM"] = "1"
    out, = capture_io { Rake::Task["banco:comments:reply"].reenable; Rake::Task["banco:comments:reply"].invoke }
    assert_match(/recorded reply/, out)
    assert_equal 1, CommentEvent.count
  ensure
    %w[ID TEACHER TEXT_IT CONFIRM].each { |k| saved&.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  # ---- the agents never read a comment -------------------------------------------------------------------

  test "no API route, controller or schema command names a comment or a reply" do
    api_routes = Rails.application.routes.routes.select { |r| r.path.spec.to_s.start_with?("/api/") }
    assert_not_empty api_routes
    api_routes.each do |route|
      target = "#{route.defaults[:controller]}##{route.defaults[:action]}"
      assert_no_match(/comment|repl(y|ies)|reply_seen/i, "#{route.path.spec} #{target}")
    end
    offenders = Dir[Rails.root.join("app/controllers/api/**/*.rb").to_s].select { |f| File.read(f).match?(/\bComments?\b|CommentEvent|Comments::|comment_events/) }
    assert_empty offenders.map { |f| f.delete_prefix("#{Rails.root}/") }
    assert_not Rails.root.join("contract/commands.json").read.match?(/"comments?"|comment_events|reply_seen/), "the CLI contract has no command for comments"
  end

  test "an agent token reads nothing of a comment from any parameterless API read" do
    send_comment(OFFICIAL, text_it: "Per il docente #{MARKER}")
    teacher_post("reply", Comment.last, { text_it: "Risposta #{MARKER}" })
    token = ApiToken.issue!(role: "agent_claude", label: "comments test")
    paths = Rails.application.routes.routes.filter_map do |route|
      spec = route.path.spec.to_s.sub("(.:format)", "")
      spec if route.verb == "GET" && spec.start_with?("/api/v1/") && spec.exclude?(":")
    end
    assert_includes paths, "/api/v1/status"
    (paths + [ "/api/v1/search?q=docente" ]).each do |path|
      on(:api, path, headers: { "Authorization" => "Bearer #{token}" })
      assert_not_includes response.body, MARKER, path
    end
    on(:api, "/api/v1/comments", headers: { "Authorization" => "Bearer #{token}" })
    assert_response :not_found
    on(:api, "/api/v1/comments", method: :post, headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }, params: { text_it: "x" }.to_json)
    assert_response :not_found
  end

  test "the student-facing comment code has no model in its path" do
    files = Dir[Rails.root.join("app/{models/comments,controllers/comments_controller.rb,controllers/teacher/comments_controller.rb}/**/*.rb").to_s] +
            [ Rails.root.join("app/controllers/comments_controller.rb").to_s, Rails.root.join("app/controllers/teacher/comments_controller.rb").to_s ]
    files.uniq.each do |f|
      assert_no_match(/anthropic|openai|llm|Providers\.|AgentSession/i, File.read(f), f)
    end
  end
end
