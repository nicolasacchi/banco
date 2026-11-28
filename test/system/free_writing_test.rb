require "application_system_test_case"
require_relative "../support/student_session"
require_relative "../support/writing_world"

# D-407, «Scrivi tu» in Chrome on a 390 px phone: the student writes a text of his own under the task, sees the live word count, reloads and finds the draft,
# sends it and reads «Consegnato. Lo corregge il docente.» with the text read-only; once the teacher has corrected it the correction is under the text and
# «Scrivi una nuova versione» opens a new box that starts from his text and sends a new row. Any JavaScript error or CSP violation fails.
class FreeWritingSystemTest < ApplicationSystemTestCase
  include WritingWorld
  include StudentSession

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

  TEXT = "Ho spostato il sette a destra e ho diviso per tre.".freeze
  CORRECTION = "Bene i passaggi. Aggiungi la verifica alla fine.".freeze

  setup do
    build_writing_world
    sign_in_as :student
    @saved_decisions = ENV["BANCO_DECISIONS_ENABLED"]
    ENV["BANCO_DECISIONS_ENABLED"] = "1" # the console records the teacher's correction
    @watch_id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: WATCH)["identifier"]
    page.driver.resize(390, 844)
  end

  teardown do
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: @watch_id) if @watch_id
    page.driver.resize(1280, 900)
    @saved_decisions ? ENV["BANCO_DECISIONS_ENABLED"] = @saved_decisions : ENV.delete("BANCO_DECISIONS_ENABLED")
    sign_out_env
  end

  def assert_clean(where) = assert_empty(Array(page.evaluate_script("window.__problems || []")), "#{where}: the browser reported problems")

  test "write, reload and find the draft, send, read «Consegnato»; then the correction is shown and a new version goes" do
    visit topic_path
    assert_selector "#writing h2", text: "Scrivi tu"
    assert_selector "#writing-1-stem", text: TASK_TEXT
    assert_selector "#writing-1 .answer-format", text: TASK_FORMAT, visible: :visible # the advice that the rubric grades is under the task (D-410)
    assert_selector "#writing .writing-range", text: "Da 20 a 60 parole."
    assert_selector "[data-writing-target=count]", text: "0 parole"

    fill_in "writing-1-text", with: TEXT
    assert_selector "[data-writing-target=count]", text: "11 parole"
    assert_selector "[data-writing-target=chars]", text: "#{TEXT.length} caratteri su 4000"
    assert_equal TEXT, page.evaluate_script("localStorage.getItem('banco.wdraft.#{TASK_KEY}')"), "the draft is kept as he types"

    visit topic_path # a reload loses nothing
    assert_equal TEXT, find("#writing-1-text").value
    assert_selector "[data-writing-target=count]", text: "11 parole"
    assert_equal 0, WritingSubmission.count

    click_button "Consegna"
    assert_selector "#writing .writing-note", text: "Consegnato. Lo corregge il docente.", wait: 15
    assert_selector "#writing .writing-sent .writing-text", text: TEXT
    assert_no_selector "#writing form.writing-form", visible: :visible
    assert_no_selector "#writing button", text: "Scrivi una nuova versione", visible: :visible
    assert_nil page.evaluate_script("localStorage.getItem('banco.wdraft.#{TASK_KEY}')"), "the draft goes when the text is sent"
    assert_equal 0, page.evaluate_script("Object.keys(localStorage).filter((k) => k.startsWith('banco.woutbox.')).length"), "the outbox is empty once it is recorded"
    row = WritingSubmission.sole
    assert_equal [ @official.id, TEXT, 11, @task.id ], [ row.student_id, row.text, row.word_count, row.item_revision_id ]

    visit topic_path # the server draws it as sent, read-only
    assert_selector "#writing .writing-task[data-state=sent] .writing-note", text: "Consegnato. Lo corregge il docente."
    assert_no_selector "#writing form.writing-form", visible: :visible

    # the teacher's correction, recorded the way the console does it
    result = DecisionConsole.call(kind: "correct_writing", teacher: "nik", params: { writing_submission_id: row.id, text_it: CORRECTION }, confirm: true)
    assert result.ok, result.errors.inspect
    visit topic_path
    assert_selector "#writing .writing-task[data-state=corrected]"
    assert_selector "#writing .writing-sent .writing-text", text: TEXT
    assert_selector "#writing .writing-correction .writing-correction-text", text: CORRECTION
    click_button "Scrivi una nuova versione"
    assert_selector "#writing form.writing-form", visible: :visible
    assert_equal TEXT, find("#writing-1-text").value, "the new version starts from his text"
    fill_in "writing-1-text", with: "#{TEXT} Poi ho fatto la verifica."
    click_button "Consegna"
    assert_selector "#writing .writing-note", text: "Consegnato. Lo corregge il docente.", wait: 15
    assert_no_selector "#writing .writing-correction", visible: :visible
    assert_equal [ TEXT, "#{TEXT} Poi ho fatto la verifica." ], WritingSubmission.order(:id).pluck(:text)
    assert_clean "the writing box"
  end

  # D-410: the task is drawn with the items' markup (a blank line is a paragraph, a numbered plan after a blank line is a list), not as pre-line text.
  test "a plan in the task is drawn as a numbered list, and the answer format stays under it" do
    plan = make_writing_item("math-write-plan", text: "Racconta come hai risolto l'equazione.\n\n1. Che cosa hai fatto prima.\n2. Che cosa dopo.\n3. Come hai verificato.\n\nEcco **come** si fa.")
    approve_topic!(make_writing_topic(@topic_revision, [ @task, plan ]))
    visit topic_path
    assert_selector "#writing-2-stem > p", text: "Racconta come hai risolto l'equazione."
    assert_selector "#writing-2-stem > ol > li", count: 3
    assert_selector "#writing-2-stem > ol > li:first-child", text: "Che cosa hai fatto prima."
    assert_selector "#writing-2-stem > p strong", text: "come"
    assert_selector "#writing-2 .answer-format", text: TASK_FORMAT
    assert_clean "the plan"
  end

  # D-410: the Italian translation of a task is drawn by the same reader (a `.tr` node is `data-markup=inline`, as items/bilingual.js's trNode draws it), so a plan in
  # the Italian is a list too. The topic of this world teaches no language, so the node is built here and drawn by the page's own module.
  test "the translation node of a task draws a numbered plan as a list" do
    visit topic_path
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      import("items/markup").then(({ drawMarked }) => {
        const root = document.createElement("div");
        root.innerHTML = '<div class="tr" lang="it" data-nospeech data-markup="inline"></div>';
        root.firstChild.textContent = "Racconta.\\n\\n1. Prima.\\n2. Dopo.";
        drawMarked(root);
        done({ items: [...root.querySelectorAll("ol > li")].map((li) => li.textContent), text: root.textContent });
      });
    JS
    assert_equal [ "Prima.", "Dopo." ], result["items"]
    assert_not_includes result["text"], "1. Prima"
    assert_clean "the translation plan"
  end

  test "an empty text is not sent and says so; the box fits the phone" do
    visit topic_path
    click_button "Consegna"
    assert_selector "[data-writing-target=status]", text: "Scrivi qualcosa prima di consegnare."
    assert_equal 0, WritingSubmission.count
    fits = page.evaluate_script(<<~JS)
      (() => {
        const box = document.getElementById("writing").getBoundingClientRect();
        const parts = Array.from(document.querySelectorAll("#writing *")).filter((e) => e.offsetParent !== null).map((e) => e.getBoundingClientRect());
        return { right: box.right, width: window.innerWidth, partRight: Math.max(...parts.map((r) => r.right)), scroll: document.documentElement.scrollWidth };
      })()
    JS
    assert_operator fits["right"], :<=, fits["width"] + 0.5
    assert_operator fits["partRight"], :<=, fits["width"] + 0.5
    assert_operator fits["scroll"], :<=, fits["width"] + 1, "no sideways scroll"
    assert_clean "the empty box"
  end
end
