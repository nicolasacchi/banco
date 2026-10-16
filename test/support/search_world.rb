require_relative "student_course_world"
require_relative "finished_run"
require_relative "lesson2_fixtures"

# The content search on top of the student's course (StudentCourseWorld): every kind of thing a door must not return carries a
# sentinel word, so that a test can search for it through each door. Everything is invented.
#
#   a practice item with a hint, a typical error, a solution and an answer key, each with its own sentinel (LEAKS)
#   a diagnosis item pinned by mistake in an approved topic revision (DIAGNOSIS_WORD)
#   a draft revision of the topic (DRAFT_WORD), a lesson in no topic (ORPHAN_WORD), a course of another subject (OTHER_WORD)
#   the answers of the official student and of a trial student (ANSWER_WORD, TRIAL_ANSWER_WORD), a refused text (REFUSED_WORD)
module SearchWorld
  include StudentCourseWorld
  include PracticeRows

  LEAKS = { hint: "zzaiutozz", error: "zzerrorezz", solution: "zzsoluzionezz", key: "zzchiavezz" }.freeze
  DIAGNOSIS_WORD = "diagnosticozz".freeze
  DRAFT_WORD = "bozzazz".freeze
  ORPHAN_WORD = "orfanozz".freeze
  OTHER_WORD = "altramateriazz".freeze
  ANSWER_WORD = "rispostaufficialezz".freeze
  TRIAL_ANSWER_WORD = "rispostaprovazz".freeze
  REFUSED_WORD = "rifiutatozz".freeze
  DIAGNOSIS_ANSWER_WORD = "rispostadiagnosizz".freeze

  def build_search_world
    build_student_world(approve: false, release: false)
    @leaky = make_leaky_item("leaky-item-1")
    @pinned_diagnosis = make_diagnosis_item("diag-#{DIAGNOSIS_WORD}")
    pins = (@revisions + [ @leaky, @pinned_diagnosis ]).map { |r| { item: r.item.key, revision: r.id } }
    @topic_revision = TopicRevision.create!(lesson: @lesson, seq: 2, course_revision: @course, lesson_revision: @lesson_revision,
                                            body_json: JSON.generate(schema: "banco.topic/1", key: TOPIC, intro_it: "Qui impari a risolvere le equazioni.",
                                                                     practice: [ { skill: SKILL, items: pins } ]))
    approve_topic!(@topic_revision)
    release_course!(@course)
    @trial_student = practice_student("prova-1")
  end

  # A practice item whose every hidden part has a sentinel: hint, typical error, solution, answer key.
  def make_leaky_item(key)
    item = Item.create!(subject: @subject, key: key, kind: "practice_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: "practice_item", subject: "math", skill: SKILL, component: "number", level: 1, expected_seconds: 60,
             hints_it: [ "#{LEAKS[:hint]} guarda il segno" ], error_catalogue: [ { code: "slip", message_it: "#{LEAKS[:error]} hai sbagliato" } ],
             prompt: { stem_it: "Quanto fa la radice quadrata di nove?" } }
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed", codes_json: "[]")
    2.times do |i|
      ItemInstance.create!(item_revision: revision, seed: i + 1, display_json: JSON.generate(stem_it: "Quanto fa la radice quadrata di #{(i + 3)**2}?"),
                           answer_json: JSON.generate(LEAKS[:key]), errors_json: JSON.generate([ { code: "slip", value: LEAKS[:error] } ]),
                           hints_json: JSON.generate([ "#{LEAKS[:hint]} due" ]), solution_json: JSON.generate(steps: [ { text_it: LEAKS[:solution] } ], final: LEAKS[:solution]),
                           fingerprint: Digest::SHA256.hexdigest("#{key}-#{i}"))
    end
    revision
  end

  def make_diagnosis_item(key)
    make_revision(key, SKILL, instances: 2)
  end

  # A second, draft revision of the lesson and of the topic (nothing approves it).
  def add_draft_revision!
    body = lesson_body.deep_stringify_keys.merge("sections" => LESSON_SECTIONS.merge("idea_it" => "Una bozza con la parola #{DRAFT_WORD}."))
    @draft_lesson_revision = LessonRevision.create!(lesson: @lesson, seq: 2, source_md: "---\n", source_sha256: "1" * 64, rules_version: Validation::Rules.version.to_s,
                                                    warnings_json: "[]", body_json: JSON.generate(body))
    @draft_topic_revision = TopicRevision.create!(lesson: @lesson, seq: 3, course_revision: @course, lesson_revision: @draft_lesson_revision,
                                                  body_json: @topic_revision.body_json)
  end

  # A lesson in no topic of any course.
  def add_orphan_lesson!
    lesson = Lesson.create!(subject: @subject, key: "lezione.math.orfana", kind: "lezione")
    body = lesson_body.deep_stringify_keys.merge("key" => lesson.key, "sections" => { "idea_it" => "La lezione che nessun argomento mostra: #{ORPHAN_WORD}." })
    LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: "2" * 64, rules_version: Validation::Rules.version.to_s,
                           warnings_json: "[]", body_json: JSON.generate(body))
  end

  # Another subject with a course map and an unapproved topic: nothing of it is open to the official student.
  def add_other_course!
    other = Subject.create!(key: "italian", name_it: "Italiano", position: 2)
    graph = SkillGraphRevision.create!(subject: other, seq: 1, body_json: JSON.generate(ValidationFixtures::GRAPH.merge("subject" => "italian", "skills" => [])))
    key = "lezione.italian.altro"
    body = { schema: "banco.course/1", schema_version: 1, subject: "italian", skills: [], topics: [ { key: key, kind: "lezione", title_it: "Altro", skills: [], minutes: 10, term: 1, after: [] } ] }
    course = CourseRevision.create!(subject: other, seq: 1, skill_graph_revision: graph, body_json: JSON.generate(body), warnings_json: "[]")
    lesson = Lesson.create!(subject: other, key: key, kind: "lezione")
    revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: "3" * 64, rules_version: Validation::Rules.version.to_s, warnings_json: "[]",
                                      body_json: JSON.generate(key: key, kind: "lezione", subject: "italian", title_it: "Altro", skills: [],
                                                               sections: { "idea_it" => "Una cosa di un altro corso: #{OTHER_WORD}." }))
    TopicRevision.create!(lesson: lesson, seq: 1, course_revision: course, lesson_revision: revision,
                          body_json: JSON.generate(schema: "banco.topic/1", key: key, practice: []))
  end

  # The student's practice answers: a serve of the first pinned item, a typed answer and a refused text.
  def add_answers!(student, word, refused: nil)
    instance = @revisions.first.instances.order(:id).first
    serve = make_serve(student, @topic_revision, instance, skill_key: SKILL)
    make_try(serve, raw: word)
    AppEvent.create!(kind: "practice_invalid_input", student: student, payload_json: JSON.generate(serve_id: serve.id, code: "unreadable", text: refused)) if refused
    serve
  end

  # An entry-test answer of the official student (diagnosis context) on the diagnosis item.
  def add_diagnosis_answer!(student, word)
    instance = @pinned_diagnosis.instances.order(:id).first
    blueprint = BlueprintRevision.create!(subject: @subject, skill_graph_revision: @graph, seq: 1, body_json: JSON.generate(subject: "math", entries: [ { skill: SKILL, items: [] } ]))
    run = DiagnosisRun.create!(student: student, subject: @subject, blueprint_revision: blueprint, sequence: 1, seed_salt: "s", rules_version: "v1", engine_version: "e1")
    event = DiagnosisEvent.create!(diagnosis_run: run, seq: 1, kind: "item_served", payload_json: "{}", at: Time.current)
    ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: SKILL, shown_order_json: "[]", id_map_json: "{}")
    Attempt.create!(student: student, context: "diagnosis", served_event: event, client_attempt_id: SecureRandom.hex(6), item_instance: instance, raw: word,
                    source: "text", answered_at: Time.current)
  end

  def rebuild_search! = Search::Indexer.rebuild!

  def staff_search(query, **options) = Search::Engine.new(scope: Search::Scope::Staff.new).call(query, **options)

  def student_search(student, query, **options) = Search::Engine.new(scope: Search::Scope::Student.for(student)).call(query, **options)
end
