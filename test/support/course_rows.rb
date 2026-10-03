# Rows of a tiny synthetic course for API tests: a subject, a graph revision, a
# programme source with lines and a reference text.
module CourseRows
  def build_course(subject_key: "math", position: 1)
    @subject = Subject.find_by(key: subject_key) || Subject.create!(key: subject_key, name_it: subject_key.humanize, position: position)
    @graph_doc = ValidationFixtures::GRAPH
    @graph = SkillGraphRevision.create!(subject: @subject, seq: 1, body_json: JSON.generate(@graph_doc))
    @source = SyllabusSource.create!(key: "prima-test", line_count: 2, sha256: "0" * 64)
    SyllabusLine.create!(syllabus_source: @source, number: 1, text: "operazioni con i numeri relativi", origin: "pdf")
    SyllabusLine.create!(syllabus_source: @source, number: 2, text: "PAGINA 2", origin: "transcript")
    seconda = SyllabusSource.create!(key: "seconda-test", line_count: 1, sha256: "1" * 64)
    SyllabusLine.create!(syllabus_source: seconda, number: 1, text: "equazioni di primo grado", origin: "pdf")
    ReferenceText.create!(key: "ref-test", title: "Testo di prova", source_url: "https://example.org/prova", sha256: "0" * 64,
                          body: ValidationFixtures::REFERENCE["ref-test"])
    @subject
  end

  # An approved graph (what the teacher's decision will make in M9).
  def approve_graph!(subject, revision)
    Decision.create!(kind: "approve_skill_graph", subject: subject, payload_json: JSON.generate(revision_id: revision.id),
                     request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1")
  end

  def approve_blueprint!(subject, revision)
    Decision.create!(kind: "approve_blueprint", subject: subject, payload_json: JSON.generate(revision_id: revision.id),
                     request_id: SecureRandom.hex(4), teacher_login: "teacher", remote_addr: "127.0.0.1")
  end

  # An item revision with a validation row and n instances, without going through
  # the job: the shape the blueprint checks read.
  def make_revision(key, skill, status: "passed", instances: 4, component: "number", subject: nil)
    subject ||= @subject
    item = Item.create!(subject: subject, key: key, kind: "diagnosis_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "diagnosis_item", subject: subject.key, skill: skill, component: component, expected_seconds: 60 }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: status, codes_json: "[]") if status
    instances.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: "#{key} #{i}"), answer_json: JSON.generate("1"),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end
end
