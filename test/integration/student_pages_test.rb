require "test_helper"
require_relative "../support/student_ui_rows"

# Who sees what on /diagnosis and /teacher/preview, in what state, and what each
# endpoint refuses.
class StudentPagesTest < ActionDispatch::IntegrationTest
  include StudentUiRows

  EDGE = ListenerHelpers::EDGE_IP
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze
  TEACHER = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    @saved = ENV.to_h.slice("BANCO_EDGE_PROXY", "BANCO_TEACHER_USERS")
    ENV["BANCO_EDGE_PROXY"] = "#{EDGE}/32"
    ENV["BANCO_TEACHER_USERS"] = "nik"
  end

  teardown do
    %w[BANCO_EDGE_PROXY BANCO_TEACHER_USERS].each { |k| @saved.key?(k) ? ENV[k] = @saved[k] : ENV.delete(k) }
  end

  def as_student(path, method: :get, body: nil)
    on(:web, path, method: method, headers: STUDENT.merge(JSON_HEADERS), params: body&.to_json, remote_addr: EDGE)
  end

  def as_teacher(path, method: :get, body: nil)
    on(:web, path, method: method, headers: TEACHER.merge(JSON_HEADERS), params: body&.to_json, remote_addr: EDGE)
  end

  test "before the release the student sees one line and the warm-up, and nothing else" do
    build_ui_subject
    as_student("/diagnosis")
    assert_response :success
    assert_select "p.notice", "La diagnosi non è ancora aperta."
    assert_select "a[href='/diagnosis/warmup']", "Prova dei comandi"
    assert_select "li.subject", 0
    as_student("/diagnosis/subjects/math", method: :post)
    assert_response :forbidden
  end

  test "the warm-up page is open before the release and shut after it" do
    as_student("/diagnosis/warmup")
    assert_response :success
    release_diagnosis!
    as_student("/diagnosis/warmup")
    assert_redirected_to "/diagnosis"
  end

  test "after the release every subject has a state, and a dependency is named" do
    build_ui_subject
    build_ui_subject(key: "chemistry", name: "Chimica", position: 2, components: %w[number], depends_on: [ "math" ])
    release_diagnosis!
    as_student("/diagnosis")
    assert_response :success
    assert_select "p", "Fai le materie nell'ordine indicato."
    assert_select "li.subject[data-subject=math] .subject-state", "Da fare"
    assert_select "li.subject[data-subject=chemistry] .subject-state", "Prima fai Matematica"
    assert_select "li.subject[data-subject=chemistry] form", 0
    as_student("/diagnosis/subjects/chemistry", method: :post)
    assert_response :forbidden, "a gated subject cannot be started by posting to it"
    as_student("/diagnosis/subjects/math", method: :post)
    assert_response :see_other
    assert_match %r{/diagnosis/runs/\d+\z}, response.location
  end

  test "once the first sitting of the dependency is closed the next subject opens, and the daily cap says Domani" do
    rows = build_ui_subject
    build_ui_subject(key: "chemistry", name: "Chimica", position: 2, components: %w[number], depends_on: [ "math" ])
    build_ui_subject(key: "english", name: "Inglese", position: 3, components: %w[number])
    build_ui_subject(key: "history", name: "Storia", position: 4, components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    conductor = Diagnosis::Conductor.new(run)
    recorder = Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis")
    10.times do
      step = conductor.step!
      break unless step.type == :item

      recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button")
    end
    # The run is held open for the short answer (D-039): the page goes to the end screen, no loop.
    assert conductor.holding?
    assert_equal :final, conductor.step!.type
    as_student("/diagnosis/runs/#{run.id}")
    assert_redirected_to "/diagnosis/runs/#{run.id}/results"
    as_student("/diagnosis/runs/#{run.id}/results")
    assert_response :success
    # Mathematics is done today; one more subject fits in the day, a third waits.
    chemistry = Diagnosis::Conductor.run_for(rows[:student], Subject.find_by!(key: "chemistry"))
    Diagnosis::Conductor.new(chemistry).step!
    as_student("/diagnosis")
    # Done, but the short answer waits for the teacher.
    assert_select "li.subject[data-subject=math] .subject-state", "Fatto · in correzione"
    assert_select "li.subject[data-subject=chemistry] .subject-state", "In pausa"
    assert_select "li.subject[data-subject=english] .subject-state", "Domani"
    assert_select "li.subject[data-subject=history] .subject-state", "Domani"
  end

  test "a run of a subject that cannot start today answers wait and writes nothing" do
    rows = build_ui_subject
    build_ui_subject(key: "chemistry", name: "Chimica", position: 2, components: %w[number], depends_on: [ "math" ])
    release_diagnosis!
    run = Diagnosis::Conductor.fresh_run(rows[:student], Subject.find_by!(key: "chemistry")) # made by hand: the page would not have
    as_student("/diagnosis/runs/#{run.id}/step", method: :post)
    assert_response :success
    assert_equal({ "type" => "wait" }, response.parsed_body)
    assert_equal 0, run.events.count
  end

  test "the sitting start screen shows the blueprint's intro note and its calculator line" do
    rows = build_ui_subject
    release_diagnosis!
    as_teacher("/teacher/preview/subjects/math", method: :post)
    as_teacher(URI(response.location).path)
    assert_response :success
    assert_select "#intro-note", "Nota di prova per chi comincia."
    assert_select "section[data-sitting-target=intro] li", /calcolatrice/i
  end

  test "the student cannot reach the teacher's preview and the teacher cannot answer as the student" do
    build_ui_subject
    release_diagnosis!
    as_student("/teacher/preview")
    assert_response :forbidden
    as_student("/teacher/preview/subjects/math", method: :post)
    assert_response :forbidden
    as_teacher("/diagnosis")
    assert_response :forbidden
  end

  test "a preview run is the teacher's own: preview student, teacher_preview context, nothing in the student's log" do
    rows = build_ui_subject
    as_teacher("/teacher/preview")
    assert_response :success
    assert_select "button", /Prova Matematica/
    as_teacher("/teacher/preview/subjects/math", method: :post)
    assert_response :see_other
    run_path = URI(response.location).path
    assert_match %r{\A/teacher/preview/runs/\d+\z}, run_path
    run = DiagnosisRun.find(run_path[/\d+\z/])
    assert_equal rows[:preview], run.student
    as_teacher("#{run_path}/step", method: :post)
    assert_response :success
    step = response.parsed_body
    as_teacher("/teacher/preview/answers", method: :post,
               body: { served_event_id: step["served_event_id"], client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button" })
    assert_equal({ "status" => "recorded" }, response.parsed_body)
    assert_equal [ "teacher_preview" ], Attempt.pluck(:context).uniq
    assert_equal rows[:preview].id, Attempt.first.student_id
    assert_equal 0, Attempt.where(student: rows[:student]).count
    assert_equal 0, DiagnosisRun.where(student: rows[:student]).count
  end

  test "a student cannot read, step or answer into another student's run" do
    rows = build_ui_subject
    release_diagnosis!
    preview_run = Diagnosis::Conductor.fresh_run(rows[:preview], rows[:subject])
    as_student("/diagnosis/runs/#{preview_run.id}")
    assert_response :not_found
    as_student("/diagnosis/runs/#{preview_run.id}/step", method: :post)
    assert_response :not_found
    step = Diagnosis::Conductor.new(preview_run).step!
    as_student("/diagnosis/answers", method: :post,
               body: { served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "3", source: "text" })
    assert_equal "invalid", response.parsed_body["status"]
    assert_equal 0, Attempt.count
  end

  test "pause and visibility events go to the log once per change, keep-alive writes nothing, anything else is refused" do
    rows = build_ui_subject
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    as_student("/diagnosis/runs/#{run.id}/step", method: :post)
    before = run.events.count
    %w[paused paused resumed hidden visible keepalive].each { |kind| as_student("/diagnosis/runs/#{run.id}/events", method: :post, body: { kind: kind }); assert_response :success }
    assert_equal before + 4, run.events.count
    as_student("/diagnosis/runs/#{run.id}/events", method: :post, body: { kind: "run_closed" })
    assert_response :unprocessable_entity
    assert_equal before + 4, run.events.count
  end

  test "the end screen is only for a closed run, and flagging an answer reaches the teacher once" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    as_student("/diagnosis/runs/#{run.id}/results")
    assert_redirected_to "/diagnosis/runs/#{run.id}"
    conductor = Diagnosis::Conductor.new(run)
    recorder = Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis")
    5.times do
      step = conductor.step!
      break unless step.type == :item

      recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "6", source: "text")
    end
    as_student("/diagnosis/runs/#{run.id}")
    assert_redirected_to "/diagnosis/runs/#{run.id}/results"
    as_student("/diagnosis/runs/#{run.id}/results")
    assert_response :success
    assert_select "h1", "Hai finito Matematica."
    assert_select "article.solution", Attempt.count # "6" is right for one instance only: two or three items
    assert_select ".closing", "Questo non è un voto. Da domani il piano parte da qui."
    attempt = Attempt.first
    2.times do
      as_student("/diagnosis/runs/#{run.id}/flags", method: :post, body: { attempt_id: attempt.id })
      assert_response :success
    end
    assert_equal 1, AppEvent.where(kind: "answer_flagged").count
    as_student("/diagnosis/runs/#{run.id}/flags", method: :post, body: { attempt_id: 999_999 })
    assert_response :not_found
  end

  test "an unknown answer, a repeated client id with a different serve and a huge raw are handled" do
    rows = build_ui_subject
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    step = Diagnosis::Conductor.new(run).step!
    as_student("/diagnosis/answers", method: :post, body: { served_event_id: 999_999, client_attempt_id: SecureRandom.uuid, raw: "1", source: "text" })
    assert_equal({ "status" => "invalid", "message_it" => "Questa domanda non è più aperta." }, response.parsed_body)
    as_student("/diagnosis/answers", method: :post, body: { served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "9" * 30_000, source: "text" })
    assert_equal "invalid", response.parsed_body["status"]
    as_student("/diagnosis/answers", method: :post, body: { served_event_id: step.event.id, client_attempt_id: "x", raw: "1", source: "text" })
    assert_equal "invalid", response.parsed_body["status"]
    assert_equal 0, Attempt.count
  end

  test "an answer the grader cannot read is refused with a message and writes no attempt" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    step = Diagnosis::Conductor.new(run).step!
    as_student("/diagnosis/answers", method: :post, body: { served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "3.5", source: "text" })
    assert_equal({ "status" => "invalid", "message_it" => "Per i decimali usa la virgola, per esempio 3,5." }, response.parsed_body)
    assert_equal 0, Attempt.count
    assert_equal 1, AppEvent.where(kind: "invalid_input").count
  end

  test "a grader that does not answer still records the answer and schedules the retry" do
    rows = build_ui_subject(components: %w[expression])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    step = Diagnosis::Conductor.new(run).step!
    raising = ->(*_args, **_kw) { raise Grading::Expression::Unavailable }
    scheduled = []
    Grading::Expression.stub(:grade, raising) do
      Grading::Recorder.stub(:schedule_retry, ->(attempt) { scheduled << attempt.id }) do
        as_student("/diagnosis/answers", method: :post, body: { served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "2x+2", source: "mathlive" })
      end
    end
    assert_equal({ "status" => "recorded" }, response.parsed_body)
    assert_equal 1, Attempt.count
    assert_equal 0, AttemptGrading.count
    assert_equal [ Attempt.first.id ], scheduled
  end

  test "grading never runs inside a transaction opened by the recorder" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    step = Diagnosis::Conductor.new(run).step!
    seen = []
    original = Grading.method(:grade)
    Grading.stub(:grade, ->(*args, **kw) { seen << Attempt.count; original.call(*args, **kw) }) do
      as_student("/diagnosis/answers", method: :post, body: { served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "6", source: "text" })
    end
    assert_equal [ 0 ], seen, "the attempt is appended after the grading"
    assert_equal 1, Attempt.count
  end

  test "the student's answer text never reaches the request log" do
    rows = build_ui_subject
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    step = Diagnosis::Conductor.new(run).step!
    io = StringIO.new
    Rails.logger.broadcast_to(ActiveSupport::Logger.new(io))
    as_student("/diagnosis/answers", method: :post,
               body: { served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: "risposta-privata-xyz", source: "text" })
    assert_match(/Parameters:/, io.string)
    assert_no_match(/risposta-privata-xyz/, io.string)
    assert_match(/served_event_id/, io.string)
  end
end
