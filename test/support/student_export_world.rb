require_relative "ledger_rows"

# D-360: the official student ("student") with one row in every table (LedgerRows) plus the rows that must be cleaned or kept apart, and
# another student ("prova-2") whose rows must never appear in the first one's file. Every address, token and marker here is invented.
module StudentExportWorld
  include LedgerRows

  OTHER_MARKER = "ALTRO-STUDENTE-MARKER".freeze
  TEACHER_ADDR = "203.0.113.9".freeze
  TEACHER_AGENT = "TeacherBrowser/9".freeze
  BOT_ADDR = "198.51.100.7".freeze
  OWN_ADDR = "192.0.2.5".freeze
  TOKEN_ID = "tok-secret-77".freeze

  attr_reader :rows, :student, :other

  def build_export_world
    @rows = build_ledger_rows
    @student = rows["students"]
    Diagnosis::Preferences.record(student, theme: "dark", size: "large")
    Diagnosis::Preferences.record(student, language: "en")
    Decision.create!(kind: "record_consent", student: student, payload_json: { reason_it: "Consenso dei genitori.", via: "api", token: TOKEN_ID }.to_json,
                     request_id: "req-export-1", teacher_login: "nik", remote_addr: TEACHER_ADDR, groups: "banco-teacher", user_agent: TEACHER_AGENT,
                     request_path: "/teacher/decisions")
    Decision.create!(kind: "approve_skill_graph", subject: rows["subjects"], payload_json: "{}", request_id: "req-export-2", teacher_login: "nik",
                     remote_addr: TEACHER_ADDR) # about no student: not in the file
    AppEvent.create!(kind: "practice_reminder_shown", student: student, payload_json: { serve_id: 1, code: "slip", source: "item" }.to_json)
    AppEvent.create!(kind: "teacher_viewed_item", payload_json: { item_revision_id: 1 }.to_json) # no student
    comment = rows["comments"]
    CommentEvent.create!(comment: comment, kind: "reply", origin: "web", actor: "nik", text_it: "Ecco la risposta del docente.", remote_addr: TEACHER_ADDR,
                         request_id: "req-export-3", created_at: Time.current)
    CommentEvent.create!(comment: comment, kind: "resolved", origin: "api", actor: "nik", remote_addr: BOT_ADDR, created_at: Time.current)
    CommentEvent.create!(comment: comment, kind: "student_reply", origin: "student", actor: student.key, text_it: "Grazie, ora è chiaro.", remote_addr: OWN_ADDR,
                         created_at: Time.current)
    build_other_student_rows
    rows
  end

  # A student that is not the first one, with a row marked in the tables a leak would most likely come through.
  def build_other_student_rows
    @other = Student.create!(key: "prova-2", kind: "student")
    instance = rows["item_instances"]
    topic = rows["topic_revisions"]
    run = DiagnosisRun.create!(student: other, subject: rows["subjects"], blueprint_revision: rows["blueprint_revisions"], sequence: 1, seed_salt: "other-salt",
                               rules_version: "v1", engine_version: "e1")
    event = DiagnosisEvent.create!(diagnosis_run: run, seq: 1, kind: "item_served", payload_json: { note: OTHER_MARKER }.to_json, at: Time.current)
    attempt = Attempt.create!(student: other, context: "diagnosis", served_event: event, client_attempt_id: "c-other-1", item_instance: instance, raw: OTHER_MARKER,
                              source: "keyboard", answered_at: Time.current)
    AttemptGrading.create!(attempt: attempt, seq: 1, verdict: "wrong", method: "exact", grader: "closed", grader_version: "abc", source: "sync")
    serve = PracticeServe.create!(student: other, topic_revision: topic, skill_key: "math.sk", item_instance: instance, reason: "next", seed: 1, rules_version: "practice/1")
    practice_attempt = PracticeAttempt.create!(student: other, practice_serve: serve, try_number: 1, client_attempt_id: "p-other-1", raw: OTHER_MARKER, source: "text",
                                               hints_before: 0, aided: false, answered_at: Time.current)
    PracticeGrading.create!(practice_attempt: practice_attempt, seq: 1, verdict: "wrong", method: "exact", grader: "closed", grader_version: "abc", source: "sync")
    PracticeEvent.create!(student: other, kind: "hint_shown", practice_serve: serve, payload_json: { note: OTHER_MARKER }.to_json, at: Time.current)
    PracticeDraft.create!(student: other, practice_serve: serve, raw: OTHER_MARKER, source: "text")
    PracticeContest.create!(student: other, practice_serve: serve, practice_attempt: practice_attempt)
    PracticePoolExhaustion.create!(student: other, topic_revision: topic, skill_key: "math.other", created_at: Time.current)
    LessonEvent.create!(student: other, topic_revision: topic, lesson_revision: rows["lesson_revisions"], kind: "card_seen", card: 2, payload_json: { note: OTHER_MARKER }.to_json,
                        at: Time.current, created_at: Time.current)
    StudentQuestion.create!(student: other, client_question_id: "q-other-1", text_it: OTHER_MARKER)
    comment = Comment.create!(student: other, client_comment_id: "c-other-comment", reason: "other", text_it: OTHER_MARKER, page_path: "/today", page_kind: "today",
                              created_at: Time.current)
    CommentEvent.create!(comment: comment, kind: "reply", origin: "web", actor: "nik", text_it: OTHER_MARKER, created_at: Time.current)
    AppEvent.create!(kind: "invalid_input", student: other, payload_json: { text: OTHER_MARKER }.to_json)
    Decision.create!(kind: "record_consent", student: other, payload_json: { reason_it: OTHER_MARKER }.to_json, request_id: "req-other-1", teacher_login: "nik",
                     remote_addr: "203.0.113.200")
  end
end
