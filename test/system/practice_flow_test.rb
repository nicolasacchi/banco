require "application_system_test_case"
require_relative "../support/student_course_world"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# Every button of the practice page, proven end to end in Chrome, for the student (a trial one) and for the teacher in the preview
# (D-309): serve -> a wrong answer -> «Controlla» says so and offers a hint -> «Mostra un aiuto» -> the right answer -> the solution ->
# «Un altro esercizio»; serve -> «Mostrami la soluzione»; a typical error closes the exercise and its «Mostrami la soluzione» still works;
# an empty answer is told and not sent; an answer left in the outbox by a page that went away is told by the next one. One skill for
# each kind of exercise the course practises. Then the list of the topic's exercises (D-337): the statuses, «Salta» keeping the typed
# answer, the autosave and a reload that resumes the last exercise, another entry, «Rifai», a link to another skill, the phone's panel.
# Any JavaScript error, console error or CSP violation fails the test.
class PracticeFlowTest < ApplicationSystemTestCase
  include StudentCourseWorld
  include StudentUiRows
  include StudentSession

  TRIAL_HEADERS = { "Remote-User" => "trial-x", "Remote-Groups" => "banco-student" }.freeze
  PREVIEW = "/teacher/preview".freeze
  HINTS = [ "Che cosa guardi prima?", "Quale regola usi?", "Fai il primo passaggio." ].freeze
  # The kinds of exercise practised in the course, each on a skill of its own (the number one is the world's).
  KINDS = %w[number fraction choice ordering matching normalized_text expression].freeze
  # The number skill of the list tests has three pinned items; every other skill has one.
  NUMBER_KEYS = %w[flow-number flow-number-2 flow-number-3].freeze
  MISSING_ROW = "Manca una risposta: scegli una risposta per ogni riga, poi controlla.".freeze
  UNRECOGNISED = "Questa risposta non corrisponde a un errore che conosco. Ecco un aiuto: riprova.".freeze

  WATCH = <<~JS.freeze
    (() => {
      window.__problems = [];
      const note = (kind, text) => window.__problems.push(kind + ": " + text);
      const consoleError = console.error.bind(console);
      console.error = (...args) => { note("console.error", args.map(String).join(" ")); consoleError(...args); };
      window.addEventListener("error", (e) => note("error", (e.message || "") + " " + (e.filename || "")));
      window.addEventListener("unhandledrejection", (e) => note("unhandledrejection", String(e.reason && e.reason.stack || e.reason)));
      document.addEventListener("securitypolicyviolation", (e) => note("csp", e.violatedDirective + " " + e.blockedURI));
    })();
  JS

  setup do
    @saved_users = ENV["BANCO_STUDENT_USERS"]
    @problems = []
    @watch_id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: WATCH)["identifier"]
    page.driver.browser.page.on("Log.entryAdded") do |params|
      entry = params["entry"] || {}
      @problems << "log #{entry['level']}: #{entry['text']} #{entry['url']}" if %w[error warning].include?(entry["level"]) && entry["source"] != "deprecation" && entry["text"].to_s !~ /favicon/
    end
  end

  teardown do
    begin
      page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: @watch_id) if @watch_id
    rescue StandardError
      nil
    end
    sign_out_env
    @saved_users ? ENV["BANCO_STUDENT_USERS"] = @saved_users : ENV.delete("BANCO_STUDENT_USERS")
  end

  # ---- the world: one topic, one skill per kind of exercise ---------------------------------------------

  def skill_of(kind) = kind == "number" ? SKILL : "math.flow-#{kind.tr('_', '-')}"

  def build_flow_world(approve: true, release: true, number_items: 1)
    build_course
    skills = KINDS.map { |kind| skill_of(kind) }
    @course = build_course_map(skills: [], topics: [ { key: TOPIC, kind: "ripasso", title_it: TOPIC_TITLE, skills: skills, minutes: 30, term: 1, after: [] } ])
    @lesson = Lesson.create!(subject: @subject, key: TOPIC, kind: "ripasso")
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 1, source_md: "---\n", source_sha256: "0" * 64, rules_version: Validation::Rules.version.to_s,
                                              warnings_json: "[]", body_json: JSON.generate(lesson_body.merge(skills: skills)))
    revisions = KINDS.to_h { |kind| [ kind, [ make_flow_item(kind) ] ] }
    (2..number_items).each { |n| revisions["number"] << make_flow_item("number", n) }
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 1, course_revision: @course, lesson_revision: @lesson_revision,
                                            body_json: JSON.generate(schema: "banco.topic/1", key: TOPIC, intro_it: "Qui impari a risolvere le equazioni.",
                                                                     practice: KINDS.map { |kind| { skill: skill_of(kind), items: revisions[kind].map { |r| { item: r.item.key, revision: r.id } } } }))
    @official = practice_student("student")
    @trial = practice_student("prova-1")
    approve_topic!(@topic_revision) if approve
    release_course!(@course) if release
  end

  def make_flow_item(kind, n = 1)
    item = Item.create!(subject: @subject, key: n == 1 ? "flow-#{kind.tr('_', '-')}" : "flow-#{kind.tr('_', '-')}-#{n}", kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "math", skill: skill_of(kind), component: kind, level: 1, expected_seconds: 60,
             prompt: { stem_it: ui_stem(kind) }, hints_it: HINTS,
             error_catalogue: [ { code: "adds_wrong", message_it: "Hai sbagliato un segno." }, { code: "odd_pick", message_it: "Hai scelto un numero dispari." } ] }
    body[:form] = [ "lowest_terms" ] if kind == "fraction"
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    6.times do |i|
      spec = ui_instance_spec(kind, i)
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: spec[:display].to_json, answer_json: spec[:answer].to_json, errors_json: spec[:errors].to_json,
                           hints_json: JSON.generate(HINTS), solution_json: spec[:solution].to_json, fingerprint: Digest::SHA256.hexdigest("flow-#{kind}-#{n}-#{i}"))
    end
    revision
  end

  # ---- the actors ---------------------------------------------------------------------------------------

  def as_student
    ENV["BANCO_STUDENT_USERS"] = "trial-x=prova-1"
    sign_in_as :student
    page.driver.headers = TRIAL_HEADERS
    @base = ""
  end

  def as_teacher_in_preview
    ENV["BANCO_STUDENT_USERS"] = ""
    sign_in_as :teacher
    @base = PREVIEW
  end

  def acting_student = @base == PREVIEW ? Student.where(kind: "preview").order(:id).last : Student.find_by!(key: "prova-1")

  def open_practice(kind)
    visit "#{@base}/topics/#{TOPIC}/practice/#{skill_of(kind)}"
    assert_selector "#check:not([disabled])", wait: 30
    served
  end

  # The serve on the page: the exercise box names it (the comment anchor), the rows say what it holds.
  def served
    find("[data-practice-target=itemBox]", visible: :all)["data-comment-serve-id"].then { |id| PracticeServe.find(id) }
  end

  def next_serve_after(serve)
    assert_selector "#check:not([disabled])", wait: 30
    wait_until { find("[data-practice-target=itemBox]", visible: :all)["data-comment-serve-id"].to_i != serve.id }
    served
  end

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    loop do
      value = yield
      return value if value

      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
  end

  def assert_clean(where)
    @problems.concat(Array(page.evaluate_script("window.__problems || []")))
    assert_empty @problems, "#{where}: the browser reported problems"
  rescue Ferrum::Error
    nil
  end

  # ---- answering through the page -----------------------------------------------------------------------

  def kind_of_serve(serve) = JSON.parse(serve.item_instance.item_revision.body_json)["component"]
  def display_of(serve) = JSON.parse(serve.item_instance.display_json)
  def key_of(serve) = JSON.parse(serve.item_instance.answer_json)
  def errors_of(serve) = JSON.parse(serve.item_instance.errors_json)

  def stored_text(display, id) = %w[options elements left right].flat_map { |k| Array(display[k]) }.find { |e| e["id"] == id }["text"]

  def answer_right(serve)
    display = display_of(serve)
    key = key_of(serve)
    case kind_of_serve(serve)
    when "number" then find("input[inputmode=decimal]").set(key)
    when "fraction"
      all(".fraction input")[0].set(key["n"].to_s)
      all(".fraction input")[1].set(key["d"].to_s)
    when "choice" then find("fieldset.options").find(".option-text", text: stored_text(display, key), exact_text: true).click
    when "ordering" then order_rows(key.map { |id| stored_text(display, id) })
    when "matching" then pair_rows { |left_id| stored_text(display, key[left_id]) }
    when "normalized_text" then find("input[type=text][lang]").set(key)
    when "expression"
      type_in_math_field(*key.chars)
    end
  end

  # An answer the grader does not know as a typical error: «Controlla» says so and offers the first hint.
  def answer_wrong(serve)
    display = display_of(serve)
    key = key_of(serve)
    case kind_of_serve(serve)
    when "number" then find("input[inputmode=decimal]").set("98")
    when "fraction"
      all(".fraction input")[0].set("9")
      all(".fraction input")[1].set("5")
    when "choice"
      declared = errors_of(serve).map { |e| e["value"] }
      plain = display["options"].find { |o| o["id"] != key && !declared.include?(o["id"]) }
      find("fieldset.options").find(".option-text", text: plain["text"], exact_text: true).click
    when "ordering" then order_rows(key.reverse.map { |id| stored_text(display, id) })
    when "matching"
      rights = display["left"].map { |l| key[l["id"]] }
      pair_rows { |left_id| stored_text(display, rights[(display["left"].index { |l| l["id"] == left_id } + 1) % rights.size]) }
    when "normalized_text" then find("input[type=text][lang]").set("xyz")
    when "expression"
      type_in_math_field("x")
    end
  end

  # The field keeps what an earlier try left in it: empty it, then type with real keys.
  def type_in_math_field(*keys)
    page.execute_script("const field = document.querySelector('math-field'); field.value = ''; field.focus()")
    wait_until { page.evaluate_script("document.activeElement && document.activeElement.tagName") == "MATH-FIELD" }
    type_keys(*keys)
  end

  # An answer is used once: an entry taken by another row is greyed out, so the rows are emptied before they are filled again.
  def pair_rows
    display = display_of(served)
    all(".match-row select").each { |select| select.find("option[value='']").select_option }
    all(".match-row").each do |row|
      left_id = display["left"].find { |l| l["text"] == row.find("label").text }["id"]
      row.find("select").select(yield(left_id))
    end
  end

  def order_rows(texts)
    texts.each_with_index do |text, target|
      loop do
        shown = all("ol.ordering .row-text").map(&:text)
        position = shown.index(text)
        break if position <= target

        all("ol.ordering li")[position].click_button("Su")
      end
    end
  end

  # ---- the flows ----------------------------------------------------------------------------------------

  # serve -> wrong -> «Controlla» -> hint offered -> «Mostra un aiuto» -> right -> solution -> next, on one skill of each kind.
  def walk_each_kind
    KINDS.each do |kind|
      serve = open_practice(kind)
      assert_equal kind, kind_of_serve(serve)
      assert_selector "#hint-button", text: "Mostra un aiuto (1 di 3)"
      assert_selector "#solution-button", text: "Mostrami la soluzione"
      answer_wrong(serve)
      click_button "Controlla"
      assert_selector "#feedback", text: UNRECOGNISED
      assert_selector "#hints li", count: 1
      assert_selector "#hints li", text: HINTS[0]
      assert_selector "#hint-button", text: "Mostra un aiuto (2 di 3)"
      assert_no_selector "#next-actions button", visible: :visible
      assert_equal [ 1, "wrong" ], [ serve.attempts.count, serve.attempts.first.gradings.first.verdict ]
      click_button "Mostra un aiuto (2 di 3)"
      assert_selector "#hints li", count: 2
      assert_selector "#hints li", text: HINTS[1]
      assert_no_text HINTS[2]
      assert_selector "#hint-button", text: "Mostra un aiuto (3 di 3)"
      assert_equal 2, serve.events.where(kind: "hint_shown").count
      assert_selector "#check:not([disabled])"
      answer_right(serve)
      click_button "Controlla"
      begin
        assert_selector "#feedback", text: "Corretto, con un aiuto."
      rescue Minitest::Assertion => e
        raise e.class, "the right #{kind} answer #{key_of(serve).inspect} was sent as #{serve.reload.attempts.order(:try_number).last&.raw.inspect}: #{e.message}"
      end
      assert_selector "#solution h2", text: "Soluzione"
      assert_selector "#solution li", text: "Si fa il conto."
      assert_selector "#next-actions button", text: "Un altro esercizio"
      assert_selector "#next-actions a", text: "Torna all'argomento"
      assert_no_selector "#check", visible: :visible
      assert_equal [ "correct", true ], [ serve.reload.attempts.order(:try_number).last.gradings.first.verdict, serve.attempts.order(:try_number).last.aided ]
      click_button "Un altro esercizio"
      fresh = next_serve_after(serve)
      assert_not_equal serve.id, fresh.id
      assert_no_selector "#solution h2"
      assert_selector "#hints li", count: 0
      assert_clean "the #{kind} exercise"
    end
  end

  # serve -> «Mostrami la soluzione» at once -> the solution and the way on; the next exercise is the similar one.
  def walk_solution
    serve = open_practice("number")
    click_button "Mostrami la soluzione"
    assert_selector "#solution h2", text: "Soluzione"
    assert_selector "#solution li", text: "Si fa il conto."
    assert_selector "#next-actions button", text: "Prova un esercizio simile"
    assert_selector "#next-actions a", text: "Torna all'argomento"
    assert_no_selector "#check", visible: :visible
    assert_equal [ "solution_shown" ], serve.events.pluck(:kind)
    assert_equal "requested", JSON.parse(serve.events.first.payload_json)["reason"]
    assert_equal 0, serve.attempts.count
    click_button "Prova un esercizio simile"
    fresh = next_serve_after(serve)
    assert_equal [ "after_solution", serve.id ], [ fresh.reason, fresh.parent_serve_id ]
    assert_selector "#serve-reason", text: "Prova un esercizio simile"
    assert_clean "the solution"
  end

  # A typical error closes the exercise at once; the solution is then asked from the buttons that come with it.
  def walk_typical_error_then_solution
    serve = open_practice("number")
    find("input[inputmode=decimal]").set(errors_of(serve).first["value"])
    click_button "Controlla"
    assert_selector "#feedback", text: "Hai sbagliato un segno."
    assert_selector "#next-actions button", text: "Prova questo"
    assert_selector "#next-actions button", text: "Mostrami la soluzione"
    assert_no_selector "#solution h2"
    within("#next-actions") { click_button "Mostrami la soluzione" }
    assert_selector "#solution h2", text: "Soluzione"
    assert_selector "#solution li", text: "Si fa il conto."
    assert_selector "#next-actions button", text: "Prova un esercizio simile"
    assert_equal [ "solution_shown" ], serve.events.pluck(:kind)
    assert_equal "after_wrong", JSON.parse(serve.events.first.payload_json)["reason"]
    assert_clean "the solution after a typical error"
  end

  def walk_empty_answer
    open_practice("number")
    click_button "Controlla"
    assert_selector "#feedback", text: "Scrivi prima una risposta."
    assert_equal 0, PracticeAttempt.count
    open_practice("matching")
    all(".match-row").first.find("select").all("option").find { |o| o.value.present? }.select_option
    click_button "Controlla"
    assert_selector "#feedback", text: MISSING_ROW
    assert_selector "[aria-invalid='true']"
    assert_equal 0, PracticeAttempt.count
    assert_clean "the empty answers"
  end

  # A matching with the first row left empty is refused with the sentence that says what is missing, and the empty row is marked.
  def walk_matching_missing_row
    serve = open_practice("matching")
    display = display_of(serve)
    key = key_of(serve)
    rows = all(".match-row")
    assert_operator rows.size, :>=, 2
    rows.drop(1).each do |row|
      left_id = display["left"].find { |l| l["text"] == row.find("label").text }["id"]
      row.find("select").select(stored_text(display, key[left_id]))
    end
    click_button "Controlla"
    assert_selector "#feedback", text: MISSING_ROW
    assert_selector "[aria-invalid='true']", count: 1
    first_row = all(".match-row").first
    assert first_row.matches_css?("[aria-invalid='true']") || first_row.has_css?("[aria-invalid='true']"), "the empty first row is marked"
    assert_equal 0, PracticeAttempt.count
    assert_clean "the matching with an empty row"
  end

  # ---- the list of exercises, «Salta», the half-typed answer (D-337) ------------------------------------

  def item_key_of(serve) = serve.item_instance.item_revision.item.key
  def entry_selector(key) = "#exercise-list .exercise-entry[data-item='#{key}']"
  def answer_box = find("input[inputmode=decimal]")
  def draft_of(serve) = PracticeDraft.where(practice_serve_id: serve.id).order(:id).last&.raw
  def no_sideways_scroll? = page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")

  # The list shows every status; «Salta» keeps the typed answer and the exercise open; the entry says «Lasciato a metà» or «Saltato»;
  # a click on an entry opens it with its answer back; the autosave is on the server and a reload resumes the exercise; a done
  # exercise is redone from «Rifai» on a new instance.
  def walk_navigation
    first = open_practice("number")
    first_key = item_key_of(first)
    assert_includes NUMBER_KEYS, first_key
    assert_selector "#exercise-list summary", text: "Esercizi"
    assert_selector "#exercise-list .exercise-list-count", text: "0 fatti su #{KINDS.size + 2}"
    assert_selector "#exercise-list .exercise-entry", count: KINDS.size + 2
    assert_selector "#exercise-list .exercise-group", count: KINDS.size
    assert_selector "#{entry_selector(first_key)} .exercise-link[aria-current]"
    assert_selector "#{entry_selector(first_key)} .exercise-status", text: "Adesso"
    (NUMBER_KEYS - [ first_key ]).each { |key| assert_selector "#{entry_selector(key)} .exercise-status", text: "Da fare" }
    assert_selector "#exercise-list button.exercise-link", count: 3
    assert_selector "#exercise-list a.exercise-link[href*='item=flow-fraction']"

    # «Salta» with an answer typed: saved, the exercise stays open, the next one comes
    answer_box.set("123")
    find("#skip-button").click
    second = next_serve_after(first)
    second_key = item_key_of(second)
    assert_includes NUMBER_KEYS - [ first_key ], second_key
    assert_selector "#{entry_selector(first_key)} .exercise-status", text: "Lasciato a metà"
    assert_selector "#{entry_selector(second_key)} .exercise-status", text: "Adesso"
    assert_equal "123", draft_of(first)
    assert_equal 0, first.attempts.count

    # «Salta» with nothing typed: «Saltato»
    find("#skip-button").click
    third = next_serve_after(second)
    third_key = item_key_of(third)
    assert_selector "#{entry_selector(second_key)} .exercise-status", text: "Saltato"
    assert_equal NUMBER_KEYS.sort, [ first_key, second_key, third_key ].sort

    # a click on an entry opens that exercise, its answer back
    find("#{entry_selector(first_key)} .exercise-link").click
    reopened = next_serve_after(third)
    assert_equal first.id, reopened.id
    wait_until { answer_box.value == "123" }
    assert_text "Ho ripreso quello che avevi scritto."
    assert_selector "#{entry_selector(third_key)} .exercise-status", text: "Saltato"

    # the autosave, then a reload resumes this exercise with the answer
    answer_box.set("456")
    wait_until(10) { draft_of(first) == "456" }
    visit current_url
    assert_selector "#check:not([disabled])", wait: 30
    assert_equal first.id, served.id
    wait_until { answer_box.value == "456" }
    assert_text "Ho ripreso quello che avevi scritto."

    # a right answer: «Fatto» and «Rifai», which opens a new instance of the same exercise
    answer_right(first)
    click_button "Controlla"
    assert_selector "#feedback", text: "Corretto."
    assert_selector "#{entry_selector(first_key)} .exercise-status", text: "Fatto"
    assert_selector "#{entry_selector(first_key)} .exercise-act", text: "Rifai"
    assert_selector "#exercise-list .exercise-list-count", text: "1 fatto su #{KINDS.size + 2}"
    find("#{entry_selector(first_key)} .exercise-link").click
    again = next_serve_after(first)
    assert_equal first_key, item_key_of(again)
    assert_not_equal first.item_instance_id, again.item_instance_id
    assert_selector "#{entry_selector(first_key)} .exercise-status", text: "Adesso"
    assert_clean "the list and «Salta»"
  end

  # An entry of another skill is a link: the draft of the exercise being left is saved, the page of that skill opens that exercise.
  def walk_other_skill
    serve = open_practice("number")
    answer_box.set("77")
    find("#exercise-list a.exercise-link[href*='item=flow-fraction']").click
    wait_until(15) { draft_of(serve) == "77" }
    wait_until(15) { page.current_path.end_with?("/practice/#{skill_of('fraction')}") }
    assert_selector "#check:not([disabled])", wait: 30
    assert page.current_path.start_with?(@base), "the link stays under #{@base.inspect}"
    fraction = served
    assert_equal "flow-fraction", item_key_of(fraction)
    assert_equal "fraction", kind_of_serve(fraction)
    assert_no_match(/item=/, page.current_url, "the address keeps no item after the first load")
    assert_selector "#{entry_selector('flow-fraction')} .exercise-status", text: "Adesso"
    assert_clean "the link to another skill"
  end

  # On a 390 px phone the list is a panel above the exercise, closed; it opens, nothing scrolls sideways, an entry opens its exercise.
  def walk_phone
    page.driver.resize(390, 844)
    serve = open_practice("number")
    assert_equal false, page.evaluate_script("document.querySelector('#exercise-list details').open")
    assert_selector "#exercise-list summary", text: "Esercizi"
    assert_selector "#exercise-list .exercise-list-count", text: "0 fatti su #{KINDS.size + 2}"
    assert no_sideways_scroll?, "no sideways scroll with the list closed"
    find("#exercise-list summary").click
    assert_selector "#exercise-list .exercise-entry", count: KINDS.size + 2
    assert no_sideways_scroll?, "no sideways scroll with the list open"
    other = (NUMBER_KEYS - [ item_key_of(serve) ]).first
    find("#{entry_selector(other)} .exercise-link").click
    fresh = next_serve_after(serve)
    assert_equal other, item_key_of(fresh)
    assert_equal false, page.evaluate_script("document.querySelector('#exercise-list details').open")
    assert no_sideways_scroll?, "no sideways scroll after an entry"
    assert_clean "the phone"
  end

  # The answer was written with no network: it waits in the outbox, the page is reloaded, the next page sends it and tells its verdict.
  def walk_outbox
    serve = open_practice("number")
    page.execute_script("window.__realFetch = window.fetch; window.fetch = function () { return Promise.reject(new TypeError('offline')) }")
    find("input[inputmode=decimal]").set(key_of(serve))
    click_button "Controlla"
    assert_selector "#feedback", text: "Non riesco a salvare ora. Riprovo da solo, non perdi la risposta."
    assert_equal 1, page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.poutbox.') === 0 }).length")
    assert_equal 0, serve.attempts.count
    visit current_url
    assert_selector "#check:not([disabled])", wait: 30
    assert_selector "#feedback", text: "La risposta di prima"
    assert_selector "#feedback", text: "Corretto."
    assert_equal [ "correct" ], serve.reload.attempts.map { |a| a.gradings.first.verdict }
    assert_equal [], page.evaluate_script("Object.keys(localStorage).filter(function (k) { return k.indexOf('banco.poutbox.') === 0 })")
    assert_not_equal serve.id, served.id, "the answered exercise is over, a new one is on the page"
    assert_clean "the outbox"
  end

  # ---- the tests ----------------------------------------------------------------------------------------

  test "a trial student: wrong, hint, right, next, on every kind of exercise" do
    build_flow_world
    as_student
    walk_each_kind
  end

  test "the teacher in the preview: wrong, hint, right, next, on every kind of exercise; it is all the preview student's" do
    build_flow_world
    as_teacher_in_preview
    walk_each_kind
    assert_equal [ acting_student.id ], PracticeServe.pluck(:student_id).uniq
    assert_equal "preview", acting_student.kind
  end

  test "a trial student: the solution on request" do
    build_flow_world
    as_student
    walk_solution
  end

  test "the teacher in the preview: the solution on request" do
    build_flow_world
    as_teacher_in_preview
    walk_solution
  end

  test "a trial student: after a typical error the solution is still asked for" do
    build_flow_world
    as_student
    walk_typical_error_then_solution
  end

  test "the teacher in the preview: after a typical error the solution is still asked for" do
    build_flow_world
    as_teacher_in_preview
    walk_typical_error_then_solution
  end

  test "a trial student: an empty or half-filled answer is told, not sent" do
    build_flow_world
    as_student
    walk_empty_answer
  end

  test "the teacher in the preview: an empty or half-filled answer is told, not sent" do
    build_flow_world
    as_teacher_in_preview
    walk_empty_answer
  end

  test "a trial student: an answer left in the outbox is sent and told by the next page" do
    build_flow_world
    as_student
    walk_outbox
  end

  test "the teacher in the preview: an answer left in the outbox is sent and told by the next page" do
    build_flow_world
    as_teacher_in_preview
    walk_outbox
  end

  test "a trial student: an empty row of a matching is told and marked" do
    build_flow_world
    as_student
    walk_matching_missing_row
  end

  test "the teacher in the preview: an empty row of a matching is told and marked" do
    build_flow_world
    as_teacher_in_preview
    walk_matching_missing_row
  end

  test "a trial student: the list shows the statuses, Salta keeps the answer, a reload resumes, an entry opens, Rifai redoes" do
    build_flow_world(number_items: 3)
    as_student
    walk_navigation
    assert_equal [ acting_student.id ], PracticeServe.pluck(:student_id).uniq
  end

  test "the teacher in the preview: the list shows the statuses, Salta keeps the answer, a reload resumes, an entry opens, Rifai redoes" do
    build_flow_world(number_items: 3)
    as_teacher_in_preview
    walk_navigation
    assert_equal [ acting_student.id ], PracticeServe.pluck(:student_id).uniq
    assert_equal "preview", acting_student.kind
  end

  test "a trial student: an entry of another skill saves the draft and opens that skill" do
    build_flow_world(number_items: 3)
    as_student
    walk_other_skill
  end

  test "the teacher in the preview: an entry of another skill stays in the preview" do
    build_flow_world(number_items: 3)
    as_teacher_in_preview
    walk_other_skill
  end

  test "a trial student on a 390 px phone: the list is a closed panel, no sideways scroll" do
    build_flow_world(number_items: 3)
    as_student
    walk_phone
  end

  test "the teacher in the preview on a 390 px phone: the list is a closed panel, no sideways scroll" do
    build_flow_world(number_items: 3)
    as_teacher_in_preview
    walk_phone
  end

  test "the teacher in the preview with the drafts: wrong, hint, right, solution" do
    build_flow_world(approve: false, release: false)
    as_teacher_in_preview
    visit PREVIEW
    click_button "Passa a: Con le bozze"
    assert_selector "#preview-view-name", text: "Vista: Con le bozze"
    walk_each_kind
    walk_solution
  end
end
