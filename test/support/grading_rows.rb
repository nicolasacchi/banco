# Builds an item revision, one instance and attempts on it from a banco.item/1
# fixture, for the tests that grade stored rows.
module GradingRows
  FIXTURES = Rails.root.join("test/fixtures/content/item/good")

  def item_body(name) = JSON.parse(File.read(FIXTURES.join("#{name}.json")))

  # body: the item.json hash; instance: one entry of body["instances"] (or a hash
  # with display/answer/errors for generator items).
  def create_instance(body, instance = body["instances"].first)
    @grading_counter = (@grading_counter || 0) + 1
    n = @grading_counter
    session = AgentSession.create!(label: "s#{n}", role: "author")
    subject = Subject.find_or_create_by!(key: body["subject"]) { |s| s.name_it = body["subject"]; s.position = n }
    item = Item.create!(subject: subject, key: "item-#{n}-#{SecureRandom.hex(3)}", kind: body["component"] || "short_answer")
    revision = ItemRevision.create!(item: item, seq: 1, body_json: body.to_json, author_session: session,
                                    file_sessions_json: "{}", brief_sha256: "0" * 64)
    ItemInstance.create!(item_revision: revision, seed: n, display_json: instance["display"].to_json,
                         answer_json: instance["answer"].to_json, errors_json: Array(instance["errors"]).to_json,
                         fingerprint: SecureRandom.hex(32))
  end

  def create_attempt(instance, raw, source: "text")
    @grading_counter = (@grading_counter || 0) + 1
    student = Student.find_or_create_by!(key: "student") { |s| s.kind = "student" }
    Attempt.create!(student: student, context: "teacher_preview", client_attempt_id: "c-#{@grading_counter}-#{SecureRandom.hex(4)}",
                    item_instance: instance, raw: raw, source: source, answered_at: Time.current)
  end
end
