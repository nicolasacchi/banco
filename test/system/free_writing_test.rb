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
