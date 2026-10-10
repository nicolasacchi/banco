require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/lesson_events_world"

# R3 (A9, A11, A14): the lesson's own ledger, the check endpoint, the events batch, the teacher's full body, and the
# proof that nothing of it reaches the skill states.
class LessonEventsTest < ActionDispatch::IntegrationTest
  include MultiUser
  include LessonEventsWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def check_url(card, block, tail = "") = "/topics/#{TOPIC}/lesson/checks/#{card}/#{block}#{tail}"
  def events_url = "/topics/#{TOPIC}/lesson/events"
  def cid = "e-" + SecureRandom.hex(8)

  setup { build_lesson_world }

  def build_lesson_world = build_student_world(approve: true, release: true)

  # ---- the table ---------------------------------------------------------------------------------------

  test "lesson_events refuses UPDATE and DELETE, and the kinds of every release are in its CHECK" do
    event = LessonEvent.create!(student: @official, topic_revision: @topic_revision, lesson_revision: @lesson_revision, kind: "card_seen", card: 1,
                                payload_json: "{}", at: Time.current, created_at: Time.current)
    assert_raises(ActiveRecord::StatementInvalid) { LessonEvent.connection.execute("UPDATE lesson_events SET card = 2 WHERE id = #{event.id}") }
    assert_raises(ActiveRecord::StatementInvalid) { LessonEvent.connection.execute("DELETE FROM lesson_events WHERE id = #{event.id}") }
    LessonEvent::KINDS.each do |kind|
      sql = "INSERT INTO lesson_events (student_id, topic_revision_id, lesson_revision_id, kind, card, block, payload_json, grader_version, at, created_at) VALUES " \
            "(#{@official.id}, #{@topic_revision.id}, #{@lesson_revision.id}, '#{kind}', 1, 1, '{}', 'x', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      assert_nothing_raised { LessonEvent.connection.execute(sql) }
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      LessonEvent.connection.execute("INSERT INTO lesson_events (student_id, topic_revision_id, lesson_revision_id, kind, payload_json, at, created_at) VALUES " \
                                     "(#{@official.id}, #{@topic_revision.id}, #{@lesson_revision.id}, 'sneaky', '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
    end
  end

  test "student_questions kept its triggers when it gained the card column" do
    assert_includes StudentQuestion.column_names, "card"
    StudentQuestion.create!(student: @official, client_question_id: "q-" + SecureRandom.hex(6), card: 3, created_at: Time.current)
    assert_raises(ActiveRecord::StatementInvalid) { StudentQuestion.connection.execute("UPDATE student_questions SET card = 4") }
    assert_raises(ActiveRecord::StatementInvalid) { StudentQuestion.connection.execute("DELETE FROM student_questions") }
  end

  # A newer lesson revision with this body, pinned by a newer approved topic revision (the tables are append-only).
  def pin_body(body)
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "1" * 64, rules_version: Validation::Rules.version.to_s,
                                              warnings_json: "[]", body_json: JSON.generate(body))
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 2, course_revision: @course, lesson_revision: @lesson_revision, body_json: @topic_revision.body_json)
    approve_topic!(@topic_revision)
  end

  # ---- events ------------------------------------------------------------------------------------------

  test "a batch of card_seen is stored once, idempotent on client_event_id, one per card per ten minutes" do
    one = cid
    reply = post_json(OFFICIAL, events_url, { events: [ { kind: "card_seen", card: 2, client_event_id: one }, { kind: "card_seen", card: 3, client_event_id: cid } ] })
    assert_response :success
    assert_equal({ "ok" => true, "accepted" => 2 }, reply)
    assert_equal [ 2, 3 ], LessonEvent.order(:id).pluck(:card)
    post_json(OFFICIAL, events_url, { events: [ { kind: "card_seen", card: 2, client_event_id: one } ] })
    assert_response :success
    assert_equal 2, LessonEvent.count
    post_json(OFFICIAL, events_url, { events: [ { kind: "card_seen", card: 2, client_event_id: cid } ] })
    assert_response :success
    assert_equal 2, LessonEvent.count, "the same card again within ten minutes is dropped"
    travel 11.minutes do
      post_json(OFFICIAL, events_url, { events: [ { kind: "card_seen", card: 2, client_event_id: cid } ] })
    end
    assert_equal 3, LessonEvent.count
    row = LessonEvent.first
    assert_equal [ @official.id, @topic_revision.id, @lesson_revision.id, "card_seen" ], [ row.student_id, row.topic_revision_id, row.lesson_revision_id, row.kind ]
  end

  test "an event batch is refused whole when one event is wrong" do
    bad = [ { events: [] }, { events: "x" }, { events: Array.new(21) { { kind: "card_seen", card: 1, client_event_id: cid } } },
            { events: [ { kind: "card_seen", card: 999, client_event_id: cid } ] }, { events: [ { kind: "card_seen", card: "2", client_event_id: cid } ] },
            { events: [ { kind: "check_answered", card: 1, client_event_id: cid } ] }, { events: [ { kind: "page_opened", card: 1, client_event_id: cid } ] },
            { events: [ { kind: "card_seen", card: 1, client_event_id: "x" } ] },
            { events: [ { kind: "card_seen", card: 1, client_event_id: cid }, { kind: "card_seen", card: 0, client_event_id: cid } ] } ]
    bad.each do |body|
      post_json(OFFICIAL, events_url, body)
      assert_response :unprocessable_entity, body.to_json[0, 80]
    end
    assert_equal 0, LessonEvent.count
  end

  test "the trial student writes under its own key, the official student's rows stay apart" do
    post_json(TRIAL, events_url, { events: [ { kind: "card_seen", card: 1, client_event_id: cid } ] })
    assert_response :success
    assert_equal [ @trial.id ], LessonEvent.pluck(:student_id)
  end

  test "guests, the teacher and unmapped students get 403 and no row; a topic that is hidden is a 404" do
    body = { events: [ { kind: "card_seen", card: 1, client_event_id: cid } ] }
    [ GUEST, TEACHER, UNMAPPED ].each do |who|
      post_json(who, events_url, body)
      assert_response :forbidden
      post_json(who, check_url(1, 3), { response: "a", try: 1, client_event_id: cid })
      assert_response :forbidden
    end
    assert_equal 0, LessonEvent.count
    post_json(OFFICIAL, "/topics/ripasso.math.nope/lesson/events", body)
    assert_response :not_found
  end

  test "a lesson/1 topic has no events and no checks" do
    pin_body(StudentCourseWorld.instance_method(:lesson_body).bind_call(self))
    post_json(OFFICIAL, events_url, { events: [ { kind: "card_seen", card: 1, client_event_id: cid } ] })
    assert_response :not_found
    post_json(OFFICIAL, check_url(1, 3), { response: "a" })
    assert_response :not_found
  end

  # ---- checks ------------------------------------------------------------------------------------------

  def choice
    @choice ||= find_block { |_, b| b["type"] == "check" && b["component"] == "choice" }
  end

  test "a choice is graded with the student's own shuffle: right, wrong with its message, the explanation after the second wrong" do
    card, block, check = choice
    right = shown_id(@official, card, block, check["answer"])
    wrong = shown_id(@official, card, block, "a")
    refute_equal right, wrong
    first = post_json(OFFICIAL, check_url(card, block), { response: wrong, try: 1, client_event_id: cid })
    assert_response :success
    assert_equal "wrong", first["verdict"]
    assert_equal 1, first["try"]
    assert_equal check["errors"].find { |e| e["answer"] == "a" }["message_it"], first["message_it"]
    assert_not first.key?("explain_it"), "no explanation at the first wrong answer"
    second = post_json(OFFICIAL, check_url(card, block), { response: wrong, try: 2, client_event_id: cid })
    assert_equal [ "wrong", 2, check["explain_it"] ], second.values_at("verdict", "try", "explain_it")
    third = post_json(OFFICIAL, check_url(card, block), { response: right, try: 3, client_event_id: cid })
    assert_equal [ "right", 3, check["explain_it"] ], third.values_at("verdict", "try", "explain_it")
    assert_not third.key?("message_it")
    rows = LessonEvent.where(kind: "check_answered").order(:id)
    assert_equal 3, rows.count
    assert_equal %w[wrong wrong right], rows.map { |r| r.payload["verdict"] }
    assert_equal [ 1, 2, 3 ], rows.map { |r| r.payload["try"] }
    assert_equal [ wrong, "choice" ], rows.first.payload.values_at("response", "component")
    assert rows.all? { |r| r.grader_version.present? && [ r.card, r.block ] == [ card, block ] }
  end

  test "the same answer arriving twice is one row with the same try, and the server counts the tries, not the browser" do
    card, block, = choice
    wrong = shown_id(@official, card, block, "a")
    id = cid
    a = post_json(OFFICIAL, check_url(card, block), { response: wrong, try: 7, client_event_id: id })
    b = post_json(OFFICIAL, check_url(card, block), { response: wrong, try: 7, client_event_id: id })
    assert_equal a, b
    assert_equal 1, a["try"]
    assert_equal 1, LessonEvent.where(kind: "check_answered").count
    post_json(OFFICIAL, check_url(card, block), { response: wrong, client_event_id: id.reverse.gsub(/\W/, "x") })
    assert_equal 2, LessonEvent.where(kind: "check_answered").count
    other_block = post_json(OFFICIAL, check_url(card, block + 99), { response: wrong, client_event_id: id })
    assert_response :not_found
    assert_equal({ "status" => "not_found" }, other_block)
  end

  test "a replay with another response answers for the stored one" do
    card, block, check = choice
    right = shown_id(@official, card, block, check["answer"])
    wrong = shown_id(@official, card, block, "a")
    id = cid
    a = post_json(OFFICIAL, check_url(card, block), { response: wrong, client_event_id: id })
    b = post_json(OFFICIAL, check_url(card, block), { response: right, client_event_id: id })
    assert_equal a, b
    assert_equal "wrong", b["verdict"]
    assert_equal 1, LessonEvent.where(kind: "check_answered").count
  end

  test "an answer that cannot be read is not a try and is not stored; a number and a matching are graded by their graders" do
    ncard, nblock, number = find_block { |_, b| b["type"] == "check" && b["component"] == "number" }
    reply = post_json(OFFICIAL, check_url(ncard, nblock), { response: "boh", try: 1, client_event_id: cid })
    assert_equal "invalid", reply["verdict"]
    assert reply["message_it"].present?
    assert_equal 0, LessonEvent.count
    reply = post_json(OFFICIAL, check_url(ncard, nblock), { response: number["answer"].sub(".", ","), try: 1, client_event_id: cid })
    assert_equal "right", reply["verdict"]
    mcard, mblock, matching = find_block { |_, b| b["type"] == "check" && b["component"] == "matching" }
    seed = Lessons::StudentBody.seed_for(@official.key, @lesson_revision.id, mcard, mblock)
    map = Lessons::Checks.id_map(matching, seed)
    shown = matching["answer"].to_h { |l, r| [ map.key(l), map.key(r) ] }
    assert_equal "right", post_json(OFFICIAL, check_url(mcard, mblock), { response: shown, try: 1, client_event_id: cid })["verdict"]
    assert_equal "invalid", post_json(OFFICIAL, check_url(mcard, mblock), { response: "x" * 500, try: 1, client_event_id: cid })["verdict"]
    assert_equal 2, LessonEvent.count
  end

  test "a blank of an example sends the step and what follows only after a right answer or the second try" do
    card, block, example = find_block { |_, b| b["type"] == "example" }
    index = example["steps"].index { |s| s["blank"] }
    url = check_url(card, block, "/#{index + 1}")
    wrong = post_json(OFFICIAL, url, { response: "99", try: 1, client_event_id: cid })
    assert_equal "wrong", wrong["verdict"]
    assert_not wrong.key?("steps")
    right = post_json(OFFICIAL, url, { response: example["steps"][index]["blank"]["answer"], try: 2, client_event_id: cid })
    assert_equal "right", right["verdict"]
    assert_equal example["steps"][index..].map { |s| s["do_it"] }, right["steps"].map { |s| s["do_it"] }
    assert_equal example["result_it"], right["result_it"]
    assert_not right["steps"].first.key?("blank")
    assert_equal [ 1, 2 ], LessonEvent.where(kind: "check_answered").order(:id).map { |r| r.payload["try"] }
    assert_equal [ "step" ], LessonEvent.last.payload.slice("step").keys
    assert_equal index + 1, LessonEvent.last.payload["step"]
    # the second wrong answer of another try sends the rest as well
    again = post_json(OFFICIAL, url, { response: "99", try: 1, client_event_id: cid })
    assert_equal [ "wrong", 3 ], again.values_at("verdict", "try")
    assert again["steps"].present?
  end

  test "an example with two blanks sends the steps up to the next blank, with that blank served and its answer withheld" do
    card, block, example = find_block { |_, b| b["type"] == "example" }
    body = stored_body
    steps = body["cards"].find { |c| c["n"] == card }["blocks"].find { |b| b["n"] == block }["steps"]
    steps[0]["blank"] = { "component" => "number", "prompt_it" => "Quanto fa 1 + 1?", "answer" => "2", "explain_it" => "Uno e uno." }
    last = steps.index { |s| s["blank"] && s != steps[0] }
    pin_body(body)
    reply = post_json(OFFICIAL, check_url(card, block, "/1"), { response: "2", try: 1, client_event_id: cid })
    assert_equal "right", reply["verdict"]
    assert_equal "Uno e uno.", reply["explain_it"]
    assert_equal last + 1, reply["steps"].size, "the steps from the first blank to the second included"
    assert_equal steps[0]["do_it"], reply["steps"][0]["do_it"]
    gate = reply["steps"].last
    assert_not gate.key?("do_it"), "the next blank's result is withheld"
    assert_equal "number", gate.dig("blank", "component")
    assert_not gate["blank"].key?("answer")
    assert_not reply.key?("result_it"), "the result waits for the last blank"
    final = post_json(OFFICIAL, check_url(card, block, "/#{last + 1}"), { response: example["steps"][last]["blank"]["answer"], try: 1, client_event_id: cid })
    assert_equal "right", final["verdict"]
    assert_equal example["result_it"], final["result_it"]
  end

  test "the exercise checks of 'Prova tu' are graded, one or several per exercise" do
    card, block, try = find_block { |_, b| b["type"] == "try" }
    exercise = try["exercises"].find { |e| e["check"] }
    reply = post_json(OFFICIAL, check_url(card, block, "/ex/#{exercise['n']}"), { response: exercise["check"]["answer"], try: 1, client_event_id: cid })
    assert_equal "right", reply["verdict"]
    assert_equal({ "ex" => exercise["n"] }, LessonEvent.last.payload.slice("ex"))
    post_json(OFFICIAL, check_url(card, block, "/ex/99"), { response: "1" })
    assert_response :not_found
    post_json(OFFICIAL, check_url(card, block, "/ex/#{exercise['n']}/2"), { response: "1" })
    assert_response :not_found
  end

  test "a check that is not where the URL says is a 404, whatever it asks" do
    card, block, = choice
    post_json(OFFICIAL, check_url(card, block, "/1"), { response: "a" })
    assert_response :not_found
    ecard, eblock, = find_block { |_, b| b["type"] == "example" }
    post_json(OFFICIAL, check_url(ecard, eblock), { response: "a" })
    assert_response :not_found
    post_json(OFFICIAL, check_url(0, 0), { response: "a" })
    assert_response :not_found
  end

  test "the answer's text is filtered from the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    assert_equal "[FILTERED]", filter.filter({ "response" => "x = 3" })["response"]
    assert_equal "[FILTERED]", filter.filter({ "response" => { "a" => "b" } })["response"]
  end

  # ---- nothing here counts for a skill state -----------------------------------------------------------

  ISOLATED = %w[app/models/practice app/models/diagnosis lib/diagnosis lib/practice app/models/teacher app/models/course app/models/approval].freeze

  test "no practice, diagnosis, course or teacher read model names the lesson ledger" do
    offenders = ISOLATED.flat_map { |dir| Dir[Rails.root.join(dir, "**/*.rb")] }.select { |f| File.read(f).match?(/lesson_events|LessonEvent/) }
    assert_empty offenders.map { |f| f.sub("#{Rails.root}/", "") }
  end

  test "twenty answered checks change neither the skill states nor the practice progress" do
    serve = make_serve(@official, @topic_revision, @revisions.first.instances.first, skill_key: SKILL)
    before = progress_snapshot
    card, block, = choice
    20.times { |i| post_json(OFFICIAL, check_url(card, block), { response: shown_id(@official, card, block, i.odd? ? "b" : "a"), client_event_id: cid }) }
    assert_equal 20, LessonEvent.where(kind: "check_answered").count
    assert_equal before, progress_snapshot
    assert serve.persisted?
  end

  def progress_snapshot
    progress = Teacher::PracticeProgress.new(@subject, @official)
    states = progress.states.transform_values { |s| [ s.state, s.counts ] }
    [ states, progress.topics.map { |t| [ t.topic, t.status, t.skills.map(&:state) ] }, PracticeEvent.count, PracticeServe.count ]
  end
end
