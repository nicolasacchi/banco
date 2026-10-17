require "test_helper"
require_relative "../support/student_ui_rows"

# D-304: a comment in the entry test names the served event it was written on (checked against this student's runs),
# opening the box stops the counted time, and neither changes a grade or the engine's path.
class CommentsSittingTest < ActionDispatch::IntegrationTest
  include StudentUiRows

  EDGE = ListenerHelpers::EDGE_IP
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze
  OTHER = { "Remote-User" => "other", "Remote-Groups" => "banco-student" }.freeze
  TEACHER = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze
  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup do
    @saved = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS", "BANCO_STUDENT_USERS")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    ENV["BANCO_TEACHER_USERS"] = "nik"
    ENV["BANCO_STUDENT_USERS"] = "student=student,other=prova-9"
    @rows = build_ui_subject
    release_diagnosis!
    @student = @rows[:student]
    @run = Diagnosis::Conductor.run_for(@student, @rows[:subject])
    @conductor = Diagnosis::Conductor.new(@run)
    @served = @conductor.step!.event
  end

  teardown { %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS BANCO_STUDENT_USERS].each { |k| @saved.key?(k) ? ENV[k] = @saved[k] : ENV.delete(k) } }

  def web(path, headers: STUDENT, method: :get, body: nil)
    on(:web, path, method: method, headers: method == :get ? headers : headers.merge(JSON_HEADERS), params: body&.to_json, remote_addr: EDGE)
  end

  def comment(path:, refs: {}, **over)
    web("/comments", method: :post, headers: over.delete(:headers) || STUDENT,
                     body: { client_comment_id: "s-" + SecureRandom.hex(8), reason: "error", text_it: "C'è un errore.", page_path: path, anchor: "question/item/prompt", refs: refs }.merge(over))
    response.parsed_body
  end

  def run_path = "/diagnosis/runs/#{@run.id}"

  test "the sitting page has the comment control, the events address for the clock and the served event on the item" do
    web(run_path)
    assert_response :success
    assert_select "#comment-root[data-comment-events-url-value='#{run_path}/events']"
    assert_select "#comment-open-sitting", 0, "one «Commenta» in the bar, none beside the question (D-307)"
    assert_select "#comment-open-menu"
    assert_select "[data-sitting-target=itemBox][data-comment-anchor=question]"
  end

  test "a comment on the question names the served event and derives the item and blueprint" do
    reply = comment(path: run_path, refs: { served_event_id: @served.id })
    assert_equal "recorded", reply["status"]
    c = Comment.last
    served = ItemServed.find_by!(diagnosis_event_id: @served.id)
    assert_equal [ @run.id, @served.id, served.item_instance_id, served.item_instance.item_revision_id, @run.blueprint_revision_id, "sitting" ],
                 [ c.diagnosis_run_id, c.served_event_id, c.item_instance_id, c.item_revision_id, c.blueprint_revision_id, c.page_kind ]
  end

  test "a served event of another run, another student's run, or an event that is no serve is refused" do
    other_run = Diagnosis::Conductor.fresh_run(Student.create!(key: "prova-9", kind: "student"), @rows[:subject])
    other_served = Diagnosis::Conductor.new(other_run).step!.event
    started = @run.events.find_by!(kind: "sitting_started")
    assert_equal "invalid", comment(path: run_path, refs: { served_event_id: other_served.id })["status"]
    assert_equal "invalid", comment(path: run_path, refs: { served_event_id: started.id })["status"]
    assert_equal "invalid", comment(path: run_path, refs: { served_event_id: 999_999 })["status"]
    assert_equal "invalid", comment(path: "/diagnosis/runs/#{other_run.id}", refs: { served_event_id: other_served.id })["status"]
    assert_equal "invalid", comment(path: "/diagnosis/runs/#{other_run.id}", refs: { served_event_id: other_served.id }, headers: OTHER, reason: "angry")["status"]
    assert_equal 0, Comment.count
  end

  test "the other student can comment on their own run and not on this one" do
    other_student = Student.create!(key: "prova-9", kind: "student")
    other_run = Diagnosis::Conductor.run_for(other_student, @rows[:subject])
    other_served = Diagnosis::Conductor.new(other_run).step!.event
    assert_equal "recorded", comment(path: "/diagnosis/runs/#{other_run.id}", refs: { served_event_id: other_served.id }, headers: OTHER)["status"]
    assert Comment.last.trial
    assert_equal "invalid", comment(path: run_path, refs: { served_event_id: @served.id }, headers: OTHER)["status"]
  end

  test "the results page takes a comment on the run, with no event or one of the run" do
    assert_equal "recorded", comment(path: "#{run_path}/results", anchor: "section:soluzioni")["status"]
    assert_equal "results", Comment.last.page_kind
  end

  test "the events address takes the comment pair, only on change, and a student's comment never serves or answers anything" do
    before = [ ItemServed.count, Attempt.count ]
    web("#{run_path}/events", method: :post, body: { kind: "comment_opened" })
    assert_response :success
    web("#{run_path}/events", method: :post, body: { kind: "comment_opened" })
    web("#{run_path}/events", method: :post, body: { kind: "comment_closed" })
    web("#{run_path}/events", method: :post, body: { kind: "comment_closed" })
    assert_equal %w[comment_opened comment_closed], @run.events.where(kind: %w[comment_opened comment_closed]).order(:seq).pluck(:kind)
    web("#{run_path}/events", method: :post, body: { kind: "comment_exploded" })
    assert_response :unprocessable_entity
    comment(path: run_path, refs: { served_event_id: @served.id })
    assert_equal before, [ ItemServed.count, Attempt.count ]
  end

  test "another student cannot post comment events into this run" do
    web("#{run_path}/events", headers: OTHER, method: :post, body: { kind: "comment_opened" })
    assert_response :not_found
    assert_equal 0, @run.events.where(kind: "comment_opened").count
  end

  test "the counted time of an item leaves out the open box, and the next serve is the same as without any comment" do
    clock = Diagnosis::FakeClock.new
    run = Diagnosis::Conductor.fresh_run(@student, @rows[:subject])
    conductor = Diagnosis::Conductor.new(run, clock: clock)
    recorder = Diagnosis::AnswerRecorder.new(student: @student, context: "diagnosis", clock: clock)
    step = conductor.step!
    clock.advance(20)
    assert conductor.record("comment_opened")
    clock.advance(900)
    assert conductor.record("comment_closed")
    clock.advance(25)
    recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button")
    assert_equal 45, conductor.state.counted_seconds_total
    assert_equal :item, conductor.step!.type, "the run goes on with the next item"
  end

  test "the teacher's preview of the test has no comment control and takes no comment events" do
    preview_run = Diagnosis::Conductor.fresh_run(Student.find_by!(key: "preview"), @rows[:subject])
    web("/teacher/preview/runs/#{preview_run.id}", headers: TEACHER)
    assert_response :success
    assert_select "#comment-root", 0
    assert_select "[data-comment-open]", 0
    assert_equal 0, Comment.count
  end
end
