require "application_system_test_case"
require_relative "../support/lesson_events_world"
require_relative "../support/finished_run"
require_relative "../support/student_session"

# D-361, «Commenta» on every page of the student's, in Chrome: the student opens each page, finds the control, writes a comment about the
# whole page and it is stored under the right kind of page and address. The table of the pages is in the decision.
class CommentsEverywhereTest < ApplicationSystemTestCase
  include LessonEventsWorld
  include StudentSession

  setup { sign_in_as :student }
  teardown { sign_out_env }

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until (value = yield)
      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
    value
  end

  # On the page the browser is on: the control, «Tutta la pagina», a reason, a text, «Invia». Returns the comment that was stored.
  def comment_here(label)
    before = Comment.count
    find("[data-comment-open]", match: :first, visible: :visible, wait: 15).click
    find("#comment-whole", wait: 10).click
    assert_selector "#comment-box[open]", wait: 10
    choose "Altro"
    fill_in "comment-text", with: "Prova da #{label}."
    find("#comment-send").click
    assert_no_selector "#comment-box[open]", wait: 10
    wait_until { Comment.count == before + 1 }
    Comment.order(:id).last
  end

  test "every page of the course, the lists, the settings, the notices, the conversation and a page that is not there takes a comment" do
    build_student_world(approve: true, release: true)
    thread = Comment.create!(student: @official, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "like", page_kind: "today", page_path: "/today", created_at: Time.current)
    pages = {
      "/today" => "today", "/subjects" => "subjects", "/subjects/math" => "subject", "/topics/#{TOPIC}" => "topic", "/topics/#{TOPIC}/lesson" => "lesson",
      "/topics/#{TOPIC}/practice/#{SKILL}" => "practice", "/search" => "search", "/settings" => "settings", "/privacy" => "privacy",
      "/account" => "account", "/comments" => "comments", "/comments/#{thread.id}" => "comments", "/diagnosis" => "diagnosis",
      "/diagnosis/warmup" => "warmup", "/schemas" => "schemas", "/topics/#{TOPIC}/schema" => "schema" # D-372; the topic is not done: the page says it is closed, and takes a comment
    }
    pages.each do |path, kind|
      visit path
      comment = comment_here(path)
      assert_equal [ kind, path ], [ comment.page_kind, comment.page_path ], path
    end
    # a page of his that is not there: the designed 404 in his layout, filed under what he asked for
    { "/civics" => "/not-found/civics", "/subjects/nonesiste" => "/not-found/subjects/nonesiste", "/topics/ripasso.math.nonesiste" => "/not-found/topics/ripasso.math.nonesiste" }.each do |path, filed|
      visit path
      assert_selector "#error-page[data-status=not_found]"
      comment = comment_here(path)
      assert_equal [ "not_found", filed ], [ comment.page_kind, comment.page_path ], path
    end
  end

  test "in the entry test: the list, the first page, a question and the next question take a comment, and so does the end of the test" do
    kit = Module.new.extend(FinishedRun)
    rows = kit.build_ui_subject
    kit.release_diagnosis!
    visit "/diagnosis"
    assert_equal "diagnosis", comment_here("diagnosis").page_kind
    visit "/diagnosis"
    click_button "Comincia"
    assert_selector "[data-sitting-target=intro]", wait: 15
    intro = comment_here("the first page of the test")
    run = DiagnosisRun.find_by!(student: rows[:student])
    assert_equal [ "sitting", run.id, nil ], [ intro.page_kind, intro.diagnosis_run_id, intro.served_event_id ]
    click_button "Comincia"
    assert_selector "input[inputmode=decimal]", wait: 15
    first = comment_here("the first question")
    assert_equal run.events.where(kind: "item_served").order(:seq).first.id, first.served_event_id
    find("input[inputmode=decimal]").set("6")
    click_button "Invia"
    wait_until { Attempt.count == 1 && run.events.where(kind: "item_served").count == 2 }
    served = run.events.where(kind: "item_served").order(:seq).last
    wait_until { page.evaluate_script("document.querySelector('[data-sitting-target=itemBox]').dataset.commentServedEventId") == served.id.to_s }
    second = comment_here("the next question")
    assert_equal [ "sitting", run.id, served.id ], [ second.page_kind, second.diagnosis_run_id, second.served_event_id ]
  end

  test "the end of a test takes a comment" do
    kit = Module.new.extend(FinishedRun)
    rows = kit.build_ui_subject
    kit.release_diagnosis!
    run = kit.play_run(rows[:student], rows[:subject])
    visit "/diagnosis/runs/#{run.id}/results"
    comment = comment_here("the results")
    assert_equal [ "results", "/diagnosis/runs/#{run.id}/results", run.id ], [ comment.page_kind, comment.page_path, comment.diagnosis_run_id ]
  end
end
