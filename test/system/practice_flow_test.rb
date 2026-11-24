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
# D-402: a bilingual exercise (target text with its authored Italian, the golden test/fixtures/lang/served_item.json) is drawn with «Traduzione» in the action bar;
# the practice endpoints are answered by the page's own stand-in (BILINGUAL_MOCK) so that this half of the walk does not depend on the serving side.
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
  UNRECOGNISED = "Non è ancora giusta. Leggi l'aiuto e riprova.".freeze
  # The skill with a sentence around a blank (D-339): the key «never eat» goes in the place of ___.
  SENTENCE_STEM = "Negativa: My parents ___ meat.".freeze
  SENTENCE_KEY = "never eat".freeze
  CONTESTED = "Ho mandato la tua risposta al docente. Intanto ecco la soluzione: confrontala con la tua.".freeze
  SAME_ANSWER = "È la stessa risposta di prima: cambiala, oppure chiedi un aiuto.".freeze
  CONTEST_NOTE = "Pensi di avere ragione? Premi «Per me va bene così»: l'esercizio si chiude e lo guarda il docente.".freeze

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

  # The practice endpoints of a bilingual exercise, answered inside the page (fetch is replaced before the page's own script runs). The shapes are the golden
  # served fixture's (test/fixtures/lang/served_item.json): `part`, `hint`, `feedback`, `reminder`, `solution`. FIXTURE and EXTRA are JSON text.
  BILINGUAL_MOCK = <<~JS.freeze
    (() => {
      const real = window.fetch.bind(window);
      const fx = %<fixture>s;
      const extra = %<extra>s;
      const kind = extra.kind;
      const posts = window.__trPosts = [];
      const json = (body, status = 200) => Promise.resolve(new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } }));
      const served = fx[kind];
      let tries = 0;
      window.fetch = (url, init = {}) => {
        const path = new URL(url, location.href).pathname;
        if (path === "/translations") { posts.push(JSON.parse(init.body)); return Promise.resolve(new Response(null, { status: 204 })); }
        if (!/\\/practice\\//.test(path)) return real(url, init);
        if (/\\/practice\\/serves$/.test(path)) {
          return json({ type: "item", serve_id: 9001, next_try_number: 1, actions: [], rating: null, exercise: { item: "flow-bilingual" }, item: extra.part || served.part,
                        skill: { state: "in_study", state_it: "In studio", why_it: "Ne servono tre giuste.", missing_it: null, clean: 0 },
                        hints: { total: 3, shown: [] }, draft: null, reason_it: null, ...served.reminder });
        }
        if (/\\/practice\\/answers$/.test(path)) {
          tries += 1;
          return json({ status: "graded", outcome: "typical_error", try_number: tries, ...served.feedback, actions: ["retry", "show_solution"], hint: null });
        }
        if (/\\/hint$/.test(path)) return json({ ...served.hint });
        if (/\\/solution$/.test(path)) return json({ solution: { ...served.solution, ...(extra.solution || {}) }, actions: ["next", "back"] });
        if (/\\/draft$/.test(path)) return json({ status: "saved" });
        if (/\\/practice\\/exercises/.test(path)) return json({ skills: [], done: false, known: false });
        return real(url, init);
      };
    })();
  JS
  PASSAGE_EN = "Tom has a dog. The dog is brown.".freeze
  PASSAGE_IT = "Tom ha un cane. Il cane è marrone.".freeze

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

  def build_flow_world(approve: true, release: true, number_items: 1, sentence: false)
    build_course
    kinds = sentence ? KINDS + [ "sentence" ] : KINDS
    skills = kinds.map { |kind| skill_of(kind) }
    @course = build_course_map(skills: [], topics: [ { key: TOPIC, kind: "ripasso", title_it: TOPIC_TITLE, skills: skills, minutes: 30, term: 1, after: [] } ])
    @lesson = Lesson.create!(subject: @subject, key: TOPIC, kind: "ripasso")
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 1, source_md: "---\n", source_sha256: "0" * 64, rules_version: Validation::Rules.version.to_s,
                                              warnings_json: "[]", body_json: JSON.generate(lesson_body.merge(skills: skills)))
    revisions = kinds.to_h { |kind| [ kind, [ make_flow_item(kind) ] ] }
    (2..number_items).each { |n| revisions["number"] << make_flow_item("number", n) }
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 1, course_revision: @course, lesson_revision: @lesson_revision,
                                            body_json: JSON.generate(schema: "banco.topic/1", key: TOPIC, intro_it: "Qui impari a risolvere le equazioni.",
                                                                     practice: kinds.map { |kind| { skill: skill_of(kind), items: revisions[kind].map { |r| { item: r.item.key, revision: r.id } } } }))
    @official = practice_student("student")
    @trial = practice_student("prova-1")
    approve_topic!(@topic_revision) if approve
    release_course!(@course) if release
  end

  def make_flow_item(kind, n = 1)
    item = Item.create!(subject: @subject, key: n == 1 ? "flow-#{kind.tr('_', '-')}" : "flow-#{kind.tr('_', '-')}-#{n}", kind: "practice_item")
    component = kind == "sentence" ? "normalized_text" : kind
    stem = kind == "sentence" ? SENTENCE_STEM : ui_stem(kind)
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "math", skill: skill_of(kind), component: component, level: 1, expected_seconds: 60,
             prompt: { stem_it: stem }, hints_it: HINTS,
             error_catalogue: [ { code: "adds_wrong", message_it: "Hai sbagliato un segno." }, { code: "odd_pick", message_it: "Hai scelto un numero dispari." } ] }
    body[:form] = [ "lowest_terms" ] if kind == "fraction"
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    6.times do |i|
      spec = kind == "sentence" ? sentence_spec : ui_instance_spec(kind, i)
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: spec[:display].to_json, answer_json: spec[:answer].to_json, errors_json: spec[:errors].to_json,
                           hints_json: JSON.generate(HINTS), solution_json: spec[:solution].to_json, fingerprint: Digest::SHA256.hexdigest("flow-#{kind}-#{n}-#{i}"))
    end
    revision
  end

  # An instance whose stem holds the frame: the answer is the words in the place of ___.
  def sentence_spec
    { display: { stem_it: SENTENCE_STEM }, answer: SENTENCE_KEY, errors: [], solution: { steps: [ { text_it: "Si fa il conto." } ], final: "My parents never eat meat." } }
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

  # ---- a bilingual exercise (D-402) ---------------------------------------------------------------------

  def bilingual_fixture = File.read(Rails.root.join("test/fixtures/lang/served_item.json"))

  # Opens the practice page of the number skill with the stand-in endpoints for `kind` ("choice" or "blank" of the golden fixture); `part` and `solution` replace
  # what the fixture serves (a testlet with a passage). The stand-in goes in before the page's own script and goes out again when the block ends.
  def with_bilingual_page(kind, part: nil, solution: nil)
    build_flow_world
    as_student
    extra = { kind: kind, part: part, solution: solution }.compact
    source = format(BILINGUAL_MOCK, fixture: bilingual_fixture, extra: JSON.generate(extra))
    id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: source)["identifier"]
    page.driver.resize(390, 844)
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector "#check:not([disabled])", wait: 30
    yield
  ensure
    begin
      page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: id) if id
    rescue StandardError
      nil
    end
  end

  def assert_no_sideways_scroll
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth + 1"), "the page scrolls sideways on a 390 px phone"
  end

  # the target text, «Traduzione» next to «Controlla» and no Italian until it is asked; then the Italian under every text, the hint and the verdict joining it
  def walk_bilingual_choice
    with_bilingual_page("choice") do
      assert_selector ".prompt", text: "Choose the two words for the gaps"
      assert_selector ".instance-stem", text: "On Saturdays I ___ my bed"
      assert_selector "fieldset.options .option-text", count: 4
      assert_selector ".reminder", text: "Look at the nouns again."
      assert_selector "#translation-button", text: "Traduzione", count: 1
      assert_equal "false", find("#translation-button")["aria-pressed"]
      assert_equal %w[check translation-button], all("[data-practice-target=controls] > button").first(2).map { |b| b[:id] }, "«Traduzione» sits next to «Controlla»"
      assert_no_selector ".tr"
      assert_no_text "Scegli le due parole"
      assert_no_text "Il sabato io"
      assert_no_selector ".option .tr-toggle"
      assert_no_sideways_scroll
      # open: the Italian of the instruction, the sentence, each option, the steps and the format
      find("#translation-button").click
      assert_equal "true", find("#translation-button")["aria-pressed"]
      assert_selector ".prompt .tr", text: "Scegli le due parole che completano la frase"
      assert_selector ".instance-stem .tr", text: "Il sabato io ___ il letto"
      assert_selector "label.option .tr", text: "fare / fare", count: 4
      assert_selector ".do-steps .tr", text: "Leggi tutta la frase."
      assert_selector ".answer-format + .tr", text: "Ogni opzione ha due parti"
      assert_selector ".reminder .tr", text: "Guarda di nuovo i nomi."
      assert_equal "it", find(".prompt .tr", match: :first)["lang"]
      assert_no_sideways_scroll
      # a hint that arrives later joins the open scope
      click_button "Mostra un aiuto (1 di 3)"
      assert_selector "#hints li", text: "Some verbs go with fixed nouns"
      assert_selector "#hints li .tr", text: "Alcuni verbi stanno con nomi fissi"
      # closing hides every line, the later ones too
      find("#translation-button").click
      assert_no_selector ".tr"
      assert_equal "false", find("#translation-button")["aria-pressed"]
      # a wrong try: the catalogue message is a pair, and the verdict joins the scope when it is open again
      find("fieldset.options").find(".option-text", text: "do / do", exact_text: true).click
      click_button "Controlla"
      assert_selector "#feedback .feedback-text[lang=en]", text: "Look at the nouns again. Which verb is the partner of each one?"
      assert_no_selector "#feedback .tr"
      find("#translation-button").click
      assert_selector "#feedback .tr", text: "Guarda di nuovo i nomi. Quale verbo è il compagno di ciascuno?"
      # the solution: steps and final with their Italian; the button goes on after the exercise is over
      click_button "Mostrami la soluzione"
      assert_selector "#solution li", text: "We say «make the bed»."
      assert_selector "#solution li .tr", text: "Si dice «make the bed»."
      assert_selector "#solution .tr", text: "make / do: il sabato rifaccio il letto e faccio la spesa."
      assert_selector "#next-actions #translation-button", text: "Traduzione"
      assert_no_selector "#check", visible: :visible
      find("#next-actions #translation-button").click
      assert_no_selector ".tr"
      assert_equal [ { "surface" => "practice", "scope" => "item", "topic" => TOPIC, "serve_id" => 9001 } ], page.evaluate_script("window.__trPosts").first(1).map { |b| b.slice("surface", "scope", "topic", "serve_id") }
      assert_no_sideways_scroll
      assert_clean "the bilingual exercise"
    end
  end

  # the form-material rule: the sentence, the forms and the final are target-only (no `_it`); «Traduzione» is still there and opens the instruction's Italian,
  # the steps' and the solution steps', and no line appears under the material
  def walk_bilingual_form_material
    served = JSON.parse(File.read(Rails.root.join("test/fixtures/lang/served_item_form.json")))["choice"]
    # the stand-in merges the solution over the golden one, which has a final_it: this one has none
    with_bilingual_page("choice", part: served["part"], solution: served["solution"].merge("final_it" => nil)) do
      assert_selector ".instance-stem", text: "My brother ___ thirteen."
      assert_selector "fieldset.options .option-text", count: 3
      assert_selector "#translation-button", text: "Traduzione", count: 1
      assert_no_selector ".tr"
      find("#translation-button").click
      assert_equal "true", find("#translation-button")["aria-pressed"]
      assert_selector ".prompt .tr", text: "Scegli la forma che completa la frase."
      assert_selector ".do-steps .tr", count: 3
      assert_selector ".answer-format + .tr", text: "Scegli una parola per lo spazio."
      assert_no_selector ".instance-stem .tr"
      assert_no_selector "label.option .tr"
      assert_no_selector ".option .tr-toggle"
      assert_no_text "Mio fratello ___ tredici"
      assert_no_sideways_scroll
      click_button "Mostrami la soluzione"
      assert_selector "#solution li .tr", text: "Mio fratello è una persona"
      assert_selector "#solution", text: "is"
      assert_equal 1, all("#solution .tr").size, "the final has no translation line"
      assert_clean "the form-material exercise"
    end
  end

  # the reading rule: the passage's Italian is not on the page before the answer, and comes with the solution
  def walk_bilingual_passage
    part = { component: "testlet", lang: "en", passage_en: PASSAGE_EN,
             sub_items: [ { id: "s1", component: "choice", stem_en: "Who has a dog?", stem_it: "Chi ha un cane?", options: [ { id: "a", text: "Tom", text_it: "Tom" }, { id: "b", text: "Amy", text_it: "Amy" } ] } ] }
    with_bilingual_page("choice", part: part, solution: { passage_it: PASSAGE_IT }) do
      assert_selector ".passage[lang=en]", text: PASSAGE_EN
      assert_no_selector ".passage .tr", visible: :all
      find("#translation-button").click
      assert_selector ".sub-item .prompt .tr", text: "Chi ha un cane?"
      assert_no_text "Tom ha un cane"
      assert_not_includes page.html, "Tom ha un cane", "the passage's Italian is not in the page before the answer"
      click_button "Mostrami la soluzione"
      assert_selector "#solution h2"
      assert_selector ".passage .tr", text: PASSAGE_IT
      assert_equal "it", find(".passage .tr")["lang"]
      find("#next-actions #translation-button").click
      assert_no_selector ".passage .tr"
      find("#next-actions #translation-button").click
      assert_selector ".passage .tr", text: PASSAGE_IT
      assert_no_sideways_scroll
      assert_clean "the bilingual passage"
    end
  end

  # a legacy exercise is drawn as before: no scope, no button
  def walk_legacy_has_no_translation
    open_practice("choice")
    assert_no_selector "#translation-button", visible: :all
    assert_no_selector "[data-tr-scope]", visible: :all
    assert_no_selector ".tr", visible: :all
    assert_clean "the legacy exercise"
  end


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
    assert_selector "#serve-reason", text: "Ti propongo un esercizio simile: per passare al prossimo ne serve uno giusto." # the same item again (D-348)
    # D-379: the line says why this one was served; a wrong try leaves it while he tries again, the right try that ends the exercise takes it away
    answer_wrong(fresh)
    click_button "Controlla"
    assert_selector "#feedback", text: UNRECOGNISED
    assert_selector "#serve-reason", text: "Ti propongo un esercizio simile"
    answer_right(fresh)
    click_button "Controlla"
    assert_selector "#feedback", text: "Corretto, con un aiuto."
    assert_no_selector "#serve-reason", visible: :visible
    assert_selector "#next-actions button", text: "Un altro esercizio"
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

  # The list shows every status; «Salta» keeps the typed answer and the exercise open; the entry says «Da finire» or, for one he only opened, «Aperto» (D-384);
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
    assert_selector "#{entry_selector(first_key)} .exercise-status", text: "Da finire"
    assert_selector "#{entry_selector(second_key)} .exercise-status", text: "Adesso"
    assert_equal "123", draft_of(first)
    assert_equal 0, first.attempts.count

    # «Salta» with nothing typed: the exercise was only opened, «Aperto» (not «Saltato»)
    find("#skip-button").click
    third = next_serve_after(second)
    third_key = item_key_of(third)
    assert_selector "#{entry_selector(second_key)} .exercise-status", text: "Aperto"
    assert_equal NUMBER_KEYS.sort, [ first_key, second_key, third_key ].sort

    # a click on an entry opens that exercise, its answer back
    find("#{entry_selector(first_key)} .exercise-link").click
    reopened = next_serve_after(third)
    assert_equal first.id, reopened.id
    wait_until { answer_box.value == "123" }
    assert_text "Ho ripreso quello che avevi scritto."
    assert_selector "#{entry_selector(third_key)} .exercise-status", text: "Aperto"

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

  # ---- «Per me va bene così», the same answer, a whole sentence, «Ci sei quasi» (D-339) ---------------------

  def sentence_box = find("input[type=text][lang]")
  def tries_of(serve) = serve.attempts.order(:try_number)

  def type_and_check(text)
    sentence_box.set(text)
    click_button "Controlla"
  end

  # The line under the message is smaller than the message; the button is there.
  def assert_contest_offered
    assert_selector "#feedback .contest-note", text: CONTEST_NOTE
    assert_selector "#feedback #contest-button", text: "Per me va bene così"
    sizes = page.evaluate_script("[document.querySelector('#feedback .feedback-text'), document.querySelector('#feedback .contest-note')].map(function (e) { return parseFloat(getComputedStyle(e).fontSize) })")
    assert_operator sizes[1], :<, sizes[0], "the contest line is smaller than the message"
  end

  def assert_contest_written(serve, raw)
    contests = PracticeContest.where(practice_serve_id: serve.id)
    assert_equal 1, contests.count
    assert_equal acting_student.id, contests.first.student_id
    assert_equal 0, Comment.count, "«Per me va bene così» writes no comment (D-400)"
    return if @base == PREVIEW

    visit "/comments"
    assert_no_selector ".cm-row"
  end

  # A wrong typed answer offers «Per me va bene così»; the click writes the contest, shows the solution and the message, closes the exercise.
  def walk_contest
    serve = open_practice("sentence")
    type_and_check("xyz")
    assert_selector "#feedback", text: UNRECOGNISED
    assert_contest_offered
    assert_selector "#hint-button", text: "Mostra un aiuto (2 di 3)"
    assert_equal 0, PracticeContest.count
    find("#contest-button").click
    assert_selector "#feedback", text: CONTESTED
    assert_selector "#solution h2", text: "Soluzione"
    assert_selector "#solution li", text: "Si fa il conto."
    assert_selector "#next-actions button", text: "Un altro esercizio"
    assert_selector "#next-actions a", text: "Torna all'argomento"
    assert_no_selector "#contest-button"
    assert_no_selector "#check", visible: :visible
    assert_equal [ "xyz" ], tries_of(serve).map(&:raw)
    assert_contest_written(serve, "xyz")
    assert_clean "the contest"
  end

  # After the second wrong try the exercise is closed with its solution, and the contest is still offered on the latest answer.
  def walk_contest_after_second_try
    serve = open_practice("sentence")
    type_and_check("xyz")
    assert_contest_offered
    sentence_box.set("abc")
    assert_selector "#check:not([disabled])"
    click_button "Controlla"
    assert_selector "#next-actions button", text: "Prova un esercizio simile"
    assert_selector "#solution h2", text: "Soluzione"
    assert_contest_offered
    assert_equal 2, serve.attempts.count
    find("#contest-button").click
    assert_selector "#feedback", text: CONTESTED
    assert_no_selector "#contest-button"
    assert_selector "#next-actions button", text: "Un altro esercizio"
    assert_contest_written(serve, "abc")
    assert_clean "the contest after the second try"
  end

  # D-395: a resumed exercise offers «Per me va bene così» again when the server allows it: after a reload, and after «Salta» and back from the list.
  def walk_contest_resumed
    first = open_practice("number")
    first_key = item_key_of(first)
    answer_wrong(first)
    click_button "Controlla"
    assert_selector "#feedback", text: UNRECOGNISED
    assert_contest_offered

    visit current_url
    assert_selector "#check:not([disabled])", wait: 30
    assert_equal first.id, served.id
    assert_selector "#feedback .contest-note", text: CONTEST_NOTE
    assert_selector "#feedback #contest-button", text: "Per me va bene così"

    find("#skip-button").click
    second = next_serve_after(first)
    assert_no_selector "#contest-button" # the other exercise has no try: nothing to send
    find("#exercise-list details.exercise-done summary").click
    find("#{entry_selector(first_key)} .exercise-link").click
    assert_equal first.id, next_serve_after(second).id
    assert_selector "#feedback .contest-note", text: CONTEST_NOTE
    assert_selector "#feedback #contest-button", text: "Per me va bene così"

    find("#contest-button").click
    assert_selector "#feedback", text: CONTESTED
    assert_no_selector "#contest-button"
    assert_selector "#solution h2", text: "Soluzione"
    assert_equal 1, PracticeContest.where(practice_serve_id: first.id).count
    assert_clean "the contest on a resumed exercise"
  end

  # D-395: the answer the outbox sends at the next page load is told above the exercise, and the button is there with it.
  def walk_contest_after_outbox
    serve = open_practice("number")
    page.execute_script("window.__realFetch = window.fetch; window.fetch = function () { return Promise.reject(new TypeError('offline')) }")
    answer_wrong(serve)
    click_button "Controlla"
    assert_selector "#feedback", text: "Non riesco a salvare ora. Riprovo da solo, non perdi la risposta."
    assert_equal 0, serve.attempts.count
    visit current_url
    assert_selector "#check:not([disabled])", wait: 30
    assert_equal serve.id, served.id
    assert_selector "#feedback", text: "La risposta di prima"
    assert_selector "#feedback", text: UNRECOGNISED
    assert_selector "#feedback .contest-note", text: CONTEST_NOTE
    assert_selector "#feedback #contest-button", text: "Per me va bene così"
    assert_equal 1, serve.reload.attempts.count
    find("#contest-button").click
    assert_selector "#feedback", text: CONTESTED
    assert_equal 1, PracticeContest.where(practice_serve_id: serve.id).count
    assert_clean "the contest after the outbox"
  end

  # D-395: «Mostrami la soluzione» on an open exercise with a try that is not right: the button is offered again with the solution; the tap sends it,
  # and the solution is not sent twice.
  def walk_contest_after_solution
    serve = open_practice("sentence")
    type_and_check("xyz")
    assert_contest_offered
    find("#solution-button").click
    assert_selector "#solution h2", text: "Soluzione"
    assert_selector "#next-actions button", text: "Prova un esercizio simile"
    assert_selector "#feedback .contest-note", text: CONTEST_NOTE
    assert_selector "#feedback #contest-button", text: "Per me va bene così"
    assert_equal [ "requested" ], serve.events.where(kind: "solution_shown").map { |e| JSON.parse(e.payload_json)["reason"] }
    assert_equal 0, PracticeContest.count

    find("#contest-button").click
    assert_selector "#feedback", text: CONTESTED
    assert_no_selector "#contest-button"
    assert_selector "#solution h2", text: "Soluzione"
    assert_selector "#next-actions button", text: "Un altro esercizio"
    assert_equal [ "requested" ], serve.events.reload.where(kind: "solution_shown").map { |e| JSON.parse(e.payload_json)["reason"] }
    assert_contest_written(serve, "xyz")
    assert_clean "the contest after the solution"
  end

  # The same answer twice is refused (D-353) and is not a try, in the page and not as a verdict; the contest stays offered; going on to another exercise takes it away.
  def walk_same_answer
    serve = open_practice("sentence")
    type_and_check("xyz")
    assert_contest_offered
    assert_selector "#check:not([disabled])"
    click_button "Controlla"
    assert_selector "#feedback", text: SAME_ANSWER
    assert_equal 1, serve.attempts.count, "the same answer is not a second try"
    assert_selector "#feedback #contest-button"
    assert_selector "#check:not([disabled])", wait: 30
    sentence_box.set("xyz  ")
    click_button "Controlla"
    assert_selector "#feedback", text: SAME_ANSWER
    assert_equal 1, serve.attempts.count
    assert_equal 0, page.evaluate_script("Object.keys(localStorage).filter((k) => k.startsWith('banco.poutbox.')).length"), "the outbox let the refused answer go"
    assert_selector "#check:not([disabled])", wait: 30
    # The skill has one exercise: «Salta» gives that same open serve back, with its try, so the server's actions still offer the contest (D-395)
    find("#skip-button").click
    assert_selector "#check:not([disabled])", wait: 30
    assert_equal serve.id, served.id
    assert_selector "#feedback #contest-button"
    # going on to an exercise with no try takes it away: the button follows only the actions of the serve on the screen
    find("#exercise-list a.exercise-link[href*='item=flow-fraction']").click
    wait_until(15) { page.current_path.end_with?("/practice/#{skill_of('fraction')}") }
    assert_selector "#check:not([disabled])", wait: 30
    assert_not_equal serve.id, served.id
    assert_no_selector "#contest-button"
    assert_no_text CONTEST_NOTE
    assert_equal 0, PracticeContest.count
    assert_clean "the same answer"
  end

  # A whole sentence around the blank is right, with a note; a typo is «Ci sei quasi» and offers the contest too (D-389).
  def walk_sentence_and_typo
    serve = open_practice("sentence")
    assert_selector "[data-practice-target=itemBox]", text: "My parents ___ meat."
    type_and_check("My parents never eat meat.")
    assert_selector "#feedback", text: "Bastava scrivere solo le parole che mancano: never eat."
    assert_selector "#solution h2", text: "Soluzione"
    assert_selector "#next-actions button", text: "Un altro esercizio"
    assert_no_selector "#contest-button"
    assert_equal [ "correct" ], serve.reload.attempts.map { |a| a.gradings.first.verdict }
    assert_equal "My parents never eat meat.", serve.attempts.first.raw
    click_button "Un altro esercizio"
    fresh = next_serve_after(serve)
    type_and_check("nevar eat")
    assert_selector "#feedback", text: "Ci sei quasi: controlla come l'hai scritta, forse c'è un errore di battitura."
    assert_selector "#feedback #contest-button", text: "Per me va bene così" # D-389: a near miss may be sent to the teacher too
    assert_equal [ "wrong" ], fresh.attempts.map { |a| a.gradings.first.verdict }
    assert_selector "#check:not([disabled])"
    sentence_box.set(SENTENCE_KEY)
    click_button "Controlla"
    assert_selector "#feedback", text: "Corretto"
    assert_equal 2, fresh.attempts.count
    assert_clean "the sentence and the typo"
  end

  # The entries of the number skill that come first, before «Già fatti».
  def number_front = "#exercise-list .exercise-group > ol.exercise-entries > .exercise-entry[data-skill='#{skill_of('number')}']"

  # An exercise answered once and left with «Salta» is «Finito» (D-353): it goes into the closed «Già fatti (1)» at the end of the list, still clickable;
  # the ones still to do stay first.
  def walk_retry_status
    first = open_practice("number")
    first_key = item_key_of(first)
    answer_wrong(first)
    click_button "Controlla"
    assert_selector "#feedback", text: UNRECOGNISED
    find("#skip-button").click
    next_serve_after(first)
    assert_selector "#exercise-list details.exercise-done summary", text: "Già fatti (1)"
    assert_selector "#{number_front}", count: 2
    assert_no_selector "#exercise-list .exercise-group > ol.exercise-entries > .exercise-entry[data-item='#{first_key}']"
    find("#exercise-list details.exercise-done summary").click
    assert_selector "#{entry_selector(first_key)} .exercise-status", text: "Finito"
    assert_selector "#{entry_selector(first_key)} .exercise-act", text: "Rifai"
    assert_clean "the retry status"
  end

  # «Già fatti (N)»: a right answer, then another exercise: the done one leaves the front of the list into a closed group at the end, still
  # clickable; the exercises to do stay first, in order; the exercise open on the page is never in the group.
  def walk_done_group
    first = open_practice("number")
    first_key = item_key_of(first)
    assert_no_selector "#exercise-list details.exercise-done"
    answer_right(first)
    click_button "Controlla"
    assert_selector "#feedback", text: "Corretto."
    assert_selector "#exercise-list .exercise-group > ol.exercise-entries > .exercise-entry[data-item='#{first_key}']", text: "Fatto"
    assert_no_selector "#exercise-list details.exercise-done", text: "Già fatti"
    other = (NUMBER_KEYS - [ first_key ]).first
    find("#{entry_selector(other)} .exercise-link").click
    next_serve_after(first)
    assert_selector "#exercise-list details.exercise-done summary", text: "Già fatti (1)"
    assert_equal false, page.evaluate_script("document.querySelector('#exercise-list details.exercise-done').open")
    assert_no_selector "#{entry_selector(first_key)}", visible: :visible
    assert_equal (NUMBER_KEYS - [ first_key ]).sort, page.all(number_front, minimum: 2).map { |li| li["data-item"] }.sort
    assert_selector "#exercise-list .exercise-list-count", text: "1 fatto su #{KINDS.size + 2}"
    find("#exercise-list details.exercise-done summary").click
    assert_selector "#{entry_selector(first_key)} .exercise-status", text: "Fatto"
    assert_selector "#{entry_selector(first_key)} .exercise-act", text: "Rifai"
    find("#{entry_selector(first_key)} .exercise-link").click
    again = next_serve_after(first)
    assert_equal first_key, item_key_of(again)
    assert_no_selector "#exercise-list details.exercise-done", text: "Già fatti"
    assert_selector "#exercise-list .exercise-group > ol.exercise-entries > .exercise-entry[data-item='#{first_key}']", text: "Adesso"
    assert_clean "the done group"
  end

  def walk_contest_phone
    page.driver.resize(390, 844)
    open_practice("sentence")
    type_and_check("xyz")
    assert_contest_offered
    assert no_sideways_scroll?, "no sideways scroll with the contest offered"
    find("#contest-button").click
    assert_selector "#feedback", text: CONTESTED
    assert no_sideways_scroll?, "no sideways scroll after the contest"
    assert_clean "the contest on a phone"
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

  test "a trial student: a wrong answer offers «Per me va bene così» and the click sends it to the teacher" do
    build_flow_world(sentence: true)
    as_student
    walk_contest
  end

  test "the teacher in the preview: «Per me va bene così» writes the contest and no comment" do
    build_flow_world(sentence: true)
    as_teacher_in_preview
    walk_contest
    assert_equal "preview", acting_student.kind
  end

  test "a trial student: after the second wrong try «Per me va bene così» is still offered" do
    build_flow_world(sentence: true)
    as_student
    walk_contest_after_second_try
  end

  test "the teacher in the preview: after the second wrong try «Per me va bene così» is still offered" do
    build_flow_world(sentence: true)
    as_teacher_in_preview
    walk_contest_after_second_try
  end

  test "a trial student: a resumed exercise (reload, «Salta» and back) offers «Per me va bene così» again" do
    build_flow_world(number_items: 3)
    as_student
    walk_contest_resumed
  end

  test "the teacher in the preview: a resumed exercise (reload, «Salta» and back) offers «Per me va bene così» again" do
    build_flow_world(number_items: 3)
    as_teacher_in_preview
    walk_contest_resumed
  end

  test "a trial student: the answer the outbox sends at the next page load comes with «Per me va bene così»" do
    build_flow_world
    as_student
    walk_contest_after_outbox
  end

  test "a trial student: after «Mostrami la soluzione» on an open exercise «Per me va bene così» is still offered" do
    build_flow_world(sentence: true)
    as_student
    walk_contest_after_solution
  end

  test "the teacher in the preview: after «Mostrami la soluzione» on an open exercise «Per me va bene così» is still offered" do
    build_flow_world(sentence: true)
    as_teacher_in_preview
    walk_contest_after_solution
  end

  test "a trial student: the same answer twice is refused and is not a try" do
    build_flow_world(sentence: true)
    as_student
    walk_same_answer
  end

  test "the teacher in the preview: the same answer twice is refused and is not a try" do
    build_flow_world(sentence: true)
    as_teacher_in_preview
    walk_same_answer
  end

  test "a trial student: a whole sentence around the blank is right with a note, a typo is «Ci sei quasi»" do
    build_flow_world(sentence: true)
    as_student
    walk_sentence_and_typo
  end

  test "the teacher in the preview: a whole sentence around the blank is right with a note, a typo is «Ci sei quasi»" do
    build_flow_world(sentence: true)
    as_teacher_in_preview
    walk_sentence_and_typo
  end

  test "a trial student: a right answer moves the exercise into the closed «Già fatti (1)», still clickable" do
    build_flow_world(number_items: 3)
    as_student
    walk_done_group
  end

  test "the teacher in the preview: a right answer moves the exercise into the closed «Già fatti (1)», still clickable" do
    build_flow_world(number_items: 3)
    as_teacher_in_preview
    walk_done_group
  end

  test "a trial student: a wrong answer then «Salta» leaves the entry «Finito» in «Già fatti»" do
    build_flow_world(number_items: 3)
    as_student
    walk_retry_status
  end

  test "the teacher in the preview: a wrong answer then «Salta» leaves the entry «Finito» in «Già fatti»" do
    build_flow_world(number_items: 3)
    as_teacher_in_preview
    walk_retry_status
  end

  # D-348: every instance of the skill was served and none is open: the page says so, nothing is served, one row is recorded, the list still
  # shows the exercise as done and «Rifai» (a click) opens a redo that does not count.
  test "a trial student who has seen every exercise of the skill is told so, and the list still redoes one" do
    build_flow_world
    student = practice_student("prova-1")
    revision = @topic_revision.body["practice"].find { |p| p["skill"] == SKILL }["items"].first["revision"].then { |id| ItemRevision.find(id) }
    revision.instances.order(:id).each_with_index do |instance, i|
      serve = make_serve(student, @topic_revision, instance, skill_key: SKILL, at: (10 - i).minutes.ago)
      make_try(serve, raw: JSON.parse(instance.answer_json).to_s, verdict: "correct", at: (10 - i).minutes.ago + 30.seconds)
    end
    as_student
    visit "/topics/#{TOPIC}/practice/#{SKILL}"
    assert_selector "#feedback", text: "Hai visto tutti gli esercizi di questa abilità. Ne stiamo preparando altri.", wait: 30
    assert_selector "#next-actions a", text: "Torna all'argomento"
    assert_no_selector "#check", visible: :visible
    key = revision.item.key
    find("#exercise-list details.exercise-done summary").click
    assert_selector "#{entry_selector(key)} .exercise-status", text: "Fatto"
    assert_equal 1, PracticePoolExhaustion.where(student: student, skill_key: SKILL).count
    assert_equal revision.instances.count, PracticeServe.where(student: student).count, "nothing was served"
    find("#{entry_selector(key)} .exercise-link").click
    assert_selector "#check:not([disabled])", wait: 30
    assert_selector "#serve-reason", text: "Questo esercizio l'hai già visto"
    assert_equal 1, PracticePoolExhaustion.where(student: student, skill_key: SKILL).count
    assert_clean "the pool that ran out"
  end

  test "a trial student on a 390 px phone: «Per me va bene così» does not scroll sideways" do
    build_flow_world(sentence: true)
    as_student
    walk_contest_phone
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

  test "a bilingual exercise on a 390 px phone: «Traduzione» next to «Controlla», the Italian under every text, the hint, the verdict and the solution join it" do
    walk_bilingual_choice
  end

  test "a bilingual exercise with a target-only material: the button and the instruction's Italian stay, the sentence and the forms have no translation line" do
    walk_bilingual_form_material
  end

  test "a bilingual reading passage: its Italian reaches the page only with the solution" do
    walk_bilingual_passage
  end

  test "a legacy exercise has no «Traduzione» button and no translation scope" do
    build_flow_world
    as_student
    walk_legacy_has_no_translation
  end
end
