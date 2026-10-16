require "test_helper"
require_relative "../support/finished_run"
require_relative "../support/practice_world"

# D-298: the refused texts kept for the teacher (and never given to the agent), the list that shows a
# finished subject as finished, and the line that suggests a pause after two subjects in a day.
class SittingFeedbackTest < ActionDispatch::IntegrationTest
  include FinishedRun
  include PracticeWorld

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

  def as_teacher(path) = on(:web, path, headers: TEACHER, remote_addr: EDGE)

  def answer(step, raw) = as_student("/diagnosis/answers", method: :post, body: { served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: raw, source: "text" })

  # ---- the refused text, for the teacher only

  test "refused texts are kept, shown to the teacher under the accepted answer, deduplicated, and never given to the agent" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    step = Diagnosis::Conductor.new(run).step!
    %w[1-12 art.\ 54 1-12].each { |text| answer(step, text) }
    assert_equal "invalid", response.parsed_body["status"]
    answer(step, "") # empty: no event
    answer(step, "99")
    assert_equal "recorded", response.parsed_body["status"]
    events = AppEvent.where(kind: "invalid_input").order(:id)
    assert_equal 3, events.count
    assert_equal %w[1-12 art.\ 54 1-12], events.map { |e| JSON.parse(e.payload_json)["text"] }

    as_teacher("/teacher/subjects/math/report")
    assert_response :success
    assert_select "#report-refused li[data-skill='math.number']" do
      assert_select "code", "99"
      assert_select "p.refused-tries", /Tentativi non letti:/
      assert_select "p.refused-tries q", 2
      assert_select "p.refused-tries q", "1-12"
      assert_select "p.refused-tries", /×2/
    end

    token = ApiToken.issue!(role: "agent_claude", label: "refused")
    on(:api, "/api/v1/diagnosis/report?subject=math", headers: { "Authorization" => "Bearer #{token}" })
    assert_response :ok
    assert_not response.parsed_body["subjects"].sole.key?("refused_tries")
    assert_not_includes response.body, "art. 54"
    assert_not_includes response.body, "1-12"
  end

  test "the refused text is cut to a sensible length" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    step = Diagnosis::Conductor.new(Diagnosis::Conductor.run_for(rows[:student], rows[:subject])).step!
    answer(step, "x" * 5000)
    assert_equal Diagnosis::AnswerRecorder::REFUSED_TEXT_CHARS, JSON.parse(AppEvent.where(kind: "invalid_input").last.payload_json)["text"].size
  end

  test "an empty answer records no event and a readable one keeps no refused text" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    step = Diagnosis::Conductor.new(Diagnosis::Conductor.run_for(rows[:student], rows[:subject])).step!
    answer(step, "   ")
    answer(step, "5")
    assert_equal 0, AppEvent.where(kind: "invalid_input").count
  end

  test "the practice trail shows the refused tries under the answer" do
    build_practice_world
    c = serve!
    answer!(c, "3.5")
    answer!(c, "3.5")
    answer!(c, "x y")
    answer!(c, correct_raw(c))
    event = AppEvent.where(kind: "practice_invalid_input").last
    assert_equal "x y", JSON.parse(event.payload_json)["text"]
    steps = Teacher::PracticeProgress.new(@topic.lesson.subject, @student).trail(@skill)
    tries = steps.flat_map(&:refused)
    assert_equal [ [ "3.5", 2 ], [ "x y", 1 ] ], tries.map { |t| [ t.text, t.count ] }
  end

  # ---- a finished subject is finished in the list

  test "a run whose next move is to close shows as Fatto, and the list writes nothing" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    conductor = Diagnosis::Conductor.new(run)
    40.times do
      step = conductor.step!
      assert_equal :item, step.type, "the run is not closed by this loop"
      assert_not conductor.finished?, "an item is on screen"
      answer(step, Grading::DONT_KNOW_RAW)
      conductor = Diagnosis::Conductor.new(run)
      break if conductor.finished?
    end
    assert conductor.finished?
    assert_not conductor.closed?
    before = DiagnosisEvent.where(diagnosis_run_id: run.id).count

    as_student("/diagnosis")
    assert_select "li.subject[data-subject=math] .subject-state", "Fatto"
    assert_equal before, DiagnosisEvent.where(diagnosis_run_id: run.id).count
    assert_equal "completed", Diagnosis::Report.call(subject: rows[:subject])[:subjects].sole[:status]

    as_student("/diagnosis/runs/#{run.id}/results")
    assert_response :success
    assert Diagnosis::Conductor.new(run).closed?, "the close is written when the student opens the run"
  end

  # ---- the suggestion to pause

  test "two subjects started today bring the pause line on the list and the end screen; one does not" do
    rows = build_ui_subject(components: %w[number])
    other = build_ui_subject(key: "chemistry", name: "Chimica", position: 2, components: %w[number])
    release_diagnosis!
    first = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    Diagnosis::Conductor.new(first).step!
    as_student("/diagnosis")
    assert_select "#pause-suggestion", 0

    second = Diagnosis::Conductor.run_for(rows[:student], other[:subject])
    Diagnosis::Conductor.new(second).step!
    as_student("/diagnosis")
    assert_select "#pause-suggestion", "Hai già fatto due prove oggi: fai una pausa prima della prossima. Puoi riprendere quando vuoi."
    assert_select "li.subject[data-subject=chemistry] form", 1, "no button is taken away"

    conductor = Diagnosis::Conductor.new(second)
    40.times do
      step = conductor.step!
      break unless step.type == :item

      answer(step, Grading::DONT_KNOW_RAW)
    end
    assert Diagnosis::Conductor.new(second).closed?
    as_student("/diagnosis/runs/#{second.id}/results")
    assert_response :success
    assert_select "#pause-suggestion", /fai una pausa/
  end

  test "sittings of other days do not count" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    old = Diagnosis::FakeClock.new(Time.utc(2020, 1, 6, 9, 0, 0))
    Diagnosis::Conductor.new(Diagnosis::Conductor.run_for(rows[:student], rows[:subject]), clock: old).step!
    assert_equal 0, Diagnosis::Pause.subjects_today(rows[:student])
    assert_equal 1, Diagnosis::Pause.subjects_today(rows[:student], clock: old)
  end
end
