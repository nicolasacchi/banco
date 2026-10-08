# Rows of the practice ledger at given times: serves, attempts with gradings, events.
# Append-only like the tables, so each helper only adds rows.
module PracticeRows
  def practice_student(key = "student", kind: "student")
    Student.find_by(key: key) || Student.create!(key: key, kind: kind)
  end

  # reason next by default; prova_questo and after_solution need parent: and (prova_questo) error_code:.
  def make_serve(student, topic_revision, instance, skill_key:, reason: "next", parent: nil, error_code: nil, seed: 1, at: Time.current)
    PracticeServe.create!(student: student, topic_revision: topic_revision, item_instance: instance, skill_key: skill_key, reason: reason,
                          parent_serve: parent, error_code: error_code, seed: seed, rules_version: "practice/1", created_at: at)
  end

  # One try with its first grading (verdict correct|wrong|dont_know|..., error_codes: ["slip"]).
  def make_try(serve, try_number: 1, raw: "1", verdict: "correct", error_codes: [], hints_before: 0, aided: false, source: "text", at: Time.current)
    @practice_counter = (@practice_counter || 0) + 1
    attempt = PracticeAttempt.create!(student: serve.student, practice_serve: serve, try_number: try_number, client_attempt_id: "pa-#{@practice_counter}-#{SecureRandom.hex(3)}",
                                      raw: raw, source: source, hints_before: hints_before, aided: aided, answered_at: at, created_at: at)
    PracticeGrading.create!(practice_attempt: attempt, seq: 1, verdict: verdict, error_codes_json: JSON.generate(error_codes), method: "exact",
                            grader: "closed", grader_version: "test", source: "sync", created_at: at)
    attempt
  end

  def make_practice_event(student, kind, serve: nil, topic_revision: nil, lesson_revision: nil, payload: {}, at: Time.current)
    PracticeEvent.create!(student: student, kind: kind, practice_serve: serve, topic_revision: topic_revision || serve&.topic_revision,
                          lesson_revision: lesson_revision, payload_json: JSON.generate(payload), at: at, created_at: at)
  end
end
