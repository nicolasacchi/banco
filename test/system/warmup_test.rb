require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# The warm-up (B-11, E-04): before the release the student sees one line and the
# "prova dei comandi", and every editor task is typed with real key events, with the
# LaTeX the editor produces checked here, not trusted.
class WarmupTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  # The keys of each editor task, as the prompt says them.
  EDITOR_KEYS = {
    "ed_fraction" => [ "3", "/", "4", :Right ],
    "ed_power" => [ "x", "^", "2", :Right, "+", "3", "x" ],
    "ed_product" => [ "3", "a", "^", "2", :Right, "b" ],
    "ed_square" => [ "(", "a", "+", "b", ")", "^", "2" ],
    "ed_root" => %w[r a d 8],
    "ed_decimal" => [ "0", ",", "7", "5" ],
    "ed_division" => [ "1", "2", ":", "4" ]
  }.freeze

  setup do
    build_ui_subject
    sign_in_as :student
  end

  teardown { sign_out_env }

  def field_latex = page.evaluate_script("document.querySelector('math-field').value")

  def task_text = find("[data-warmup-target=itemBox] .prompt p", match: :first).text

  def current_task
    Diagnosis::Warmup.tasks.find { |t| t["prompt_it"] == task_text }
  end

  def wait_for_next(previous)
    assert_no_selector "[data-warmup-target=itemBox] .prompt p", text: previous, wait: 20
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

  def option_text(task, id) = %w[options elements left right].flat_map { |k| Array(task.dig("display", k)) }.find { |e| e["id"] == id }["text"]

  def do_task(task)
    case task["component"]
    when "choice" then find(".option-text", text: option_text(task, task["answer"]), exact_text: true).click
    when "number" then find("input[inputmode=decimal]").set(task["answer"])
    when "fraction"
      all(".fraction input")[0].set(task["answer"]["n"].to_s)
      all(".fraction input")[1].set(task["answer"]["d"].to_s)
    when "ordering" then order_rows(task["answer"].map { |id| option_text(task, id) })
    when "matching"
      all(".match-row").each do |row|
        left_id = task["display"]["left"].find { |l| l["text"] == row.find("label").text }["id"]
        row.find("select").select(option_text(task, task["answer"][left_id]))
      end
    when "normalized_text"
      find("input[type=text][lang]").set("pi")
      click_button "ù"
    when "dont_know" then click_button "Non lo so"
    when "pause"
      click_button "Pausa"
      assert_text "Sei in pausa."
      click_button "Riprendi"
    when "expression"
      assert_selector "math-field"
      find("math-field").click
      type_keys(*EDITOR_KEYS.fetch(task["id"]))
      produced = field_latex.gsub(/\\left|\\right|\s/, "")
      assert_includes task["accept"].map { |a| a.gsub(/\\left|\\right|\s/, "") }, produced,
                      "#{task['id']}: the editor produced #{field_latex.inspect}"
      # The rendered echo shows what was typed.
      assert_selector ".echo .katex"
    end
    click_button "Invia" unless %w[dont_know pause].include?(task["component"])
  end

  test "before the release the student sees one line and the warm-up, and finishes it" do
    visit "/diagnosis"
    assert_text "La diagnosi non è ancora aperta."
    assert_no_selector "li.subject"
    click_link "Prova dei comandi"
    assert_text "Compito 1 di #{Diagnosis::Warmup.tasks.size}"

    Diagnosis::Warmup.tasks.size.times do
      assert_selector "[data-warmup-target=itemBox] .prompt p", wait: 20
      task = current_task
      assert task, "unknown task text #{task_text.inspect}"
      text = task_text
      do_task(task)
      assert_text "Bene.", wait: 20
      wait_for_next(text) unless task["id"] == Diagnosis::Warmup.tasks.last["id"]
    end

    assert_text "Hai finito la prova dei comandi."
    assert Diagnosis::Warmup.complete?(@rows_student ||= Student.find_by!(key: "student"))
    assert_equal 0, Attempt.count, "the warm-up never counts"
    assert_equal 0, DiagnosisRun.count
    outside = requested_urls.reject { |u| u.start_with?(origin) || u.start_with?("data:") || u.start_with?("about:") }
    assert_empty outside

    visit "/diagnosis"
    assert_text "Hai già fatto la prova dei comandi."
  end

  test "a wrong answer says Riprova at once and does not move on" do
    visit "/diagnosis/warmup"
    assert_selector "[data-warmup-target=itemBox] .prompt p"
    first = task_text
    click_button "Invia" # nothing chosen
    assert_text "Riprova."
    assert_equal first, task_text
    find(".option-text", text: "3", exact_text: true).click # wrong: 2 + 2 is 4
    click_button "Invia"
    assert_text "Riprova."
    assert_equal first, task_text
  end

  test "after the release the warm-up is no longer offered" do
    release_diagnosis!
    visit "/diagnosis/warmup"
    assert_current_path "/diagnosis"
    assert_text "Fai le materie nell'ordine indicato."
  end
end
