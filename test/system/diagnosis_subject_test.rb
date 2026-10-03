require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"

# A whole subject in Chrome: from the list to the end-of-subject screen, answering
# every component through the page with the keyboard and the mouse, as the student
# would, and checking what the ledger and the screens say at the end.
class DiagnosisSubjectTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession

  setup do
    @rows = build_ui_subject
    release_diagnosis!
    sign_in_as :student
  end

  teardown { sign_out_env }

  def run_row = DiagnosisRun.where(student: @rows[:student]).order(:sequence).last

  def current_event = run_row.events.where(kind: "item_served").order(:seq).last

  def stored_text(display, id)
    %w[options elements left right].flat_map { |k| Array(display[k]) }.find { |e| e["id"] == id }["text"]
  end

  # Fills in the item on screen with its right answer.
  def answer_correctly
    event = current_event
    served = ItemServed.find_by!(diagnosis_event_id: event.id)
    instance = served.item_instance
    body = JSON.parse(instance.item_revision.body_json)
    display = JSON.parse(instance.display_json)
    answer = JSON.parse(instance.answer_json)
    component = body["kind"] == "testlet" ? "testlet" : body["kind"] == "short_answer" ? "short_answer" : body["component"]
    assert_selector "[data-sitting-target=itemBox] .item-body .answer"
    fill_component(component, display, answer)
    click_button "Invia"
    component
  end

  def fill_component(component, display, answer)
    case component
    when "number" then find("input[inputmode=decimal]").set(answer)
    when "fraction"
      all(".fraction input")[0].set(answer["n"].to_s)
      all(".fraction input")[1].set(answer["d"].to_s)
    when "choice" then pick_option(stored_text(display, answer), within: find("fieldset.options"))
    when "ordering" then order_rows(answer.map { |id| stored_text(display, id) })
    when "matching"
      all(".match-row").each do |row|
        left_text = row.find("label").text
        left_id = display["left"].find { |l| l["text"] == left_text }["id"]
        row.find("select").select(stored_text(display, answer[left_id]))
      end
    when "normalized_text" then find("input[type=text][lang]").set(answer)
    when "expression"
      find("math-field").click
      type_keys(*answer.chars)
    when "testlet"
      all(".sub-item").each do |section|
        sub = display["sub_items"].find { |s| s["id"] == section["data-sub"] }
        pick_option(stored_text(sub["display"], answer[sub["id"]]), within: section.find("fieldset.options"))
      end
    when "short_answer" then find("textarea").set("Una risposta di prova scritta dallo studente.")
    else flunk "no way to answer #{component}"
    end
  end

  def pick_option(text, within:)
    within.find(".option-text", text: text, exact_text: true).click
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

  # After an answer the page either shows the next question or goes to the results.
  def wait_for_next(count)
    Timeout.timeout(60) do
      loop do
        return :results if page.current_path.to_s.match?(%r{/results\z})
        return :item if page.has_selector?("[data-sitting-target=heading]", text: /Domanda #{count + 1}\z/, wait: 0.2)

        sleep 0.2
      end
    end
  end

  test "a student completes the subject, end to end" do
    visit "/diagnosis"
    assert_text "Fai le materie nell'ordine indicato."
    assert_selector "li.subject[data-subject=math]", text: "Matematica"
    click_button "Comincia"

    # The start screen: six lines, no clock.
    assert_text "Test d'ingresso · Matematica"
    assert_text "Non è un voto: serve a capire da dove partire."
    assert_text "Dura circa 30 minuti."
    assert_text "senza calcolatrice"
    refute_text(/\d{1,2}:\d{2}/, wait: 0)
    click_button "Comincia"

    seen = []
    state = :item
    while state == :item
      flunk "the subject did not finish" if seen.size > 40
      assert_selector "[data-sitting-target=itemBox] .item-body .answer", wait: 30
      assert_selector "[data-sitting-target=heading]", text: /Matematica · Domanda \d+/
      assert_no_selector ".timer, progress, [role=progressbar]"
      seen << answer_correctly
      assert_text(/Risposta salvata|La tua risposta è arrivata/, wait: 20)
      state = wait_for_next(seen.size)
    end

    assert_current_path %r{/diagnosis/runs/\d+/results}
    assert_text "Hai finito Matematica."
    assert_text(/Hai lavorato (meno di un|\d+) minut[oi]\./)
    assert_text "Questo non è un voto."
    assert_selector "h2", text: "Sai già fare"
    assert_selector "[data-group=known] li", count: 8
    assert_selector "[data-group=checking] li", count: 1 # the short answer waits for the teacher
    # The run is held open for the short answer (D-039): solutions wait until the subject is final.
    assert_no_selector "article.solution"
    refute_text(/\d+ ?%/)

    run = run_row
    assert_equal %w[number fraction choice ordering matching normalized_text expression testlet short_answer].sort, seen.uniq.sort
    assert_not run.events.where(kind: "run_closed").exists?, "a pending short answer holds the run open"
    assert_equal "unsupervised", JSON.parse(run.events.where(kind: "sitting_started").first.payload_json)["condition"]
    verdicts = AttemptGrading.joins(:attempt).where(attempts: { student_id: @rows[:student].id }).pluck(:verdict)
    assert_equal 1, verdicts.count("short_answer")
    assert_equal verdicts.size - 1, verdicts.count("correct"), "every other answer was graded correct: #{verdicts.tally}"
    assert_equal 0, Attempt.where.not(context: "diagnosis").count
  end
end
