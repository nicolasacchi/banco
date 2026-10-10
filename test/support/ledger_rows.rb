# Builds one valid row in every table of the ledger, for tests that exercise the
# append-only triggers and the importer.
module LedgerRows
  JSON_BODY = '{"k":1}'.freeze

  def build_ledger_rows
    now = Time.current
    rows = {}
    rows["subjects"] = Subject.create!(key: "math", name_it: "Matematica", position: 1)
    rows["students"] = Student.create!(key: "student", kind: "student")
    source = SyllabusSource.create!(key: "synthetic", line_count: 1, sha256: "0" * 64)
    rows["syllabus_sources"] = source
    rows["syllabus_lines"] = SyllabusLine.create!(syllabus_source: source, number: 1, text: "x", origin: "pdf")
    rows["reference_texts"] = ReferenceText.create!(key: "ref", title: "t", source_url: "https://example.org", sha256: "0" * 64, body: "b")
    session = AgentSession.create!(label: "s", role: "author")
    rows["agent_sessions"] = session
    token = ApiToken.create!(public_id: "abcd1234", secret_sha256: "d" * 64, role: "agent_claude", label: "l")
    rows["api_tokens"] = token
    rows["api_token_revocations"] = ApiTokenRevocation.create!(api_token: token, reason: "test")
    graph = SkillGraphRevision.create!(subject: rows["subjects"], seq: 1, body_json: JSON_BODY, author_session: session)
    rows["skill_graph_revisions"] = graph
    item = Item.create!(subject: rows["subjects"], key: "item-1", kind: "choice")
    rows["items"] = item
    revision = ItemRevision.create!(item: item, seq: 1, body_json: JSON_BODY, author_session: session,
                                    file_sessions_json: "{}", brief_sha256: "0" * 64)
    rows["item_revisions"] = revision
    rows["item_validations"] = ItemValidation.create!(item_revision: revision, seq: 1, status: "passed")
    instance = ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON_BODY,
                                    answer_json: JSON_BODY, fingerprint: "f" * 64)
    rows["item_instances"] = instance
    review = ItemReview.create!(item_revision: revision, agent_session: session, checklist_json: "[]")
    rows["item_reviews"] = review
    solve = BlindSolve.create!(item_revision: revision, agent_session: session, answers_json: "[]", results_json: "[]")
    rows["blind_solves"] = solve
    rows["review_findings"] = ReviewFinding.create!(item_revision: revision, source: "review", item_review: review, severity: "minor", field: "f",
                                                   quote: "q", problem_it: "p", fix_it: "f")
    rows["finding_responses"] = FindingResponse.create!(review_finding: rows["review_findings"], agent_session: session, stance: "item_right", note_it: "La domanda è giusta.")
    rows["finding_assessments"] = FindingAssessment.create!(review_finding: rows["review_findings"], agent_session: session, verdict: "unclear", note_it: "Non so dire.")
    blueprint = BlueprintRevision.create!(subject: rows["subjects"], skill_graph_revision: graph, seq: 1, body_json: JSON_BODY)
    rows["blueprint_revisions"] = blueprint
    rows["decisions"] = Decision.create!(kind: "approve_skill_graph", subject: rows["subjects"], payload_json: JSON_BODY,
                                         request_id: "req-1", teacher_login: "teacher", remote_addr: "127.0.0.1")
    run = DiagnosisRun.create!(student: rows["students"], subject: rows["subjects"], blueprint_revision: blueprint,
                               sequence: 1, seed_salt: "salt", rules_version: "v1", engine_version: "e1")
    rows["diagnosis_runs"] = run
    event = DiagnosisEvent.create!(diagnosis_run: run, seq: 1, kind: "item_served", payload_json: JSON_BODY, at: now)
    rows["diagnosis_events"] = event
    rows["item_served"] = ItemServed.create!(diagnosis_event: event, item_instance: instance, skill_key: "sk",
                                             shown_order_json: "[]", id_map_json: "{}")
    attempt = Attempt.create!(student: rows["students"], context: "diagnosis", served_event: event,
                              client_attempt_id: "c-1", item_instance: instance, raw: "42", source: "keyboard", answered_at: now)
    rows["attempts"] = attempt
    rows["attempt_gradings"] = AttemptGrading.create!(attempt: attempt, seq: 1, verdict: "correct", method: "exact",
                                                      grader: "closed", grader_version: "abc", source: "sync")
    rows["grade_proposals"] = GradeProposal.create!(attempt: attempt, agent_session: session, points_json: "[]", total: 1, max_total: 2,
                                                    threshold: 0.6, meets_threshold: false)
    rows["app_events"] = AppEvent.create!(kind: "warmup_completed", student: rows["students"])
    build_course_ledger_rows(rows, now, session, graph, instance)
    rows
  end

  # Phase 1b: the five course tables and the five practice tables (one row each).
  def build_course_ledger_rows(rows, now, session, graph, instance)
    lesson = Lesson.create!(subject: rows["subjects"], key: "ripasso.math.demo", kind: "ripasso")
    rows["lessons"] = lesson
    lesson_revision = LessonRevision.create!(lesson: lesson, seq: 1, source_md: "x", source_sha256: "a" * 64, body_json: JSON_BODY,
                                             rules_version: "7", warnings_json: "[]", author_session: session)
    rows["lesson_revisions"] = lesson_revision
    rows["lesson_reviews"] = LessonReview.create!(lesson_revision: lesson_revision, agent_session: session, checklist_json: "[]",
                                                  recomputed_json: "[]", findings_json: "[]")
    course = CourseRevision.create!(subject: rows["subjects"], seq: 1, skill_graph_revision: graph, body_json: JSON_BODY, warnings_json: "[]")
    rows["course_revisions"] = course
    topic = TopicRevision.create!(lesson: lesson, seq: 1, course_revision: course, lesson_revision: lesson_revision, body_json: JSON_BODY)
    rows["topic_revisions"] = topic
    serve = PracticeServe.create!(student: rows["students"], topic_revision: topic, skill_key: "math.sk", item_instance: instance, reason: "next",
                                  seed: 1, rules_version: "practice/1")
    rows["practice_serves"] = serve
    attempt = PracticeAttempt.create!(student: rows["students"], practice_serve: serve, try_number: 1, client_attempt_id: "p-1", raw: "42",
                                      source: "text", hints_before: 0, aided: false, answered_at: now)
    rows["practice_attempts"] = attempt
    rows["practice_gradings"] = PracticeGrading.create!(practice_attempt: attempt, seq: 1, verdict: "correct", method: "exact",
                                                        grader: "closed", grader_version: "abc", source: "sync")
    rows["practice_events"] = PracticeEvent.create!(student: rows["students"], kind: "hint_shown", practice_serve: serve, payload_json: '{"n":1,"auto":false}', at: now)
    rows["lesson_events"] = LessonEvent.create!(student: rows["students"], topic_revision: rows["topic_revisions"], lesson_revision: rows["lesson_revisions"], kind: "card_seen",
                                                card: 1, payload_json: "{}", at: now, created_at: now)
    rows["student_questions"] = StudentQuestion.create!(student: rows["students"], client_question_id: "q-1", text_it: "Non ho capito.")
  end
end
