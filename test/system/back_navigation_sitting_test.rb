require "application_system_test_case"
require_relative "../support/student_ui_rows"
require_relative "../support/student_session"
require_relative "../support/sitting_answers"

# The arrow back around a sitting of the entry test (D-355). From Oggi the sitting is one page: the arrow back in the middle of it leaves for
# Oggi, keeps the open question (the clock is the server's, the question is served again as it was) and abandons nothing. At the end the page
# of the run is replaced by the results, so the arrow back from the results goes to Oggi instead of to a page that sends the student to the
# results again; «Vedi risultati e soluzioni» scrolls and adds no step. Text-free on purpose: ids, data attributes and hrefs.
class BackNavigationSittingTest < ApplicationSystemTestCase
  include StudentUiRows
  include StudentSession
  include SittingAnswers

  setup do
    @rows = build_ui_subject # the whole subject, as diagnosis_subject_test plays it to the results in one sitting
    release_diagnosis!
    sign_in_as :student
  end

  teardown { sign_out_env }

  def run_row = DiagnosisRun.where(student: @rows[:student]).order(:sequence).last
  def served_count = run_row.events.where(kind: "item_served").count
  def history_length = page.evaluate_script("history.length")

  def start_sitting_from_oggi
    visit "/today"
    find("#entry-next").click
    assert_current_path %r{/diagnosis/runs/\d+\z}
    find("[data-action='sitting#begin']").click
    assert_selector "[data-sitting-target=itemBox] .item-body .answer", wait: 30
  end

  def answer_current_item = answer_correctly

  # After an answer the page shows the next question or goes to the results; on a timeout it says where it stopped.
  def wait_for_next(count)
    Timeout.timeout(60) do
      loop do
        return :results if page.current_path.to_s.match?(%r{/results\z})
        return :item if page.has_selector?("[data-sitting-target=heading]", text: /Domanda #{count + 1}\z/, wait: 0.2)

        sleep 0.2
      end
    end
  rescue Timeout::Error
    flunk "after #{count} answers the page is #{page.current_path}: #{page.text.squish[0, 400]}"
  end

  def play_to_the_results
    answered = 0
    state = :item
    while state == :item
      flunk "the subject did not finish" if answered > 40
      assert_selector "[data-controller=sitting][data-ready='true']", wait: 30
      assert_selector "[data-sitting-target=itemBox] .item-body .answer"
      assert_selector "[data-sitting-target=heading]", text: /Domanda #{answered + 1}\z/
      answer_current_item
      answered += 1
      state = wait_for_next(answered)
    end
    assert_current_path %r{/diagnosis/runs/\d+/results\z}
  end

  test "the arrow back in the middle of a sitting leaves for Oggi, keeps the question open, and Riprendi serves it again" do
    start_sitting_from_oggi
    served = served_count
    assert_equal 1, served
    page.go_back
    assert_current_path "/today"
    assert_selector "#entry-next"
    assert_equal served, served_count, "leaving serves nothing and abandons nothing"
    assert_empty run_row.events.where(kind: %w[item_abandoned run_closed]).to_a

    find("#entry-next").click
    assert_current_path %r{/diagnosis/runs/\d+\z}
    find("[data-action='sitting#begin']").click
    assert_selector "[data-sitting-target=itemBox] .item-body .answer", wait: 30
    assert_selector "[data-sitting-target=heading]", text: /Domanda 1\z/
    assert_equal served, served_count, "the open question is served again, not a new one"
  end

  test "the end of a sitting: the arrow back from the results goes to Oggi, not to the page of the run" do
    start_sitting_from_oggi
    play_to_the_results
    assert_selector "#soluzioni", visible: :all
    page.go_back
    assert_current_path "/today"
    assert_selector "#entry-done", wait: 10 # the subject is finished, Oggi says so
    # and the run page is not on the way forward either: the results replaced it
    page.go_forward
    assert_current_path %r{/diagnosis/runs/\d+/results\z}
  end

  test "«Vedi risultati e soluzioni» scrolls to the solutions without a step of the history, so the arrow back leaves the results" do
    start_sitting_from_oggi
    play_to_the_results
    length = history_length
    find("a[href='#soluzioni']").click
    assert_equal length, history_length
    assert_equal "", page.evaluate_script("location.hash")
    assert_operator page.evaluate_script("document.getElementById('soluzioni').getBoundingClientRect().top"), :<, page.evaluate_script("window.innerHeight")
    page.go_back
    assert_current_path "/today"
  end
end
