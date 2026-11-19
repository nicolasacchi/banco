require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_course_world"

# D-377: an exercise opened on a topic revision that the teacher has since replaced with a new approved one. The student never meets it again:
# Oggi, the list, the page and a new serve go by the revision he is shown; an answer that still arrives for it is not graded and gets the line
# «aggiornato» with the new serve, never a closed-exercise dead end nor a rating box; the tries it already has keep counting.
class PracticeReplacedTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentCourseWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup { build_student_world }

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def get_json(headers, path)
    on(:web, path, headers: headers.merge("Accept" => "application/json"), remote_addr: EDGE)
    response.parsed_body
  end

  def serve_for(headers = OFFICIAL, **extra) = post_json(headers, "/practice/serves", { topic: TOPIC, skill: SKILL, **extra })
  def list_for(headers = OFFICIAL) = get_json(headers, "/practice/exercises?topic=#{TOPIC}")

  def answer_for(serve_id, raw, headers = OFFICIAL, id: SecureRandom.uuid)
    post_json(headers, "/practice/answers", { serve_id: serve_id, client_attempt_id: id, raw: raw, source: "text" })
  end

  def correct_of(serve_id) = correct_raw(PracticeServe.find(serve_id))

  # The teacher revises the topic: a new approved revision pinning `revisions` (the same item revisions by default).
  def revise!(revisions = @revisions)
    topic = make_topic(@lesson_revision, { SKILL => revisions }, course: @course)
    approve_topic!(topic)
    topic
  end

  def today_resume
    on(:web, "/today", headers: OFFICIAL, remote_addr: EDGE)
    css_select("#now-resume")
  end

  def counts = Course::StudentView.new(@official).state(SKILL).counts

  test "Oggi and the page resume the open exercise while its revision is the one he is shown, and not after the topic is revised" do
    opened = serve_for
    assert_equal "item", opened["type"]
    assert_equal 1, today_resume.size, "before the revision: the topic is the one he left half done"
    assert_equal opened["serve_id"], serve_for["serve_id"], "and the page resumes the serve"

    topic_b = revise!
    assert_empty today_resume, "Oggi offers no «Riprendi» for an exercise of a replaced revision"
    assert_equal "open", PracticeServe.find(opened["serve_id"]).then { |s| Practice::Loader.status_of(s, now: Time.current).state.to_s }, "the loader alone knows no better"
    assert_equal :replaced, Practice::Loader.status_of(PracticeServe.find(opened["serve_id"]), now: Time.current, shown: Course::StudentView.new(@official).shown_revisions).state

    entry = list_for["skills"].first["exercises"].find { |e| e["item"] == PracticeServe.find(opened["serve_id"]).item_instance.item_revision.item.key }
    assert_equal [ "todo", nil ], [ entry["status"], entry["open_serve_id"] ], "the list does not offer it as open or as finished"

    fresh = serve_for
    assert_equal "item", fresh["type"]
    assert_not_equal opened["serve_id"], fresh["serve_id"]
    row = PracticeServe.find(fresh["serve_id"])
    assert_equal topic_b.id, row.topic_revision_id, "the next serve comes from the revision he is shown"
    assert_equal PracticeServe.find(opened["serve_id"]).item_instance.item_revision.item_id, row.item_instance.item_revision.item_id, "of the same item, still pinned"
    assert_equal fresh["serve_id"], serve_for["serve_id"], "and that one is resumed from now on"
  end

  test "POST /practice/serves with an item gives that item from the new revision, never the replaced serve" do
    opened = serve_for
    key = PracticeServe.find(opened["serve_id"]).item_instance.item_revision.item.key
    topic_b = revise!
    chosen = serve_for(item: key)
    assert_not_equal opened["serve_id"], chosen["serve_id"]
    assert_equal topic_b.id, PracticeServe.find(chosen["serve_id"]).topic_revision_id
  end

  test "an answer to the replaced serve is not graded: the line «aggiornato» and the new serve come, no try is written and no rating box is asked for" do
    opened = serve_for
    tries_before = PracticeAttempt.count
    topic_b = revise!
    reply = answer_for(opened["serve_id"], correct_of(opened["serve_id"]))
    assert_response :success
    assert_equal "replaced", reply["status"]
    assert_equal "Questo esercizio è stato aggiornato: eccolo nella versione nuova.", reply["message_it"]
    assert_equal "item", reply.dig("serve", "type")
    assert_not_equal opened["serve_id"], reply.dig("serve", "serve_id")
    assert_equal topic_b.id, PracticeServe.find(reply.dig("serve", "serve_id")).topic_revision_id
    assert_equal "open", reply.dig("serve", "status")
    assert_equal 1, reply.dig("serve", "next_try_number"), "a serve with no try"
    assert_not reply.key?("outcome")
    assert_equal tries_before, PracticeAttempt.count, "nothing was graded or stored"
    assert_equal 0, PracticeEvent.where(practice_serve_id: opened["serve_id"]).count

    again = answer_for(opened["serve_id"], correct_of(opened["serve_id"]))
    assert_equal [ "replaced", reply.dig("serve", "serve_id") ], [ again["status"], again.dig("serve", "serve_id") ], "an outbox retry gets the same serve"
    assert_equal 1, PracticeServe.where(topic_revision_id: topic_b.id).count
  end

  test "the new serve of the reply is answered like any serve" do
    opened = serve_for
    revise!
    reply = answer_for(opened["serve_id"], "1")
    assert_equal "replaced", reply["status"]
    fresh = reply.dig("serve", "serve_id")
    verdict = answer_for(fresh, correct_of(fresh))
    assert_equal "graded", verdict["status"]
    assert_equal "correct", verdict["outcome"]
  end

  test "the reply says so in English too" do
    assert_equal "This exercise has been updated: here it is in the new version.", I18n.t("practice.replaced", locale: :en)
  end

  test "the tries made on the replaced serve keep counting for the skill" do
    opened = serve_for
    assert_equal "graded", answer_for(opened["serve_id"], "99999")["status"] # not right, the serve stays open
    assert_equal :open, Practice::Loader.status_of(PracticeServe.find(opened["serve_id"]), now: Time.current).state
    before = counts
    revise!
    assert_equal :replaced, Practice::Loader.status_of(PracticeServe.find(opened["serve_id"]), now: Time.current, shown: Course::StudentView.new(@official).shown_revisions).state
    answer_for(opened["serve_id"], "1") # the replaced reply
    after = counts
    assert_equal 1, after[:tries]
    assert_equal before.except(:abandoned, :serves), after.except(:abandoned, :serves), "the try is still in the fold"
    assert_equal 2, after[:serves], "and the new serve is counted"
    assert_equal 1, after[:abandoned], "the serve is counted as left unfinished"
    assert_equal 1, PracticeAttempt.where(practice_serve_id: opened["serve_id"]).count
  end

  test "an item that the new revision no longer pins is not served again; another pinned item is" do
    opened = serve_for
    old_item = PracticeServe.find(opened["serve_id"]).item_instance.item_revision.item_id
    revise!([ @revisions.last ])
    reply = answer_for(opened["serve_id"], "1")
    assert_equal "replaced", reply["status"]
    assert_not_equal old_item, PracticeServe.find(reply.dig("serve", "serve_id")).item_instance.item_revision.item_id
  end

  test "an item revised on its own: the serve comes from the new item revision" do
    opened = serve_for
    old = PracticeServe.find(opened["serve_id"]).item_instance.item_revision
    revised = ItemRevision.create!(item: old.item, seq: 2, body_json: old.body_json, file_sessions_json: "{}")
    old.instances.each_with_index do |i, n|
      ItemInstance.create!(i.attributes.except("id").merge("item_revision_id" => revised.id, "fingerprint" => "rev2-#{n}"))
    end
    ItemValidation.create!(item_revision: revised, seq: 1, status: "passed", codes_json: "[]")
    revise!([ revised, *(@revisions - [ old ]) ])
    reply = answer_for(opened["serve_id"], "1")
    assert_equal "replaced", reply["status"]
    assert_equal revised.id, PracticeServe.find(reply.dig("serve", "serve_id")).item_instance.item_revision_id
  end

  test "hint and solution on the replaced serve say the same line and write nothing" do
    opened = serve_for
    revise!
    events = PracticeEvent.count
    reply = post_json(OFFICIAL, "/practice/serves/#{opened['serve_id']}/hint", { n: 1 })
    assert_response :conflict
    assert_equal "replaced", reply["status"]
    reply = post_json(OFFICIAL, "/practice/serves/#{opened['serve_id']}/solution", {})
    assert_response :conflict
    assert_equal "replaced", reply["status"]
    assert_equal events, PracticeEvent.count
  end

  test "a serve already closed is not touched by the new revision" do
    opened = serve_for
    assert_equal "correct", answer_for(opened["serve_id"], correct_of(opened["serve_id"]))["outcome"]
    revise!
    status = Practice::Loader.status_of(PracticeServe.find(opened["serve_id"]), now: Time.current, shown: Course::StudentView.new(@official).shown_revisions)
    assert_equal [ :closed, :correct ], [ status.state, status.closed_by ]
    reply = answer_for(opened["serve_id"], correct_of(opened["serve_id"]))
    assert_equal [ 409, "closed" ], [ response.status, reply["status"] ]
  end

  test "the ledger is append-only: the replaced serve and its rows are the same after the new serve" do
    opened = serve_for
    answer_for(opened["serve_id"], "99999")
    snapshot = [ PracticeServe.find(opened["serve_id"]).attributes, PracticeAttempt.where(practice_serve_id: opened["serve_id"]).map(&:attributes),
                 PracticeEvent.where(practice_serve_id: opened["serve_id"]).map(&:attributes) ]
    revise!
    answer_for(opened["serve_id"], "1")
    serve_for
    assert_equal snapshot, [ PracticeServe.find(opened["serve_id"]).attributes, PracticeAttempt.where(practice_serve_id: opened["serve_id"]).map(&:attributes),
                             PracticeEvent.where(practice_serve_id: opened["serve_id"]).map(&:attributes) ]
  end
end
