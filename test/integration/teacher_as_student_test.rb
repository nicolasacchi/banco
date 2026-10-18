require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson_events_world"

# The teacher walks the whole student's site as a student (D-309): /teacher/preview runs the student's own controllers for
# the teacher's preview student (kind preview). Two views (official, drafts), a reset that starts a new preview student, and
# nothing of it reaches S, a trial student, a report, the Cruscotto, the comments, the search answers or the API.
class TeacherAsStudentTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze
  ROOT = "/teacher/preview".freeze
  PAGES = [ "", "/today", "/subjects", "/subjects/math", "/topics/#{TOPIC}", "/topics/#{TOPIC}/lesson", "/topics/#{TOPIC}/practice/#{SKILL}", "/search",
            "/settings", "/test", "/warmup" ].freeze

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def token_for(headers)
    page(headers, "#{ROOT}/today")
    css_select("meta[name=csrf-token]").first&.[]("content").to_s
  end

  # A post as the page's script does it; the answer as parsed JSON.
  def post_json(headers, path, body = {})
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token_for(headers)), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def post_form(headers, path, params = {})
    on(:web, path, method: :post, headers: headers.merge("X-CSRF-Token" => token_for(headers)), params: params, remote_addr: EDGE)
  end

  def preview_student = Student.where(kind: "preview").order(:id).last
  def cid = "e-" + SecureRandom.hex(8)

  # The teacher plays a bit of everything: the lesson (cards seen, a check), a practice try, a preference, a lesson solution.
  def walk!
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}/lesson")
    post_json(TEACHER, "#{ROOT}/topics/#{TOPIC}/lesson/events", { events: [ { kind: "card_seen", card: 2, client_event_id: cid } ] })
    card, block, check = find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
    right = shown_id(preview_student, card, block, check["answer"])
    reply = post_json(TEACHER, "#{ROOT}/topics/#{TOPIC}/lesson/checks/#{card}/#{block}", { response: right, try: 1, client_event_id: cid })
    @check_reply = reply
    serve = post_json(TEACHER, "#{ROOT}/practice/serves", { topic: TOPIC, skill: SKILL })
    instance = PracticeServe.find(serve["serve_id"]).item_instance
    @answer = post_json(TEACHER, "#{ROOT}/practice/answers", { serve_id: serve["serve_id"], client_attempt_id: SecureRandom.uuid, raw: JSON.parse(instance.answer_json).to_s, source: "text" })
    post_form(TEACHER, "#{ROOT}/preferences", { theme: "dark", size: "large" })
  end

  # ---- the walk ---------------------------------------------------------------------------------------

  test "the teacher walks Oggi, Materie, a subject, a topic, the lesson and a graded practice try, on the preview addresses" do
    build_student_world
    page(TEACHER, ROOT)
    assert_response :success
    assert_select "#preview-banner", /Stai provando come studente/
    assert_select "#preview-banner", /Vista: Come lo vede S/
    assert_select "#preview-exit[href='/teacher'][aria-label='Esci dalla prova']", /Esci/
    # the phone's one row (D-315): «Opzioni» discloses the switch and the reset; each control's name is the whole action
    assert_select "#preview-more summary[aria-label='Opzioni della prova']", "Opzioni"
    assert_select "#preview-actions form[action='#{ROOT}/view'] button#preview-switch", /Passa a: Con le bozze/
    assert_select "#preview-actions #preview-reset summary", /Ricomincia da capo/
    assert_select "#suggestions li.topic[data-topic='#{TOPIC}'] a.topic-title[href='#{ROOT}/topics/#{TOPIC}']"
    assert_select "nav.student-menu a#menu-subjects[href='#{ROOT}/subjects']"
    page(TEACHER, "#{ROOT}/subjects")
    assert_select "li.subject[data-subject=math] a[href='#{ROOT}/subjects/math']"
    page(TEACHER, "#{ROOT}/subjects/math")
    assert_select "li.topic[data-topic='#{TOPIC}'] a[href='#{ROOT}/topics/#{TOPIC}']"
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}")
    assert_select "h1", TOPIC_TITLE
    assert_select "a#lesson-link[href='#{ROOT}/topics/#{TOPIC}/lesson']"
    assert_select "li.skill a[href='#{ROOT}/topics/#{TOPIC}/practice/#{SKILL}']"
    assert_select "[data-controller=question]", 0
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}/lesson")
    assert_response :success
    urls = JSON.parse(css_select("[data-lesson2-urls-value]").first["data-lesson2-urls-value"])
    assert_equal "#{ROOT}/topics/#{TOPIC}/lesson/events", urls["events"]
    assert_equal "#{ROOT}/topics/#{TOPIC}/lesson/checks", urls["check"]
    assert_equal "#{ROOT}/preferences", urls["preferences"]
    assert_nil urls["questions"], "no «Non ho capito» from the preview"
    walk!
    assert_equal "right", @check_reply["verdict"]
    assert_equal %w[graded correct], @answer.values_at("status", "outcome")
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}/practice/#{SKILL}")
    assert_response :success
    assert_select "[data-practice-serve-url-value='#{ROOT}/practice/serves']"
    assert_select "[data-practice-back-url-value='#{ROOT}/topics/#{TOPIC}']"
    page(TEACHER, "#{ROOT}/settings")
    assert_select "form#preferences[action='#{ROOT}/preferences']"
    page(TEACHER, "#{ROOT}/search?q=equazioni")
    assert_response :success
    page(TEACHER, "#{ROOT}/warmup")
    assert_response :success
    page(TEACHER, "#{ROOT}/test")
    assert_response :success
    assert_select "#preview-banner"
    preview = preview_student
    assert_equal "preview", preview.key
    assert_equal 1, PracticeAttempt.where(student: preview).count
    assert_equal 2, LessonEvent.where(student: preview).count, "one card seen and one check answered"
    assert_equal({ theme: "dark", size: "large" }, Diagnosis::Preferences.for(preview))
  end

  test "no link, form or script address on a preview page leaves for the student's own pages" do
    build_student_world
    own = %r{\A/(today|subjects|topics|practice|diagnosis|settings|search|comments|questions|warmup|runs)(/|\?|#|\z)}
    (PAGES + [ "/test" ]).uniq.each do |path|
      page(TEACHER, "#{ROOT}#{path}")
      assert_response :success, path
      addresses = css_select("a[href], form[action]").map { |e| e["href"] || e["action"] }
      addresses += css_select("[data-lesson2-urls-value]").flat_map { |e| JSON.parse(e["data-lesson2-urls-value"]).values }
      addresses += response.body.scan(/data-[a-z-]+-url-value="([^"]+)"/).flatten
      leaking = addresses.select { |a| a.match?(own) }
      assert_empty leaking, "#{path} links to the student's own pages: #{leaking.uniq.inspect}"
    end
  end

  test "Oggi offers «Riprendi» after the lesson was opened, as for S" do
    build_student_world
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}/lesson")
    page(TEACHER, ROOT)
    assert_select "#resume[href^='#{ROOT}/topics/#{TOPIC}']"
  end

  # ---- the two views ----------------------------------------------------------------------------------

  test "the official view hides a draft and an unreleased course; the drafts view shows them flagged; the switch is the teacher's" do
    build_student_world(approve: false, release: false)
    page(TEACHER, "#{ROOT}/subjects")
    assert_select "#course-closed"
    assert_select "li.subject", 0
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}")
    assert_response :not_found
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}/lesson")
    assert_response :not_found
    post_form(TEACHER, "#{ROOT}/view", { view: "drafts", back: "#{ROOT}/subjects" })
    assert_response :see_other
    assert_equal "#{ROOT}/subjects", URI(response.location).path
    page(TEACHER, "#{ROOT}/subjects")
    assert_select "li.subject[data-subject=math]"
    assert_select "#preview-banner", /Vista: Con le bozze/
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}")
    assert_response :success
    assert_select "#draft-notice", /Bozza in prova/
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}/lesson")
    assert_select "#draft-notice"
    page(TEACHER, "#{ROOT}/today")
    assert_select "#now-draft", /Bozza/
    assert_select "a[href^='/diagnosis']", 0, "no link leaves the preview for the student's own pages"
    post_form(TEACHER, "#{ROOT}/view", { view: "official" })
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}")
    assert_response :not_found
    post_form(TEACHER, "#{ROOT}/view", { view: "nonsense" })
    page(TEACHER, "#{ROOT}/subjects")
    assert_select "#preview-banner", /Vista: Come lo vede S/
  end

  test "the switch comes back only to a preview address of this site" do
    build_student_world
    [ "https://evil.example/x", "//evil.example/x", "/teacher", "/today", "#{ROOT}/runs/1", "#{ROOT}//evil" ].each do |back|
      post_form(TEACHER, "#{ROOT}/view", { view: "drafts", back: back })
      assert_response :see_other
      assert_equal ROOT, URI(response.location).path, back
    end
  end

  # ---- who may enter ----------------------------------------------------------------------------------

  test "guests, students, trial students, unmapped students and nobody enter the preview, and nothing is written" do
    build_student_world
    before = [ Student.count, Decision.count, LessonEvent.count, PracticeServe.count, AppEvent.count ]
    [ GUEST, OFFICIAL, TRIAL, UNMAPPED, {} ].each do |who|
      PAGES.each do |path|
        page(who, "#{ROOT}#{path}")
        assert_response :forbidden, "#{path} for #{who['Remote-User'].inspect}"
      end
      [ "/view", "/reset", "/practice/serves", "/practice/answers", "/preferences", "/topics/#{TOPIC}/lesson/events", "/topics/#{TOPIC}/lesson/checks/1/1",
        "/warmup/answers" ].each do |path|
        on(:web, "#{ROOT}#{path}", method: :post, headers: who.merge(JSON_HEADERS), params: "{}", remote_addr: EDGE)
        assert_response :forbidden, "POST #{path} for #{who['Remote-User'].inspect}"
      end
    end
    assert_equal before, [ Student.count, Decision.count, LessonEvent.count, PracticeServe.count, AppEvent.count ]
    assert_empty Student.where(kind: "preview")
  end

  test "the student's own pages stay the student's: the teacher is refused there, and a student cannot pick the preview with a parameter" do
    build_student_world
    page(TEACHER, "/today")
    assert_response :forbidden
    page(OFFICIAL, "/today?preview=true")
    assert_response :success
    assert_select "#preview-banner", 0
    assert_equal [ "student" ], Student.pluck(:key).select { |k| k.start_with?("student") }
    assert_empty Student.where(kind: "preview")
  end

  # ---- isolation --------------------------------------------------------------------------------------

  test "nothing is written on the official student or a trial student" do
    build_student_world
    page(OFFICIAL, "/today")
    page(TRIAL, "/today")
    walk!
    preview = preview_student
    {
      LessonEvent => :student_id, PracticeServe => :student_id, PracticeEvent => :student_id, PracticeAttempt => :student_id, AppEvent => :student_id,
      DiagnosisRun => :student_id, Attempt => :student_id, StudentQuestion => :student_id, Comment => :student_id
    }.each do |model, column|
      others = model.where.not(column => preview.id).where.not(column => nil)
      assert_empty others.to_a, "#{model.name} has rows of someone else than the preview student"
    end
    assert_equal [ preview.id ], PracticeServe.pluck(:student_id).uniq
    assert_empty Student.where(key: %w[student prova-1]).flat_map { |s| LessonEvent.where(student: s).to_a }
    assert_equal [ "preview" ], Student.where(kind: "preview").pluck(:key)
  end

  test "the preview student is in no report, no student row, no comment inbox, no search answer and no API output" do
    build_student_world
    walk!
    preview = preview_student
    on(:web, "#{ROOT}/subjects/math", method: :post, headers: TEACHER.merge("X-CSRF-Token" => token_for(TEACHER)), remote_addr: EDGE)
    token = ApiToken.issue!(role: "agent_claude", label: "preview isolation")
    assert_empty Student.real.select { |s| s.kind == "preview" }
    assert_empty Teacher::Dashboard.new.students.select { |s| s.id == preview.id }
    [ "/teacher", "/teacher/students", "/teacher/corrections", "/teacher/comments", "/teacher/subjects/math/report", "/teacher/subjects/math/practice",
      "/teacher/subjects/math/course", "/teacher/dashboard/state" ].each do |path|
      page(TEACHER, path)
      assert_response :success, path
      assert_no_match(/preview(\.\d+)?\b/i, css_select("main, body").first.text.gsub(/Prova come studente|Anteprima|anteprima/, ""), path) unless path.end_with?("/state")
      assert_not_includes response.body, "student=preview", path
    end
    page(TEACHER, "/teacher?student=preview")
    assert_not_includes response.body, "student=preview"
    answers = Search::Builders::Answers.call
    assert_empty answers.select { |d| d.student_key.to_s.start_with?("preview") }
    auth = { "Authorization" => "Bearer #{token}" }
    [ "/api/v1/status", "/api/v1/diagnosis/report", "/api/v1/subjects/math/practice/progress", "/api/v1/submissions/pending" ].each do |path|
      on(:api, path, headers: auth)
      assert_not_includes response.body, "preview", path
    end
    %w[preview preview.1].each do |key|
      on(:api, "/api/v1/diagnosis/report?student=#{key}", headers: auth)
      assert_includes [ 400, 404 ], response.status, key
      on(:api, "/api/v1/subjects/math/practice/progress?student=#{key}", headers: auth)
      assert_not_equal 200, response.status, key
    end
    assert_equal 1, PracticeAttempt.where(student: preview).count
  end

  test "a preview run of the entry test is the preview student's, and a reset never hides it from the approval gate" do
    build_student_world
    rows = nil
    assert_nothing_raised { rows = Student.current_preview }
    assert_equal "preview", rows.key
    assert_predicate rows, :preview?
    refute_predicate rows, :official?
    refute_predicate rows, :trial?
  end

  # ---- no decision, no comment ------------------------------------------------------------------------

  test "no decision, no comment and no question come from a preview page" do
    build_student_world
    walk!
    page(TEACHER, "#{ROOT}/topics/#{TOPIC}")
    assert_select "#comment-root", 0
    assert_select "#comment-open-menu", 0
    assert_select "form[action*='/teacher/'][action*='approve']", 0
    assert_select "form[action*='release']", 0
    before = [ Decision.count, Comment.count, StudentQuestion.count ]
    [ "/comments", "/questions", "/subjects/math/course-release", "/topic-revisions/1/approve", "/release", "/consent" ].each do |path|
      on(:web, "#{ROOT}#{path}", method: :post, headers: TEACHER.merge(JSON_HEADERS, "X-CSRF-Token" => token_for(TEACHER)), params: "{}", remote_addr: EDGE)
      assert_response :not_found, path
    end
    on(:web, "#{ROOT}/comments", headers: TEACHER, remote_addr: EDGE)
    assert_response :not_found
    on(:web, "/comments", method: :post, headers: TEACHER.merge(JSON_HEADERS, "X-CSRF-Token" => token_for(TEACHER)), params: "{}", remote_addr: EDGE)
    assert_response :forbidden
    assert_equal before, [ Decision.count, Comment.count, StudentQuestion.count ]
  end

  # ---- the reset --------------------------------------------------------------------------------------

  test "«Ricomincia da capo» gives a new preview student with a clean slate, and the old rows stay (append-only)" do
    build_student_world
    walk!
    old = preview_student
    old_rows = [ LessonEvent.where(student: old).count, PracticeServe.where(student: old).count, PracticeAttempt.where(student: old).count ]
    assert old_rows.all?(&:positive?)
    states = Course::StudentView.new(old, view: :official).states.values.map(&:state)
    assert_includes states, "in_study"
    page(TEACHER, "#{ROOT}/today")
    assert_select "form[action='#{ROOT}/reset'] button#preview-reset-confirm"
    assert_difference("Student.count", 1) { post_form(TEACHER, "#{ROOT}/reset", { back: "#{ROOT}/subjects" }) }
    assert_response :see_other
    assert_equal ROOT, URI(response.location).path, "a reset lands on the preview home"
    fresh = preview_student
    assert_not_equal old.id, fresh.id
    assert_equal "preview.2", fresh.key
    assert_predicate fresh, :preview?
    assert_equal old_rows, [ LessonEvent.where(student: old).count, PracticeServe.where(student: old).count, PracticeAttempt.where(student: old).count ]
    assert_equal [ 0, 0, 0 ], [ LessonEvent.where(student: fresh).count, PracticeServe.where(student: fresh).count, PracticeAttempt.where(student: fresh).count ]
    assert_equal({ theme: "cream", size: "normal" }, Diagnosis::Preferences.for(fresh))
    assert_empty Course::StudentView.new(fresh, view: :official).states.values.map(&:state).uniq - %w[not_seen to_learn]
    page(TEACHER, ROOT)
    assert_select "#resume", 0
    assert_select "#preview-banner", /Ricominci da capo/
    # the log is append-only: the reset updated and deleted nothing
    assert_raises(ActiveRecord::StatementInvalid) { Student.connection.execute("UPDATE students SET key = 'x' WHERE id = #{old.id}") }
    assert_raises(ActiveRecord::StatementInvalid) { Student.connection.execute("DELETE FROM students WHERE id = #{old.id}") }
    assert_raises(ActiveRecord::StatementInvalid) { LessonEvent.connection.execute("DELETE FROM lesson_events") }
    # and the new student is the one that gets the next rows
    walk!
    assert_equal 2, LessonEvent.where(student: fresh).count
    assert_equal old_rows.first, LessonEvent.where(student: old).count
  end

  test "a login cannot be mapped to a preview key, so no student can ever act as one" do
    build_student_world
    assert_not Student::KEY_FORMAT.match?("preview.2")
    assert_not Banco::EdgeProxy.student_map("BANCO_STUDENT_USERS" => "kid=preview,kid2=preview.2").key?("kid2")
    assert_not Banco::EdgeProxy.student_map("BANCO_STUDENT_USERS" => "kid=preview").key?("kid")
  end
end
