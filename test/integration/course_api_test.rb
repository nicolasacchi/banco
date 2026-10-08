require "test_helper"
require_relative "../support/validation_fixtures"
require_relative "../support/course_rows"
require_relative "../support/lesson_md"
require_relative "../support/practice_rows"

# The course over the agent API (Phase 1b, S1b): map, lessons, lesson reviews, topics, status, practice progress.
# Invented content only. Nothing here decides: the teacher approves in the browser (approve_topic rows are made
# directly, as the decision tests do).
class CourseApiTest < ActionDispatch::IntegrationTest
  include CourseRows
  include PracticeRows
  L = LessonMd
  SKILL = "math.linear-equation-integer".freeze
  NEW_SKILL = "math.linear-system-substitution".freeze

  setup do
    @token = ApiToken.issue!(role: "agent_claude", label: "course test")
    build_course
    @prima = SyllabusSource.create!(key: "prima-2025-26", line_count: 2, sha256: "2" * 64)
    SyllabusLine.create!(syllabus_source: @prima, number: 1, text: "equazioni di primo grado", origin: "pdf")
    SyllabusLine.create!(syllabus_source: @prima, number: 2, text: "PAGINA 2", origin: "transcript")
    @seconda = SyllabusSource.create!(key: "seconda-2025-26", line_count: 2, sha256: "3" * 64)
    SyllabusLine.create!(syllabus_source: @seconda, number: 1, text: "sistemi lineari: metodo di sostituzione", origin: "pdf")
    SyllabusLine.create!(syllabus_source: @seconda, number: 2, text: "equazioni di primo grado numeriche intere", origin: "pdf")
    @author = session!(:author, "claude-opus-5-5")
    @reviewer = session!(:reviewer, "gpt-5.2")
  end

  def session!(role, model) = AgentSession.create!(label: "t", role: role.to_s, agent: "test", model: model)

  def api(path, method: :get, body: nil, as: nil, dry: false)
    headers = { "Authorization" => "Bearer #{@token}" }
    headers["X-Banco-Session"] = as.id.to_s if as
    headers["X-Banco-Dry-Run"] = "1" if dry
    on(:api, path, method: method, headers: headers, params: body, as: body ? :json : nil)
  end

  def json = response.parsed_body

  # ---- documents ----------------------------------------------------------------------------

  def course_doc(&edit)
    doc = {
      "schema" => "banco.course/1", "schema_version" => 1, "subject" => "math", "notes_it" => [ "Un esempio inventato." ],
      "skills" => [ {
        "key" => NEW_SKILL, "label_it" => "Sistemi lineari: sostituzione", "layer" => "core", "prerequisites" => [ SKILL ],
        "refs" => [ { "source" => "seconda-2025-26", "line" => 1, "fragment" => "metodo di sostituzione", "role" => "taught_in" } ],
        "errors" => [ { "code" => "subst_no_brackets", "description_it" => "Sostituisce senza parentesi.", "implicates" => [ "math.integer-operations" ] } ]
      } ],
      "topics" => [
        { "key" => "ripasso.math.demo-equations", "kind" => "ripasso", "title_it" => "Equazioni di primo grado", "term" => 1, "minutes" => 45, "skills" => [ SKILL ], "after" => [] },
        { "key" => "lezione.math.demo-systems", "kind" => "lezione", "title_it" => "Sistemi lineari", "term" => 2, "minutes" => 45, "skills" => [ NEW_SKILL ], "after" => [ "ripasso.math.demo-equations" ] }
      ]
    }
    edit&.call(doc)
    doc
  end

  def submit_course(doc = course_doc, dry: false) = api("/api/v1/subjects/math/course", method: :post, body: { course: doc }, as: @author, dry: dry)

  def ripasso_md(**opts) = L.build(front: { "skills" => [ SKILL ], "uses" => [ "math.integer-operations" ] }.merge(opts.delete(:front) || {}), **opts)

  def lezione_md
    L.build(front: { "kind" => "lezione", "key" => "lezione.math.demo-systems", "scope" => "seconda", "skills" => [ NEW_SKILL ], "uses" => [],
                     "refs" => [ { "source" => "seconda-2025-26", "line" => 1, "fragment" => "metodo di sostituzione", "role" => "taught_in" } ] })
  end

  def submit_lesson(md, key: "ripasso.math.demo-equations", base: nil, as: @author, dry: false)
    api("/api/v1/lessons/submit", method: :post, body: { lesson: key, base: base, files: { "lesson.md" => md } }, as: as, dry: dry)
  end

  def checklist(prefix = "Ricontrollato l'esercizio")
    (1..8).map { |i| { "id" => i, "result" => "pass", "evidence" => "#{prefix} numero #{i} con il calcolo esatto, nessun difetto." } }
  end

  def review_doc(revision, recomputed: nil, findings: [])
    recomputed ||= (1..8).map { |i| { "where" => "solutions", "n" => (i % 4) + 1, "expression" => "#{i} + #{i}", "value" => (i * 2).to_s } }
    { "schema" => "banco.lesson_review/1", "schema_version" => 1, "revision" => revision.id.to_s, "checklist" => checklist, "recomputed" => recomputed, "findings" => findings }
  end

  def review_lesson(revision, doc = nil, as: @reviewer, dry: false)
    api("/api/v1/lesson-revisions/#{revision.id}/review", method: :post, body: { review: doc || review_doc(revision) }, as: as, dry: dry)
  end

  def topic_doc(items_by_skill, lesson_revision: "latest", key: "ripasso.math.demo-equations")
    { "schema" => "banco.topic/1", "schema_version" => 1, "subject" => "math", "key" => key, "lesson_revision" => lesson_revision,
      "practice" => items_by_skill.map { |skill, items| { "skill" => skill, "items" => items.map { |i, r| { "item" => i, "revision" => r || "latest" } } } } }
  end

  def submit_topic(doc, as: @author, dry: false) = api("/api/v1/topics/#{doc['key']}", method: :post, body: { topic: doc }, as: as, dry: dry)

  # A ripasso lesson, a course map, and two practice items (24 instances) on SKILL; returns the lesson revision.
  def world
    assert_equal 201, submit_course.then { response.status }, json.inspect
    submit_lesson(ripasso_md)
    assert_response :created, json.inspect
    @lesson_revision = LessonRevision.find(json["revision_id"])
    @item_a = make_practice_item("math-p-demo-1", SKILL, level: 1)
    @item_b = make_practice_item("math-p-demo-2", SKILL, level: 2)
    @lesson_revision
  end

  # ---- the course map ---------------------------------------------------------------------------

  test "status without a map says so" do
    api("/api/v1/status")
    assert_equal "corso: nessuna mappa", json["subjects"].first.dig("course", "line_it")
  end

  test "course open without a map, submit, replay, and a dry run that stores nothing" do
    api("/api/v1/subjects/math/course")
    assert_response :ok
    assert_nil json["revision"]
    assert_equal "course", json.dig("brief", "name")
    submit_course(dry: true)
    assert_response :ok
    record_example "course submit", "dry-run-passed"
    assert_equal 0, CourseRevision.count
    submit_course
    assert_response :created, json.inspect
    record_example "course submit", "created"
    assert_equal false, json["replayed"]
    submit_course
    assert_response :ok
    assert_equal true, json["replayed"]
    assert_equal 1, CourseRevision.count
    api("/api/v1/subjects/math/course")
    record_example "course open", "with-map"
    assert_equal 2, json.dig("revision", "course", "topics").size
    assert_equal false, json.dig("revision", "graph_stale")
    assert_nil json["released_revision_id"]
  end

  test "a newer graph makes the map stale at read time; a re-submit against it is a new revision" do
    submit_course
    graph = SkillGraphRevision.create!(subject: @subject, seq: 2, body_json: JSON.generate(@graph_doc))
    api("/api/v1/subjects/math/course")
    assert_equal true, json.dig("revision", "graph_stale")
    assert_includes json.dig("revision", "warnings").map { |w| w["code"] }, "W-COURSE-GRAPH-STALE"
    api("/api/v1/status")
    assert_equal true, json["subjects"].find { |s| s["key"] == "math" }.dig("course", "revision", "graph_stale")
    submit_course
    assert_response :created
    assert_equal graph.id, json["skill_graph_revision_id"]
    api("/api/v1/subjects/math/course")
    assert_equal false, json.dig("revision", "graph_stale")
  end

  test "a course map is refused with the code of its fault" do
    {
      "E-COURSE-SKILL-DUPLICATE" => ->(d) { d["skills"][0]["key"] = SKILL },
      "E-COURSE-TOPIC" => ->(d) { d["topics"][1]["after"] = [ "ripasso.math.nope" ] },
      "E-SKILL-UNKNOWN" => ->(d) { d["skills"][0]["prerequisites"] = [ "math.not-a-skill" ] },
      "E-SOURCE" => ->(d) { d["skills"][0]["refs"][0]["fragment"] = "non esiste" },
      "E-GRAPH-CYCLE" => ->(d) { d["skills"][0]["prerequisites"] = [ NEW_SKILL ] },
      "E-SCHEMA" => ->(d) { d["topics"][0]["term"] = 4 }
    }.each do |code, edit|
      submit_course(course_doc(&edit))
      assert_response :unprocessable_entity, code
      assert_equal code, json["code"]
      record_example "course submit", "cycle" if code == "E-GRAPH-CYCLE"
    end
    assert_equal 0, CourseRevision.count
  end

  test "an ordering warning is returned and stored" do
    submit_course(course_doc { |d| d["topics"].reverse! })
    assert_response :created, json.inspect
    assert_includes json["warnings"].map { |w| w["code"] }, "W-COURSE-ORDER"
  end

  test "a course map needs a graph" do
    Subject.create!(key: "italian", name_it: "Italiano", position: 2)
    api("/api/v1/subjects/italian/course", method: :post, body: { course: course_doc.merge("subject" => "italian") }, as: @author)
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
  end

  # ---- lessons ----------------------------------------------------------------------------------

  test "lesson submit: dry run, created, replay, stale base" do
    submit_lesson(ripasso_md, dry: true)
    assert_response :ok, json.inspect
    assert_equal 0, LessonRevision.count
    record_example "lesson submit", "dry-run-passed"
    submit_lesson(ripasso_md)
    assert_response :created, json.inspect
    record_example "lesson submit", "created"
    first = json["revision_id"]
    submit_lesson(ripasso_md, base: first)
    assert_response :ok
    assert_equal true, json["replayed"]
    changed = ripasso_md(sections: { "idea_it" => "Una equazione è come una bilancia. Quello che fai a un lato, lo fai anche all'altro." })
    submit_lesson(changed)
    assert_response :conflict
    assert_equal "E-STALE-BASE", json["code"]
    submit_lesson(changed, base: first)
    assert_response :created
    assert_equal 2, json["seq"]
    assert_equal first, LessonRevision.find(json["revision_id"]).base_revision_id
  end

  test "lesson submit: each fault answers with its code" do
    {
      "E-LESSON-PARSE" => ripasso_md.sub(/\A---\n/, ""),
      "E-LESSON-SECTIONS" => ripasso_md(drop: [ "idea_it" ]),
      "E-LESSON-MARKUP" => ripasso_md(sections: { "idea_it" => "Il valore x^2 è grande." }),
      "E-LESSON-EXERCISES" => ripasso_md(sections: { "try" => "1. Uno.\n2. Due.", "solutions" => "1. Uno.\n2. Due." }),
      "E-SKILL-UNKNOWN" => ripasso_md(front: { "skills" => [ "math.not-a-skill" ] })
    }.each do |code, md|
      submit_lesson(md)
      assert_response :unprocessable_entity, code
      assert_equal code, json["code"]
      record_example "lesson submit", "markup-refused" if code == "E-LESSON-MARKUP"
    end
    assert_equal 0, Lesson.count
  end

  test "lesson submit: transport faults" do
    submit_lesson(ripasso_md, key: "ripasso.math.other-key")
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
    api("/api/v1/lessons/submit", method: :post, body: { lesson: "ripasso.math.demo-equations", files: { "other.md" => "x" } }, as: @author)
    assert_equal "E-FILES", json["code"]
    submit_lesson("x" * (Validation::Rules.get(:lesson, :max_bytes) + 1))
    assert_response 413
    assert_equal "E-TOO-LARGE", json["code"]
    submit_lesson(ripasso_md, key: "ripasso.nowhere.demo-equations")
    assert_response :not_found
  end

  test "lessons list, lesson open and lesson status" do
    world
    api("/api/v1/subjects/math/lessons")
    assert_response :ok
    row = json["rows"].find { |r| r["lesson"] == "ripasso.math.demo-equations" }
    record_example "lessons list", "rows"
    assert_equal @lesson_revision.id, row["latest_revision_id"]
    assert_equal true, row["in_course_map"]
    assert_equal 0, row["reviews"]
    assert_equal false, row["sent_back"]
    api("/api/v1/lessons/ripasso.math.demo-equations")
    assert_response :ok
    record_example "lesson open", "opened"
    assert_equal @lesson_revision.source_md, json.dig("files", "lesson.md")
    assert_equal [], json["reviews"]
    api("/api/v1/lessons/ripasso.math.no-such-lesson")
    assert_response :not_found
    api("/api/v1/lesson-revisions/#{@lesson_revision.id}")
    assert_response :ok
    record_example "lesson status", "fresh"
    assert_equal false, json["superseded"]
    api("/api/v1/lesson-revisions/999999")
    assert_response :not_found
  end

  test "a send_back_lesson decision shows in the comments and the list" do
    world
    Decision.create!(kind: "send_back_lesson", subject: @subject, request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1",
                     payload_json: JSON.generate(lesson_revision_id: @lesson_revision.id, lesson: @lesson_revision.lesson.key, seq: 1, reason_code: "off_programme", comment_it: "Fuori programma."))
    api("/api/v1/lessons/ripasso.math.demo-equations")
    assert_equal "Fuori programma.", json["teacher_comments"].first["comment_it"]
    api("/api/v1/subjects/math/lessons")
    assert_equal true, json["rows"].first["sent_back"]
  end

  # ---- lesson review ------------------------------------------------------------------------------

  test "lesson review: open, dry run, submit; one review per session; the author cannot review" do
    world
    api("/api/v1/lesson-revisions/#{@lesson_revision.id}/review", as: @reviewer)
    assert_response :ok, json.inspect
    record_example "lesson-review open", "opened"
    assert_equal 8, json["checklist"].size
    assert_equal "equazioni di primo grado", json["programme_lines"].find { |l| l["source"] == "prima-2025-26" }["text"]
    assert_equal SKILL, json["skills"].first["key"]
    assert_equal "graph", json["skills"].first["source"]
    assert_equal [ "math.integer-operations" ], json["uses"].map { |u| u["key"] }
    review_lesson(@lesson_revision, dry: true)
    assert_response :ok, json.inspect
    assert_equal 0, LessonReview.count
    review_lesson(@lesson_revision)
    assert_response :created, json.inspect
    record_example "lesson-review submit", "created"
    review_lesson(@lesson_revision)
    assert_response :unprocessable_entity
    assert_equal "E-SESSION-NOT-INDEPENDENT", json["code"]
    review_lesson(@lesson_revision, as: @author)
    assert_equal "E-SESSION-ROLE", json["code"]
    api("/api/v1/lessons/ripasso.math.demo-equations")
    assert_equal 1, json["reviews"].size
    assert_equal({ "pass" => 8, "fail" => 0, "na" => 0 }, json["reviews"].first["results"])
  end

  test "lesson and topic submit need an author session, also in a dry run" do
    world
    doc = topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-demo-2", nil ] ] })
    [ ->(**o) { submit_lesson(ripasso_md, **o) }, ->(**o) { submit_topic(doc, **o) } ].each do |submit|
      [ true, false ].each do |dry|
        submit.call(as: nil, dry: dry)
        assert_response :unprocessable_entity
        assert_equal "E-SESSION", json["code"]
        submit.call(as: @reviewer, dry: dry)
        assert_equal "E-SESSION-ROLE", json["code"]
      end
    end
    assert_equal 1, LessonRevision.count
    assert_equal 0, TopicRevision.count
  end

  test "a reviewer on the author's model is refused, and so is a session that wrote the lesson" do
    world
    same_model = session!(:reviewer, "claude-opus-5-5")
    review_lesson(@lesson_revision, as: same_model)
    assert_response :unprocessable_entity
    assert_equal "E-PROVIDER-NOT-ALLOWED", json["code"]
    # The same session row cannot hold two roles, so the author conflict is checked on the sessions book.
    assert_equal [ "author" ], LessonSessions.new(@lesson_revision.lesson).conflicts(@author.id, "reviewer")
  end

  test "lesson review: faults answer with their codes" do
    world
    review_lesson(@lesson_revision, review_doc(@lesson_revision, findings: [ { "severity" => "major", "section" => "idea", "quote" => "una frase che non c'e", "problem_it" => "Non va.", "fix_it" => "Cambia." } ]))
    assert_equal "E-QUOTE-NOT-FOUND", json["code"]
    review_lesson(@lesson_revision, review_doc(@lesson_revision, recomputed: []))
    assert_equal "E-LESSON-REVIEW-RECOMPUTED", json["code"]
    review_lesson(@lesson_revision, review_doc(@lesson_revision, recomputed: (1..8).map { |i| { "where" => "solutions", "n" => 1, "expression" => "#{i}", "value" => "#{i}" } }))
    assert_equal "E-LESSON-REVIEW-RECOMPUTED", json["code"]
    doc = review_doc(@lesson_revision)
    doc["checklist"].each { |c| c["evidence"] = "tutto verificato" }
    review_lesson(@lesson_revision, doc)
    assert_equal "E-REVIEW-EMPTY", json["code"]
    doc = review_doc(@lesson_revision)
    doc["checklist"].pop
    review_lesson(@lesson_revision, doc)
    assert_equal "E-SCHEMA", json["code"]
    bad = review_doc(@lesson_revision).merge("revision" => "999999")
    review_lesson(@lesson_revision, bad)
    assert_equal "E-FILES", json["code"]
    assert_equal 0, LessonReview.count
  end

  test "a review of a superseded lesson revision cannot be filed" do
    world
    submit_lesson(ripasso_md(sections: { "idea_it" => "Una equazione è come una bilancia. Quello che fai a un lato, lo fai anche all'altro." }), base: @lesson_revision.id)
    review_lesson(@lesson_revision)
    assert_response :conflict
    assert_equal "E-STALE-BASE", json["code"]
  end

  # ---- topics, status, progress --------------------------------------------------------------------

  def worked!(revision)
    reviewer = session!(:reviewer, "gpt-5.2")
    solver = session!(:solver, "kimi-k3")
    ItemReview.create!(item_revision: revision, agent_session: reviewer, checklist_json: "[]")
    BlindSolve.create!(item_revision: revision, agent_session: solver, answers_json: "[]", results_json: "[]")
  end

  test "topic submit pins latest, stores integers, replays, and the list walks missing -> in_review -> awaiting_teacher" do
    world
    api("/api/v1/subjects/math/topics")
    assert_equal %w[missing missing], json["rows"].map { |r| r["stage"] }
    assert_equal [ 1, 2 ], json["rows"].map { |r| r["position"] }
    doc = topic_doc({ SKILL => [ [ "math-p-demo-1" ], [ "math-p-demo-2" ] ].map(&:first).zip([ nil, nil ]) })
    submit_topic(doc, dry: true)
    assert_response :ok, json.inspect
    assert_equal @lesson_revision.id, json.dig("stored", "lesson_revision")
    assert_equal [ @item_a.id, @item_b.id ], json.dig("stored", "practice", 0, "items").map { |i| i["revision"] }
    record_example "topic submit", "dry-run-passed"
    assert_equal 0, TopicRevision.count
    submit_topic(doc)
    assert_response :created, json.inspect
    record_example "topic submit", "created"
    submit_topic(doc)
    assert_response :ok
    assert_equal true, json["replayed"]
    api("/api/v1/subjects/math/topics")
    row = json["rows"].first
    record_example "topics list", "rows"
    assert_equal "in_review", row["stage"]
    assert_includes row["gate_reasons"].join(" "), "no review by an independent session"
    review_lesson(@lesson_revision)
    assert_response :created
    [ @item_a, @item_b ].each { |r| worked!(r) }
    api("/api/v1/subjects/math/topics")
    assert_equal "awaiting_teacher", json["rows"].first["stage"], json["rows"].first["gate_reasons"].inspect
    api("/api/v1/topics/ripasso.math.demo-equations")
    assert_response :ok
    record_example "topic open", "opened"
    assert_equal "awaiting_teacher", json["stage"]
    assert_equal @lesson_revision.id, json.dig("lesson", "pinned")
    assert_equal 2, json.dig("latest", "topic", "practice", 0, "items").size
  end

  test "approved, approved_newer_pending, stale pins and a sent-back lesson show in the stage" do
    world
    submit_topic(topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-demo-2", nil ] ] }))
    first = TopicRevision.find(json["revision_id"])
    review_lesson(@lesson_revision)
    [ @item_a, @item_b ].each { |r| worked!(r) }
    approve = ->(rev) { Decision.create!(kind: "approve_topic", subject: @subject, request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1", payload_json: JSON.generate(topic_revision_id: rev.id, topic: "ripasso.math.demo-equations", seq: rev.seq)) }
    approve.call(first)
    api("/api/v1/subjects/math/topics")
    assert_equal "approved", json["rows"].first["stage"]
    assert_equal first.id, json["rows"].first["approved_revision_id"]
    # A new lesson revision makes the pin stale; a new topic revision is newer than the approval.
    submit_lesson(ripasso_md(sections: { "idea_it" => "Una equazione è come una bilancia. Quello che fai a un lato, lo fai anche all'altro." }), base: @lesson_revision.id)
    submit_topic(topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-demo-2", nil ] ] }))
    assert_response :created
    api("/api/v1/subjects/math/topics")
    assert_equal "approved_newer_pending", json["rows"].first["stage"]
    # Item pins: a newer passed revision of an item is a stale pin.
    newer = ItemRevision.create!(item: @item_a.item, seq: 2, body_json: @item_a.body_json, file_sessions_json: "{}")
    ItemValidation.create!(item_revision: newer, seq: 1, status: "passed", codes_json: "[]")
    api("/api/v1/topics/ripasso.math.demo-equations")
    assert_equal [ @item_a.id ], json["stale_pins"].map { |p| p["pinned"] }
    assert_equal newer.id, json["stale_pins"].first["newest_passed"]
  end

  test "topic submit: each fault answers with its code" do
    world
    ok_items = [ [ "math-p-demo-1", nil ], [ "math-p-demo-2", nil ] ]
    diagnosis = make_revision("math-d-1", SKILL)
    short = make_practice_item("math-p-short", SKILL, instances: 3)
    other_skill = make_practice_item("math-p-other", "math.percentages", level: 1)
    failed = make_practice_item("math-p-failed", SKILL, status: "failed")
    level2_only = make_practice_item("math-p-l2", SKILL, level: 2)
    cases = {
      "E-TOPIC-UNKNOWN" => topic_doc({ SKILL => ok_items }, key: "ripasso.math.not-in-the-map"),
      "E-TOPIC-PIN" => topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-nothing", nil ] ] }),
      "E-TOPIC-SKILLS" => topic_doc({ "math.percentages" => ok_items }),
      "E-TOPIC-ITEM-KIND" => topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-d-1", nil ] ] }),
      "E-TOPIC-POOL" => topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-short", nil ] ] }.merge({})),
      "E-ITEM-NOT-PASSED" => topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-failed", failed.id ] ] }),
      "E-SCHEMA" => topic_doc({ SKILL => [ [ "math-p-demo-1", nil ] ] })
    }
    cases.each do |code, doc|
      submit_topic(doc, dry: true)
      assert_response :unprocessable_entity, "#{code}: #{json.inspect}"
      assert_equal code, json["code"], json.inspect
    end
    # level 1 missing: two level 2 items
    submit_topic(topic_doc({ SKILL => [ [ "math-p-demo-2", nil ], [ "math-p-l2", nil ] ] }), dry: true)
    assert_equal "E-TOPIC-POOL", json["code"]
    assert_includes json["findings"].map { |f| f["message"] }.join, "level 1"
    assert_equal 0, TopicRevision.count
    submit_topic(topic_doc({ SKILL => ok_items }, key: "lezione.math.demo-systems"), dry: true)
    assert_equal "E-TOPIC-PIN", json["code"] # the lezione has no lesson yet
    other_skill
  end

  test "topic submit: a topic whose key differs from the path is E-FILES" do
    world
    api("/api/v1/topics/lezione.math.demo-systems", method: :post, body: { topic: topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-demo-2", nil ] ] }) }, as: @author)
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
  end

  test "stale pins warn and a pin on an older passed revision is stored as asked" do
    world
    newer = ItemRevision.create!(item: @item_a.item, seq: 2, body_json: @item_a.body_json, file_sessions_json: "{}")
    ItemValidation.create!(item_revision: newer, seq: 1, status: "passed", codes_json: "[]")
    12.times { |i| ItemInstance.create!(item_revision: newer, seed: i + 1, display_json: "{}", answer_json: "\"1\"", fingerprint: Digest::SHA256.hexdigest("n#{i}")) }
    submit_topic(topic_doc({ SKILL => [ [ "math-p-demo-1", @item_a.id ], [ "math-p-demo-2", nil ] ] }), dry: true)
    assert_response :ok
    assert_includes json["warnings"].map { |w| w["code"] }, "W-STALE-PIN"
  end

  test "status carries the course block and practice progress carries no student text" do
    world
    submit_topic(topic_doc({ SKILL => [ [ "math-p-demo-1", nil ], [ "math-p-demo-2", nil ] ] }))
    api("/api/v1/status")
    record_example "status", "course-block"
    course = json["subjects"].find { |s| s["key"] == "math" }["course"]
    assert_equal({ "in_map" => 2, "missing" => 1, "in_review" => 1, "awaiting_teacher" => 0, "approved" => 0, "approved_newer_pending" => 0 }, course["topics"])
    assert_equal({ "total" => 1, "unreviewed" => 1, "sent_back" => 0 }, course["lessons"])
    assert_equal 2, course["practice_items"]["total"]
    assert_equal 2, course["practice_items"]["passed"]
    assert_equal false, course["released"]
    assert_equal "corso: 1 in revisione, 1 da scrivere (2 nella mappa) · chiuso allo studente", course["line_it"]
    student = practice_student("student")
    topic = TopicRevision.last
    instance = @item_a.instances.first
    serve = make_serve(student, topic, instance, skill_key: SKILL)
    make_try(serve, raw: "SECRET-ANSWER", verdict: "wrong", error_codes: [ "sign_error" ])
    api("/api/v1/subjects/math/practice/progress")
    assert_response :ok
    record_example "practice progress", "official"
    row = json["skills"].find { |s| s["skill"] == SKILL }
    assert_equal "in_study", row["state"]
    assert_equal({ "sign_error" => 1 }, row["typical"])
    assert_equal 1, row["counts"]["wrong"]
    assert_not_includes response.body, "SECRET-ANSWER"
    assert_equal false, json["trial"]
    api("/api/v1/subjects/math/practice/progress?student=nobody")
    assert_response :not_found
    practice_student("trial-1")
    api("/api/v1/subjects/math/practice/progress?student=trial-1")
    assert_response :ok
    assert_equal true, json["trial"]
  end

  test "no route of the course writes a decision" do
    Rails.application.routes.routes.map { |r| r.path.spec.to_s }.grep(%r{\A/api/v1/(lessons|lesson-revisions|topics|subjects/:subject/(course|lessons|topics|practice))}).each do |path|
      assert_no_match(/approve|release|decision|send-back/, path)
    end
  end
end
