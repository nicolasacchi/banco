require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/docs_family_world"

# The docs family on the server (T8): the oral's outline is graded by the check endpoint as an ordering, its model answer is withheld until the
# outline is right or the second try (L6), the student's body carries the outline shuffled and no key, the source and the reveal are served whole
# (teaching content, L8), and a lesson with these blocks passes the checks of the lesson.
class DocsBlocksTest < ActionDispatch::IntegrationTest
  include MultiUser
  include DocsFamilyWorld

  JSON_HEADERS = { "Content-Type" => "application/json", "Accept" => "application/json" }.freeze

  setup { build_student_world(approve: true, release: true) }

  def post_json(headers, path, body = {})
    on(:web, "/today", headers: headers, remote_addr: EDGE)
    token = css_select("meta[name=csrf-token]").first&.[]("content")
    on(:web, path, method: :post, headers: headers.merge(JSON_HEADERS, "X-CSRF-Token" => token.to_s), params: body.to_json, remote_addr: EDGE)
    response.parsed_body
  end

  def stored = @lesson_revision.reload.body
  def oral = stored["cards"].flat_map { |c| c["blocks"].map { |b| [ c["n"], b["n"], b ] } }.find { |_, _, b| b["type"] == "oral" }
  def check_url(card, block) = "/topics/#{TOPIC}/lesson/checks/#{card}/#{block}"
  def cid = "e-" + SecureRandom.hex(8)

  # The ids the student's page shows for the stored ids, in the order given
  def shown(student, card, block, stored_ids)
    seed = Lessons::StudentBody.seed_for(student.key, @lesson_revision.id, card, block["n"])
    map = Lessons::Checks.id_map(Lessons::Oral.check(block), seed)
    stored_ids.map { |id| map.key(id) }
  end

  test "the gallery lesson passes the checks of the lesson with no finding" do
    outcome = Lesson2Fixtures.check(GALLERY.read, "business")
    assert_empty outcome.findings.map(&:to_h)
  end

  test "the student's body carries the oral's outline shuffled in ids e1..eN and no key, no typical error and no model answer" do
    card, block, b = oral
    served = Lessons::StudentBody.for(@lesson_revision, seed: @official.key)
    body = served["cards"].find { |c| c["n"] == card }["blocks"].find { |x| x["n"] == block }
    assert_equal %w[n type question_it outline connectives terms].sort, body.keys.sort
    assert_equal %w[e1 e2 e3 e4], body["outline"].map { |o| o["id"] }.sort
    assert_equal b["outline"].map { |o| o["text_it"] }.sort, body["outline"].map { |o| o["text_it"] }.sort
    json = JSON.generate(served)
    assert_not_includes json, b["model_it"]
    assert_not_includes json, b["errors"].first["message_it"]
    assert_not_includes json, '"answer"'
    assert_not_equal b["outline"].map { |o| o["text_it"] }, body["outline"].map { |o| o["text_it"] }, "the stored order is not the shown order"
  end

  test "a source and a reveal are served whole: the plain version, the law's words, the marks, the crossroads and what really happened" do
    served = Lessons::StudentBody.for(@lesson_revision, seed: @official.key)
    blocks = served["cards"].flat_map { |c| c["blocks"] }
    source = blocks.find { |b| b["type"] == "source" }
    assert_equal "legal", source["kind"]
    assert_equal "codice-di-prova", source["ref"]
    assert source["parts"].all? { |p| p["plain_it"].present? && p["text_it"].present? }
    assert_equal "creditor", source["parts"][0]["marks"][0]["role"]
    cross = blocks.find { |b| b["type"] == "reveal" && b["options"] }
    assert_equal 3, cross["options"].size
    assert cross["real_it"].present?
    assert_equal [ true ], cross["options"].filter_map { |o| o["real"] }.uniq
    plain = blocks.find { |b| b["type"] == "reveal" && b["prompt_it"] }
    assert plain["answer_it"].present?
  end

  test "a wrong order is a wrong answer with the hint of its typical error and no model; the second wrong order shows the model; the right order shows it at once" do
    card, block, b = oral
    key = b["answer"]
    swapped = [ key[0], key[2], key[1], key[3] ]
    first = post_json(OFFICIAL, check_url(card, block), { response: shown(@official, card, b, swapped), try: 1, client_event_id: cid })
    assert_response :success
    assert_equal "wrong", first["verdict"]
    assert_equal b["errors"].first["message_it"], first["message_it"]
    assert_nil first["model_it"], "the model answer is withheld on the first try"
    second = post_json(OFFICIAL, check_url(card, block), { response: shown(@official, card, b, swapped), try: 2, client_event_id: cid })
    assert_equal "wrong", second["verdict"]
    assert_equal b["model_it"], second["model_it"], "after the second try the model answer is shown"
    right = post_json(OFFICIAL, check_url(card, block), { response: shown(@official, card, b, key), try: 3, client_event_id: cid })
    assert_equal "right", right["verdict"]
    assert_equal b["model_it"], right["model_it"]
    rows = LessonEvent.where(kind: "check_answered", card: card, block: block).order(:id)
    assert_equal %w[wrong wrong right], rows.map { |r| r.payload["verdict"] }
    assert_equal [ "ordering" ], rows.map { |r| r.payload["component"] }.uniq
  end

  test "the right order on the first try shows the model answer at once" do
    card, block, b = oral
    reply = post_json(OFFICIAL, check_url(card, block), { response: shown(@official, card, b, b["answer"]), try: 1, client_event_id: cid })
    assert_equal "right", reply["verdict"]
    assert_equal b["model_it"], reply["model_it"]
  end

  test "an outline with an id the page never showed, or with one element missing, is not an answer and not a try" do
    card, block, b = oral
    [ %w[e1 e2 e3 e9], %w[e1 e2 e3], %w[e1 e1 e2 e3], [] ].each do |response|
      reply = post_json(OFFICIAL, check_url(card, block), { response: response, try: 1, client_event_id: cid })
      assert_equal "invalid", reply["verdict"], response.inspect
      assert_nil reply["model_it"]
    end
    assert_equal 0, LessonEvent.where(kind: "check_answered", card: card, block: block).count
    assert b
  end

  test "the typical error of the outline is found whatever order the page showed" do
    card, block, b = oral
    err = b["errors"].first["answer"]
    reply = post_json(TRIAL, check_url(card, block), { response: shown(@trial, card, b, err), try: 1, client_event_id: cid })
    assert_equal "wrong", reply["verdict"]
    assert_equal b["errors"].first["message_it"], reply["message_it"]
  end

  test "the teacher's full body keeps the key and the model answer, and the teacher's box grades the outline with the seed \"preview\" and records nothing" do
    card, block, b = oral
    on(:web, "/teacher/lesson-revisions/#{@lesson_revision.id}/full.json", headers: TEACHER, remote_addr: EDGE)
    assert_response :success
    full = response.parsed_body["cards"].find { |c| c["n"] == card }["blocks"].find { |x| x["n"] == block }
    assert_equal b["answer"], full["answer"]
    assert_equal b["model_it"], full["model_it"]
    map = Lessons::Checks.id_map(Lessons::Oral.check(b), Lessons::StudentBody.seed_for("preview", @lesson_revision.id, card, block))
    reply = post_json(TEACHER, "/teacher/lesson-revisions/#{@lesson_revision.id}/checks/#{card}/#{block}", { response: b["answer"].map { |id| map.key(id) }, try: 1 })
    assert_equal "right", reply["verdict"]
    assert_equal b["model_it"], reply["model_it"]
    assert_equal 0, LessonEvent.count
  end
end
