require_relative "course_rows"

# One topic ready for the teacher, with invented content: a course map, a lesson revision with a full body,
# a lesson review, two practice items with instances (hints, messages, solutions), their reviews and blind
# solves, and a topic revision pinning them. Nothing of a real programme.
module TopicWorld
  include CourseRows

  TOPIC_KEY = "ripasso.math.demo".freeze

  LESSON_BODY = {
    schema: "banco.lesson/1", schema_version: 1, kind: "ripasso", subject: "math", title_it: "Lezione di prova", uses: [],
    refs: [ { source: "seconda-test", line: 1, fragment: "equazioni", role: "needed_by" } ], scope: "studied", minutes: 30, calculator: false,
    sections: { why_it: "Ti serve per i sistemi.", idea_it: "Una **bilancia** in equilibrio.", example_it: "Risolviamo $x + 1 = 3$.", mistakes_it: "- Dimenticare il segno.",
                book_it: "Pagine del libro: le indica il docente.", summary_it: "- Il segno cambia." },
    try_intro_it: nil,
    exercises: [ { n: 1, text_it: "Risolvi $x + 1 = 4$.", solution_it: "$x = 3$.", final_it: "x = 3" },
                 { n: 2, text_it: "Spiega che cosa è una soluzione.", solution_it: "Il valore che rende vera l'uguaglianza.", final_it: nil } ]
  }.freeze

  # Builds everything on @subject (create it first, with its graph). Sets @topic, @lesson_revision, @topic_items, @lesson_review, @reviewer.
  def build_topic_world(subject: @subject, skill: "math.number", key: TOPIC_KEY, review_findings: [])
    @reviewer ||= AgentSession.find_or_create_by!(label: "topic-reviewer", role: "reviewer") { |s| s.agent = "omp"; s.model = "gpt-5.2" }
    course = build_course_map(subject: subject, topics: [ { key: key, kind: "ripasso", title_it: "Ripasso di prova", skills: [ skill ], minutes: 30, term: 1, after: [] } ])
    @lesson_revision = lesson_revision_with_body!(key, skill)
    @lesson_review = review_lesson!(@lesson_revision, findings: review_findings)
    @topic_items = Array.new(2) { |i| make_practice_item("#{key.tr('.', '-')}-#{i + 1}", skill, subject: subject, instances: 6) }
    @topic_items.each { |r| work_item!(r) }
    @topic = make_topic(@lesson_revision, { skill => @topic_items }, course: course)
  end

  # A lesson with one revision whose body is the full parsed lesson (what the page renders).
  def lesson_revision_with_body!(key, skill)
    kind, subject_key, = key.split(".", 3)
    lesson = Lesson.find_by(key: key) || Lesson.create!(subject: Subject.find_by!(key: subject_key), key: key, kind: kind)
    md = "---\nkey: #{key}\n---\n"
    LessonRevision.create!(lesson: lesson, seq: (lesson.revisions.maximum(:seq) || 0) + 1, source_md: md, source_sha256: Digest::SHA256.hexdigest(md),
                           body_json: JSON.generate(LESSON_BODY.merge(key: key, skills: [ skill ])), rules_version: Validation::Rules.version.to_s, warnings_json: "[]")
  end

  def review_lesson!(revision, findings: [], session: @reviewer)
    LessonReview.create!(lesson_revision: revision, agent_session: session, checklist_json: JSON.generate((1..8).map { |i| { id: i, result: "pass", evidence: "ok #{i}" } }),
                         recomputed_json: JSON.generate([ { where: "example", n: 1, expression: "$x+1$", value: "3" } ]), findings_json: JSON.generate(findings))
  end

  def work_item!(revision, session: @reviewer)
    ItemReview.create!(item_revision: revision, agent_session: session, checklist_json: "[]")
    BlindSolve.create!(item_revision: revision, agent_session: session, answers_json: "[]", results_json: "[]")
  end

  def open_topic_page!(headers:, key: TOPIC_KEY, subject: "math")
    on(:web, "/teacher/subjects/#{subject}/topics/#{key}", headers: headers, remote_addr: DecisionWorld::EDGE)
  end

  def record_viewed!(topic = @topic)
    AppEvent.create!(kind: Approval::TopicGate::VIEW_KIND, payload_json: { topic_revision_id: topic.id }.to_json)
  end
end
