require_relative "student_course_world"

# «Novità» (D-375) on top of the student's tiny course: a second approval of the same topic (a revision that replaces the first), the second topic that
# the course map does not hold (so no student sees it), and comments of the student on a page.
module ChangelogWorld
  include StudentCourseWorld

  HIDDEN_TOPIC = "lezione.math.nascosto".freeze

  # A new revision of the topic (the same lesson and items) and the teacher's approval of it, now (travel_to moves "now"). extra: more payload
  # (the findings reason, a console note).
  def revise!(topic_revision = @topic_revision, **extra)
    lesson = topic_revision.lesson
    seq = TopicRevision.where(lesson: lesson).maximum(:seq) + 1
    revision = TopicRevision.create!(lesson: lesson, seq: seq, course_revision: topic_revision.course_revision, lesson_revision: topic_revision.lesson_revision,
                                     body_json: topic_revision.body_json)
    payload = { topic_revision_id: revision.id, topic: lesson.key, seq: seq, course_revision_id: revision.course_revision_id,
                lesson_revision_id: revision.lesson_revision_id }.merge(extra)
    decide!("approve_topic", payload)
    revision
  end

  # A topic that no course map of the student holds, approved twice.
  def build_hidden_topic!
    lesson = Lesson.create!(subject: @subject, key: HIDDEN_TOPIC, kind: "lezione")
    lesson_revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "---\n", source_sha256: "1" * 64, rules_version: Validation::Rules.version.to_s,
                                             warnings_json: "[]", body_json: JSON.generate(lesson_body.merge(key: HIDDEN_TOPIC, kind: "lezione")))
    first = TopicRevision.create!(lesson: lesson, seq: 1, course_revision: @course, lesson_revision: lesson_revision,
                                  body_json: JSON.generate(schema: "banco.topic/1", key: HIDDEN_TOPIC, practice: []))
    approve_topic!(first)
    revise!(first)
  end

  # A comment of the student, written at +at+ on a page of his.
  def comment_on(student, path, kind, at: Time.current, card: nil, text: "Non torna.")
    Comment.create!(student: student, client_comment_id: "c-#{SecureRandom.hex(6)}", reason: "error", text_it: text, page_path: path, page_kind: kind,
                    subject: @subject, card: card, created_at: at)
  end
end
