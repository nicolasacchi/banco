require_relative "practice_world"

# A tiny course for the student's pages (A9): one subject, one topic whose lesson has all the sections, one
# skill with two pinned practice items, the students of MultiUser (the official "student" and the trial
# "prova-1"), and short ways to approve and release it. Everything is invented.
module StudentCourseWorld
  include PracticeWorld

  TOPIC = "ripasso.math.demo".freeze
  TOPIC_TITLE = "Equazioni di primo grado".freeze
  # Strings that must never be in a page or a reply before they are due.
  SECRET_FINAL = "x = 31415".freeze
  SECRET_SOLUTION = "Porta il sette a destra, risultato 27182.".freeze

  LESSON_SECTIONS = {
    "why_it" => "Le equazioni servono in quasi ogni **problema**. Se le sai risolvere, i sistemi diventano facili.",
    "idea_it" => "Una equazione è come una bilancia in equilibrio.\n\n- Quello che fai a un lato\n  - lo fai anche all'altro",
    "example_it" => "Risolviamo $3x - 7 = 2$.\n\n1. Porta $-7$ a destra.\n2. Dividi per $3$.",
    "mistakes_it" => "- Spostare un termine senza cambiargli il segno.\n- Dividere un solo lato.\n- Dimenticare la verifica.",
    "book_it" => "Pagine del libro: le indica il docente.",
    "summary_it" => "- Un termine che cambia lato cambia segno.\n- Si divide per il coefficiente.\n- Si controlla il risultato."
  }.freeze

  def build_student_world(approve: true, release: true)
    build_course
    @skill = SKILL
    @topic_key = TOPIC
    @course = build_course_map(skills: [], topics: [ { key: TOPIC, kind: "ripasso", title_it: TOPIC_TITLE, skills: [ SKILL ], minutes: 30, term: 1, after: [] } ])
    @lesson = Lesson.create!(subject: @subject, key: TOPIC, kind: "ripasso")
    @lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 1, source_md: "---\n", source_sha256: "0" * 64, rules_version: Validation::Rules.version.to_s,
                                              warnings_json: "[]", body_json: JSON.generate(lesson_body))
    @revisions = Array.new(2) { |i| make_practice_item("demo-item-#{i + 1}", SKILL, instances: 12) }
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 1, course_revision: @course, lesson_revision: @lesson_revision,
                                            body_json: JSON.generate(schema: "banco.topic/1", key: TOPIC, intro_it: "Qui impari a risolvere le equazioni.",
                                                                     practice: [ { skill: SKILL, items: @revisions.map { |r| { item: r.item.key, revision: r.id } } } ]))
    @official = practice_student("student")
    @trial = practice_student("prova-1")
    approve_topic!(@topic_revision) if approve
    release_course!(@course) if release
    @clock = Diagnosis::FakeClock.new(Time.current)
  end

  def lesson_body
    { schema: "banco.lesson/1", schema_version: 1, key: TOPIC, kind: "ripasso", subject: "math", title_it: "Equazioni di primo grado: risolvere",
      skills: [ SKILL ], uses: [], refs: [ { source: "seconda-2025-26", line: 7, fragment: "equazioni di primo grado numeriche", role: "needed_by" },
                                          { source: "prima-2025-26", line: 3, fragment: "equazioni", role: "taught_in" } ],
      scope: "studied", minutes: 30, calculator: false, sections: LESSON_SECTIONS, try_intro_it: "Prendi un foglio.",
      exercises: [ { n: 1, text_it: "Risolvi e verifica: $2x + 1 = 7$.", solution_it: "#{SECRET_SOLUTION}\n\n1. Primo passo.\n2. Secondo passo.", final_it: SECRET_FINAL },
                   { n: 2, text_it: "Risolvi: $5x = 10$.", solution_it: "Dividi per $5$.", final_it: "x = 2" } ] }
  end

  def approve_topic!(topic_revision)
    decide!("approve_topic", { topic_revision_id: topic_revision.id, topic: topic_revision.lesson.key, seq: topic_revision.seq,
                               course_revision_id: topic_revision.course_revision_id, lesson_revision_id: topic_revision.lesson_revision_id })
  end

  def release_course!(course, open: true)
    payload = open ? { subject: course.subject.key, open: true, course_revision_id: course.id } : { subject: course.subject.key, open: false }
    decide!("release_course", payload, student: Student.official || @official)
  end

  def decide!(kind, payload, student: nil)
    Decision.create!(kind: kind, subject: @subject, student: student, payload_json: JSON.generate(payload), request_id: SecureRandom.hex(4),
                     teacher_login: "nik", remote_addr: "127.0.0.1")
  end
end
