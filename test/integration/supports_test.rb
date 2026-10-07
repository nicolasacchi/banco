require "test_helper"
require_relative "../support/student_ui_rows"
require_relative "../support/decision_world"
require_relative "../support/finished_run"

# D-216: the standard instructions, the answer format and the steps, the help box, and the formula
# sheet as a declared support (decision, availability and openings per item, the report marks).
class SupportsTest < ActionDispatch::IntegrationTest
  include FinishedRun

  EDGE = ListenerHelpers::EDGE_IP
  STUDENT = { "Remote-User" => "student", "Remote-Groups" => "banco-student" }.freeze
  TEACHER = { "Remote-User" => "nik", "Remote-Groups" => "banco-teacher" }.freeze
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze
  SHEET = "Area del rettangolo: $A = b \\cdot h$.".freeze

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

  def switch_sheet!(subject, enabled)
    Decision.create!(kind: "set_formula_sheet", subject: subject, payload_json: { subject: subject.key, enabled: enabled }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
  end

  # Serves items to the student until one has +component+; returns [run, conductor, event, presentation].
  def serve_component(rows, component)
    run = Diagnosis::Conductor.run_for(rows[:student], rows[:subject])
    conductor = Diagnosis::Conductor.new(run)
    recorder = Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis")
    12.times do
      step = conductor.step!
      raise "no #{component} item served" unless step.type == :item

      presentation = conductor.presentation(step.event, student: rows[:student])
      return [ run, conductor, step.event, presentation ] if presentation[:item][:component] == component

      recorder.call(served_event_id: step.event.id, client_attempt_id: SecureRandom.uuid, raw: Grading::DONT_KNOW_RAW, source: "button")
    end
    raise "no #{component} item served"
  end

  # ---- 1. the start screen ----------------------------------------------------------------

  test "the start screen has a Come funziona block with the standard instructions" do
    rows = build_ui_subject
    release_diagnosis!
    as_student("/diagnosis/subjects/math", method: :post)
    as_student(URI(response.location).path)
    assert_response :success
    assert_select "section#how-it-works h2", "Come funziona"
    text = css_select("section#how-it-works li").map(&:text).join(" ")
    [ /domande cambiano in base alle tue risposte/, /Dura circa 30 minuti/, /Pausa/, /Non lo so/, /Non l'ho ancora studiato/, /Non sono errori/,
      /sul foglio/, /calcolatrice/, /Non è un voto/, /Invia/, /Come si risponde/ ].each { |re| assert_match re, text }
    assert_select "#intro-formula-sheet", 0
  end

  test "the start screen names the formula sheet only when the teacher switched it on" do
    rows = build_ui_subject(formula_sheet: SHEET)
    release_diagnosis!
    switch_sheet!(rows[:subject], true)
    as_student("/diagnosis/subjects/math", method: :post)
    as_student(URI(response.location).path)
    assert_select "#intro-formula-sheet", /Formulario/
    assert_select "#intro-formula-sheet", /All'esame non c'è/
  end

  # ---- 2. answer format and steps -----------------------------------------------------------

  test "the presentation carries the item's steps and answer format, and an instance's own" do
    rows = build_ui_subject(components: %w[number fraction])
    release_diagnosis!
    _run, _conductor, _event, number = serve_component(rows, "number")
    assert_equal "Scrivi solo il numero, per esempio 12.", number[:item][:answer_format_it]
    assert_equal [ "Leggi il conto.", "Scrivi il risultato." ], number[:item][:steps_it]
    _run, _conductor, _event, fraction = serve_component(rows, "fraction")
    assert_equal "Scrivi la frazione nelle due caselle.", fraction[:item][:answer_format_it]
    assert_not fraction[:item].key?(:steps_it)
    assert_not number.key?(:formula_sheet_it)
  end

  test "the teacher's all-questions page and item play carry the same texts" do
    rows = build_ui_subject(components: %w[number fraction])
    as_teacher("/teacher/subjects/math/test/all")
    assert_response :success
    presentations = css_select("[data-presentation]").map { |n| JSON.parse(n["data-presentation"]) }
    number = presentations.find { |p| p["component"] == "number" }
    assert_equal "Scrivi solo il numero, per esempio 12.", number["answer_format_it"]
    assert_equal [ "Leggi il conto.", "Scrivi il risultato." ], number["steps_it"]
    fraction = presentations.find { |p| p["component"] == "fraction" }
    assert_equal "Scrivi la frazione nelle due caselle.", fraction["answer_format_it"]
    as_teacher("/teacher/items/#{rows[:revisions]['number'].id}/play/data?n=1")
    assert_response :success
    assert_equal [ "Leggi il conto.", "Scrivi il risultato." ], response.parsed_body["item"]["steps_it"]
  end

  # ---- 3. the help box ------------------------------------------------------------------------

  test "opening the help logs an app event with the component and changes nothing of the evidence" do
    rows = build_ui_subject(components: %w[number])
    release_diagnosis!
    run, _conductor, event, = serve_component(rows, "number")
    before = [ DiagnosisEvent.count, Attempt.count, AttemptGrading.count, ItemServed.count, run.events.order(:seq).pluck(:kind, :payload_json) ]
    as_student("/diagnosis/runs/#{run.id}/support", method: :post, body: { kind: "help_opened", served_event_id: event.id, component: "number" })
    assert_response :success
    app_event = AppEvent.where(kind: "help_opened").sole
    assert_equal rows[:student].id, app_event.student_id
    assert_equal({ "run_id" => run.id, "served_event_id" => event.id, "component" => "number" }, JSON.parse(app_event.payload_json))
    assert_equal before, [ DiagnosisEvent.count, Attempt.count, AttemptGrading.count, ItemServed.count, run.events.order(:seq).pluck(:kind, :payload_json) ]
  end

  test "the support endpoint refuses an unknown kind, a serve of another run and, for the sheet, an item served without it" do
    rows = build_ui_subject(components: %w[number], formula_sheet: SHEET)
    release_diagnosis!
    run, _conductor, event, = serve_component(rows, "number")
    as_student("/diagnosis/runs/#{run.id}/support", method: :post, body: { kind: "answer_flagged", served_event_id: event.id })
    assert_response :not_found
    as_student("/diagnosis/runs/#{run.id}/support", method: :post, body: { kind: "help_opened", served_event_id: event.id + 999 })
    assert_response :not_found
    as_student("/diagnosis/runs/#{run.id}/support", method: :post, body: { kind: "formula_sheet_opened", served_event_id: event.id })
    assert_response :forbidden, "the sheet is off: it cannot be opened"
    assert_equal 0, AppEvent.where(kind: %w[help_opened formula_sheet_opened answer_flagged]).count
  end

  test "the help texts exist for every component and the sitting page carries the box and the sheet button" do
    build_ui_subject
    release_diagnosis!
    as_student("/diagnosis/subjects/math", method: :post)
    as_student(URI(response.location).path)
    assert_select "details#answer-help summary", "Come si risponde"
    assert_select "button#sheet-button[hidden]"
    texts = JSON.parse(css_select("main[data-controller=sitting]").first["data-sitting-texts-value"])
    %w[number fraction expression choice ordering matching normalized_text short_answer testlet common].each do |name|
      assert_operator texts["help"][name].size, :>=, 2, name
    end
    assert_match(/12:4/, texts["help"]["expression"].join(" "))
    assert_match(/virgola/, texts["help"]["number"].join(" "))
  end

  # ---- 4. the formula sheet --------------------------------------------------------------------

  test "the sheet is off by default: not in the page, not in the step, not recorded as available" do
    rows = build_ui_subject(components: %w[number], formula_sheet: SHEET)
    release_diagnosis!
    as_student("/diagnosis/subjects/math", method: :post)
    page = URI(response.location).path
    as_student(page)
    assert_not_includes response.body, "Area del rettangolo"
    as_student("#{page}/step", method: :post)
    assert_equal "item", response.parsed_body["type"]
    assert_not response.parsed_body.key?("formula_sheet_it")
    assert_not_includes response.body, "Area del rettangolo"
    assert_equal [ false ], ItemServed.pluck(:formula_sheet_available)
    assert_not Diagnosis::FormulaSheet.enabled?(rows[:subject])
  end

  test "switched on: the step carries the sheet, the serve records it, each opening is an event, the report marks it" do
    rows = build_ui_subject(components: %w[number], formula_sheet: SHEET)
    release_diagnosis!
    switch_sheet!(rows[:subject], true)
    as_student("/diagnosis/subjects/math", method: :post)
    page = URI(response.location).path
    as_student("#{page}/step", method: :post)
    assert_equal SHEET, response.parsed_body["formula_sheet_it"]
    served_id = response.parsed_body["served_event_id"]
    assert_equal [ true ], ItemServed.pluck(:formula_sheet_available)

    2.times do
      as_student("#{page}/support", method: :post, body: { kind: "formula_sheet_opened", served_event_id: served_id })
      assert_response :success
    end
    assert_equal 2, AppEvent.where(kind: "formula_sheet_opened").count
    opened = AppEvent.where(kind: "formula_sheet_opened").map { |e| JSON.parse(e.payload_json) }
    assert(opened.all? { |p| p["served_event_id"] == served_id && p["run_id"] == DiagnosisRun.last.id })

    # An answer, then the next item: the teacher switches the sheet off; the first row stays as it was.
    as_student("/diagnosis/answers", method: :post, body: { served_event_id: served_id, client_attempt_id: "attempt-sheet-1", raw: "6", source: "text" })
    assert_equal "recorded", response.parsed_body["status"]
    switch_sheet!(rows[:subject], false)
    as_student("#{page}/step", method: :post)
    assert_not response.parsed_body.key?("formula_sheet_it") if response.parsed_body["type"] == "item"
    assert_equal true, ItemServed.order(:id).first.formula_sheet_available
    assert_equal false, ItemServed.order(:id).last.formula_sheet_available if ItemServed.count > 1

    report = Diagnosis::Report.call(subject: rows[:subject]).fetch(:subjects).sole
    assert_equal 1, report[:formula_sheet][:available]
    assert_equal 1, report[:formula_sheet][:opened]
    assert_equal false, report[:formula_sheet][:enabled]
    skill = report[:skills].find { |s| s[:skill] == "math.number" }
    assert_equal "con formulario disponibile", skill[:marks].first
    assert_equal "con formulario consultato", skill[:marks].last
    assert_equal({ attempts: 1, available: 1, opened: 1 }, skill[:formula_sheet])
  end

  test "a skill answered without the sheet carries no mark, and available is not opened" do
    rows = build_ui_subject(components: %w[number], formula_sheet: SHEET)
    release_diagnosis!
    switch_sheet!(rows[:subject], true)
    run, _conductor, event, = serve_component(rows, "number")
    Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis").call(served_event_id: event.id, client_attempt_id: "c-available-1", raw: "6", source: "text")
    skill = Diagnosis::Report.call(subject: rows[:subject])[:subjects].sole[:skills].find { |s| s[:skill] == "math.number" }
    assert_equal [ "con formulario disponibile" ], skill[:marks]
    assert_equal({ attempts: 1, available: 1, opened: 0 }, skill[:formula_sheet])
    assert run
  end

  test "the evidence does not depend on the sheet: the same answers give the same outcomes with and without it" do
    with = build_ui_subject(components: %w[number choice], formula_sheet: SHEET)
    without = build_ui_subject(key: "english", name: "Inglese", position: 2, components: %w[number choice])
    release_diagnosis!
    switch_sheet!(with[:subject], true)
    answers = { "number" => "99" }
    runs = [ with, without ].map { |rows| play_run(with[:student], rows[:subject], answers: answers) }
    assert_equal [ true ], ItemServed.where(diagnosis_event_id: runs[0].events.select(:id)).pluck(:formula_sheet_available).uniq
    assert_equal [ false ], ItemServed.where(diagnosis_event_id: runs[1].events.select(:id)).pluck(:formula_sheet_available).uniq
    outcomes = runs.map do |run|
      result = Diagnosis::Derivation.result(Diagnosis::Conductor.new(run).plan, Diagnosis::EventLoader.for_run(run))
      result[:skills].map { |r| [ r[:skill].split(".").last, r[:state], r[:reason], r[:evidence] ] }.sort_by(&:first)
    end
    assert_equal outcomes[0], outcomes[1]
    gradings = runs.map { |run| AttemptGrading.joins(:attempt).where(attempts: { served_event_id: run.events.select(:id) }).order("attempts.id").pluck(:verdict) }
    assert_equal gradings[0], gradings[1]
  end

  test "the teacher's test page shows the switch and the report page shows the marks plainly" do
    rows = build_ui_subject(components: %w[number], formula_sheet: SHEET)
    release_diagnosis!
    as_teacher("/teacher/subjects/math/test")
    assert_response :success
    assert_select "#test-formula-sheet[data-enabled=false]"
    assert_select "#formula-sheet-form input[name=enabled][value=true]"
    assert_select "#formula-sheet-text", /Area del rettangolo/
    switch_sheet!(rows[:subject], true)
    as_teacher("/teacher/subjects/math/test")
    assert_select "#test-formula-sheet[data-enabled=true]"
    assert_select "#formula-sheet-form input[name=enabled][value=false]"

    run, _conductor, event, = serve_component(rows, "number")
    as_student("/diagnosis/runs/#{run.id}/support", method: :post, body: { kind: "formula_sheet_opened", served_event_id: event.id })
    Diagnosis::AnswerRecorder.new(student: rows[:student], context: "diagnosis").call(served_event_id: event.id, client_attempt_id: "c-report-1", raw: "6", source: "text")
    as_teacher("/teacher/subjects/math/report")
    assert_response :success
    assert_select "#report-formula-sheet[data-available='1'][data-opened='1']"
    assert_select "#report-formula-sheet", /Con il formulario disponibile: 1 risposte su 1/
    assert_select "li[data-skill='math.number'] strong", /con formulario disponibile · con formulario consultato/
  end

  test "a test with no sheet says so and offers no switch" do
    build_ui_subject(components: %w[number])
    as_teacher("/teacher/subjects/math/test")
    assert_select "#test-formula-sheet", /non ha un formulario/
    assert_select "#formula-sheet-form", 0
  end
end

# The decision itself: only DecisionRecorder writes it, with the guards of every decision (the
# whole matrix is in decision_routes_test); here what is particular to the formula sheet.
class FormulaSheetDecisionTest < ActionDispatch::IntegrationTest
  include DecisionWorld

  test "on needs a sheet in the entry test; off never does; the latest decision counts" do
    rows = build_ui_subject(approve: false)
    decide("/teacher/subjects/math/formula-sheet", { enabled: true })
    assert_response :unprocessable_entity
    assert_match(/no formula sheet/, json["reasons"].first)
    decide("/teacher/subjects/math/formula-sheet", { enabled: false })
    assert_response :success
    assert_not Diagnosis::FormulaSheet.enabled?(rows[:subject])
  end

  test "on is recorded with its provenance and read back; off turns it off again" do
    rows = build_ui_subject(formula_sheet: "Perimetro del quadrato: $P = 4l$.", approve: false)
    assert_difference "Decision.where(kind: 'set_formula_sheet').count", 1 do
      decide("/teacher/subjects/math/formula-sheet", { enabled: true })
    end
    assert_response :success
    decision = Decision.where(kind: "set_formula_sheet").last
    assert_equal "nik", decision.teacher_login
    assert_equal rows[:subject].id, decision.subject_id
    assert_equal({ "subject" => "math", "enabled" => true, "blueprint_revision_id" => rows[:blueprint].id }, JSON.parse(decision.payload_json))
    assert Diagnosis::FormulaSheet.enabled?(rows[:subject])
    decide("/teacher/subjects/math/formula-sheet", { enabled: false })
    assert_not Diagnosis::FormulaSheet.enabled?(rows[:subject])
  end

  test "enabled must be true or false, a subject must exist" do
    build_ui_subject(formula_sheet: "Una formula.", approve: false)
    decide("/teacher/subjects/math/formula-sheet", {})
    assert_response :unprocessable_entity
    decide("/teacher/subjects/math/formula-sheet", { enabled: "maybe" })
    assert_response :unprocessable_entity
    decide("/teacher/subjects/history/formula-sheet", { enabled: true })
    assert_response :not_found
  end

  test "the form post goes back to the teacher's page with a sentence" do
    build_ui_subject(formula_sheet: "Una formula.", approve: false)
    token = csrf_token
    on(:web, "/teacher/subjects/math/formula-sheet", method: :post, headers: TEACHER.merge("X-CSRF-Token" => token),
                                                     params: { enabled: "true", back: "/teacher/subjects/math/test" }, remote_addr: EDGE)
    assert_redirected_to "/teacher/subjects/math/test"
    assert_equal "Formulario aggiornato.", flash[:notice]
  end

  test "an approved test without a sheet cannot switch it on even when a newer draft has one" do
    rows = build_ui_subject
    older = rows[:blueprint]
    BlueprintRevision.create!(subject: rows[:subject], skill_graph_revision: older.skill_graph_revision, author_session: older.author_session, seq: older.seq + 1,
                              body_json: JSON.parse(older.body_json).merge("formula_sheet_it" => "Una formula.").to_json)
    decide("/teacher/subjects/math/formula-sheet", { enabled: true })
    assert_response :unprocessable_entity
  end
end
