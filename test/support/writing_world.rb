require_relative "student_course_world"

# The student's course of StudentCourseWorld plus a writing task (D-407): a short_answer item with a word range pinned by a second revision of the topic, which the
# teacher approves, on top of the practice items of revision 1. Everything is invented.
module WritingWorld
  include StudentCourseWorld

  TASK_KEY = "math-write-1".freeze
  TASK_TEXT = "Racconta in poche righe come hai risolto un'equazione.".freeze
  TASK_NOTES = "Guarda se nomina la verifica e se i passaggi sono in ordine.".freeze
  # The advice that the item's author wrote under `answer_format_it` and that the rubric grades (D-410): the student is told it under the task.
  TASK_FORMAT = "Scrivi al passato prossimo e collega le frasi con «prima», «poi» e «alla fine».".freeze

  # The world of StudentCourseWorld, approved and released, whose topic revision (the one the student is shown) pins the writing task.
  def build_writing_world(**options)
    build_student_world(approve: false, release: false, **options)
    @task = make_writing_item(TASK_KEY)
    @practice_topic = @topic_revision
    @topic_revision = make_writing_topic(@practice_topic, [ @task ])
    approve_topic!(@topic_revision)
    release_course!(@course)
  end

  # A short_answer item with a word range, a model answer, the answer format and the teacher's notes (banco.item/1, kind short_answer), validated. `prompt:` replaces the
  # Italian-only prompt (a bilingual task: stem_en + stem_it) and `extra:` is merged into the body (answer_format_en, bilingual).
  def make_writing_item(key, subject: nil, words: [ 20, 60 ], status: "passed", text: TASK_TEXT, notes: TASK_NOTES, format_it: TASK_FORMAT, prompt: nil, extra: {})
    subject ||= @subject
    item = Item.create!(subject: subject, key: key, kind: "short_answer")
    body = { schema: "banco.item/1", schema_version: 1, kind: "short_answer", subject: subject.key, skill: SKILL, component: "short_answer", prompt: prompt || { stem_it: text },
             rubric: { points: [ { id: "steps", weight: 2, expected_it: "Nomina i passaggi." }, { id: "check", weight: 1, expected_it: "Nomina la verifica." } ], threshold: 0.6,
                       model_answer_it: "Un testo che nomina i passaggi e la verifica." },
             words_min: words.first, words_max: words.last, teacher_notes_it: notes }.merge(extra)
    body[:answer_format_it] = format_it if format_it
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON.generate(body), file_sessions_json: "{}")
    ItemValidation.create!(item_revision: revision, seq: 1, status: status, codes_json: "[]") if status
    ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON.generate(stem_it: text), answer_json: JSON.generate(body[:rubric]), errors_json: nil,
                         hints_json: "[]", solution_json: JSON.generate(model_answer_it: body[:rubric][:model_answer_it]), fingerprint: Digest::SHA256.hexdigest("#{key}-writing"))
    revision
  end

  # The same lesson's next topic revision: the practice of +base+ and these writing item revisions.
  def make_writing_topic(base, tasks)
    body = base.body.merge("writing" => tasks.map { |r| { "item" => r.item.key, "revision" => r.id } })
    TopicRevision.create!(lesson: base.lesson, seq: base.lesson.topic_revisions.maximum(:seq) + 1, course_revision: base.course_revision, lesson_revision: base.lesson_revision,
                          body_json: JSON.generate(body))
  end

  def topic_path = "/topics/#{TOPIC}"
  def writings_path = "#{topic_path}/writings"
end
