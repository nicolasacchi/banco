require_relative "validation_fixtures"

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

  # ---- Phase 1b: the course (invented look-alikes only; nothing of a real programme) ----

  COURSE_LINES = [
    "equazioni di primo grado numeriche intere",
    "sistemi lineari: metodo di sostituzione"
  ].freeze

  # An invented seconda programme source with citable lines, and a course map revision
  # on the subject's latest graph. skills: [{key:, label_it:, ...}] (course skills, not in the graph).
  def build_course_map(subject: @subject, skills: nil, topics: nil)
    source = SyllabusSource.find_by(key: "seconda-test") || SyllabusSource.create!(key: "seconda-test", line_count: COURSE_LINES.size, sha256: "1" * 64)
    COURSE_LINES.each_with_index { |text, i| SyllabusLine.find_or_create_by!(syllabus_source: source, number: i + 1) { |l| l.text = text; l.origin = "pdf" } }
    graph = SkillGraphRevision.where(subject: subject).order(:seq).last
    skills ||= [ { key: "#{subject.key}.linear-system-substitution", label_it: "Sistemi lineari: sostituzione", layer: "core",
                   prerequisites: [], refs: [ { source: "seconda-test", line: 2, fragment: "metodo di sostituzione", role: "taught_in" } ], errors: [] } ]
    topics ||= [ { key: "lezione.#{subject.key}.linear-systems", kind: "lezione", title_it: "Sistemi lineari", skills: skills.map { |k| k[:key] }, minutes: 30, term: 1, after: [] } ]
    body = { schema: "banco.course/1", schema_version: 1, subject: subject.key, skills: skills, topics: topics }
    CourseRevision.create!(subject: subject, seq: (CourseRevision.where(subject: subject).maximum(:seq) || 0) + 1,
                           skill_graph_revision: graph, body_json: JSON.generate(body), warnings_json: "[]")
  end

  # A lesson (the topic's identity) with one revision.
  def make_lesson(key = "ripasso.math.demo", skills: [ "math.skill-a" ], title_it: "Lezione di prova")
    kind, subject_key, = key.split(".", 3)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: subject_key), key: key, kind: kind)
    seq = (lesson.revisions.maximum(:seq) || 0) + 1
    md = "---\nkey: #{key}\n---\n\n## Perche ti serve\nUna lezione di prova.\n"
    LessonRevision.create!(lesson: lesson, seq: seq, source_md: md, source_sha256: Digest::SHA256.hexdigest(md),
                           body_json: JSON.generate(key: key, kind: kind, title_it: title_it, skills: skills), rules_version: Validation::Rules.version.to_s,
                           warnings_json: "[]")
  end

  # A practice item revision with n instances, each with effective hints stored apart from the display.
  def make_practice_item(key, skill, instances: 12, component: "number", status: "passed", level: 1, subject: nil, hints: [ "Che cosa guardi prima?", "Quale regola usi?", "Fai il primo passaggio." ])
    subject ||= @subject
    item = Item.create!(subject: subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: subject.key, skill: skill, component: component,
             level: level, expected_seconds: 60, hints_it: hints }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: status, codes_json: "[]") if status
    instances.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: "#{key} #{i}"), answer_json: JSON.generate((i + 2).to_s),
                           errors_json: JSON.generate([ { code: "slip", value: (i + 3).to_s } ]), hints_json: JSON.generate(hints),
                           solution_json: JSON.generate(steps: [ { text_it: "Passo.", math: "$x$" } ], final: "$x$"),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  # A topic revision for a lesson, pinning the given practice item revisions per skill.
  def make_topic(lesson_revision, items_by_skill, course: nil)
    course ||= CourseRevision.where(subject: lesson_revision.lesson.subject).order(:seq).last || build_course_map(subject: lesson_revision.lesson.subject)
    practice = items_by_skill.map { |skill, revs| { skill: skill, items: Array(revs).map { |r| { item: r.item.key, revision: r.id } } } }
    TopicRevision.create!(lesson: lesson_revision.lesson, seq: (lesson_revision.lesson.topic_revisions.maximum(:seq) || 0) + 1, course_revision: course,
                          lesson_revision: lesson_revision, body_json: JSON.generate(schema: "banco.topic/1", key: lesson_revision.lesson.key, practice: practice))
  end
end
