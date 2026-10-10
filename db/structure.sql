CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "subjects" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "name_it" varchar NOT NULL, "position" integer NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_subjects_on_key" ON "subjects" ("key");
CREATE TABLE "syllabus_sources" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "line_count" integer NOT NULL, "sha256" varchar(64) NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_syllabus_sources_on_key" ON "syllabus_sources" ("key");
CREATE TABLE "syllabus_lines" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "syllabus_source_id" integer NOT NULL, "number" integer NOT NULL, "text" text NOT NULL, "origin" varchar NOT NULL, "marker" varchar, "parts_json" text, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_337129165a"
FOREIGN KEY ("syllabus_source_id")
  REFERENCES "syllabus_sources" ("id")
, CONSTRAINT syllabus_lines_origin CHECK (origin IN ('pdf','transcript','operator')));
CREATE INDEX "index_syllabus_lines_on_syllabus_source_id" ON "syllabus_lines" ("syllabus_source_id");
CREATE UNIQUE INDEX "index_syllabus_lines_on_syllabus_source_id_and_number" ON "syllabus_lines" ("syllabus_source_id", "number");
CREATE TABLE "reference_texts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "title" varchar NOT NULL, "source_url" varchar NOT NULL, "sha256" varchar(64) NOT NULL, "body" text NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_reference_texts_on_key" ON "reference_texts" ("key");
CREATE TABLE "skill_graph_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "seq" integer NOT NULL, "body_json" text NOT NULL, "author_session_id" integer, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_511ad51e6c"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
);
CREATE INDEX "index_skill_graph_revisions_on_subject_id" ON "skill_graph_revisions" ("subject_id");
CREATE UNIQUE INDEX "index_skill_graph_revisions_on_subject_id_and_seq" ON "skill_graph_revisions" ("subject_id", "seq");
CREATE TABLE "items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "key" varchar NOT NULL, "kind" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_2f63756365"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
);
CREATE INDEX "index_items_on_subject_id" ON "items" ("subject_id");
CREATE UNIQUE INDEX "index_items_on_key" ON "items" ("key");
CREATE TABLE "item_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_id" integer NOT NULL, "seq" integer NOT NULL, "base_revision_id" integer, "body_json" text NOT NULL, "author_session_id" integer, "file_sessions_json" text, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, "files_json" text, CONSTRAINT "fk_rails_0ac7a4cb2d"
FOREIGN KEY ("item_id")
  REFERENCES "items" ("id")
);
CREATE INDEX "index_item_revisions_on_item_id" ON "item_revisions" ("item_id");
CREATE UNIQUE INDEX "index_item_revisions_on_item_id_and_seq" ON "item_revisions" ("item_id", "seq");
CREATE TABLE "item_validations" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "seq" integer NOT NULL, "status" varchar NOT NULL, "codes_json" text, "created_at" datetime(6) NOT NULL, "findings_json" text, "rules_version" varchar, "grader_version" varchar, "harness_version" varchar, "chrome_version" varchar, "instances_sha256" varchar(64), "attempt" integer, CONSTRAINT "fk_rails_3879210719"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
);
CREATE INDEX "index_item_validations_on_item_revision_id" ON "item_validations" ("item_revision_id");
CREATE UNIQUE INDEX "index_item_validations_on_item_revision_id_and_seq" ON "item_validations" ("item_revision_id", "seq");
CREATE TABLE "item_instances" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "seed" integer, "display_json" text NOT NULL, "answer_json" text NOT NULL, "errors_json" text, "solution_json" text, "fingerprint" varchar(64) NOT NULL, "created_at" datetime(6) NOT NULL, "accept_json" text, "hints_json" text, CONSTRAINT "fk_rails_07564fabf6"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
);
CREATE INDEX "index_item_instances_on_item_revision_id" ON "item_instances" ("item_revision_id");
CREATE INDEX "index_item_instances_on_item_revision_id_and_fingerprint" ON "item_instances" ("item_revision_id", "fingerprint");
CREATE TABLE "blueprint_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "skill_graph_revision_id" integer NOT NULL, "seq" integer NOT NULL, "body_json" text NOT NULL, "author_session_id" integer, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_320fc6e2d7"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
, CONSTRAINT "fk_rails_77b7161d1c"
FOREIGN KEY ("skill_graph_revision_id")
  REFERENCES "skill_graph_revisions" ("id")
);
CREATE INDEX "index_blueprint_revisions_on_subject_id" ON "blueprint_revisions" ("subject_id");
CREATE INDEX "index_blueprint_revisions_on_skill_graph_revision_id" ON "blueprint_revisions" ("skill_graph_revision_id");
CREATE UNIQUE INDEX "index_blueprint_revisions_on_subject_id_and_seq" ON "blueprint_revisions" ("subject_id", "seq");
CREATE TRIGGER subjects_no_update BEFORE UPDATE ON subjects
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER subjects_no_delete BEFORE DELETE ON subjects
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER syllabus_sources_no_update BEFORE UPDATE ON syllabus_sources
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER syllabus_sources_no_delete BEFORE DELETE ON syllabus_sources
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER syllabus_lines_no_update BEFORE UPDATE ON syllabus_lines
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER syllabus_lines_no_delete BEFORE DELETE ON syllabus_lines
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER reference_texts_no_update BEFORE UPDATE ON reference_texts
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER reference_texts_no_delete BEFORE DELETE ON reference_texts
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER skill_graph_revisions_no_update BEFORE UPDATE ON skill_graph_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER skill_graph_revisions_no_delete BEFORE DELETE ON skill_graph_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER items_no_update BEFORE UPDATE ON items
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER items_no_delete BEFORE DELETE ON items
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_revisions_no_update BEFORE UPDATE ON item_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_revisions_no_delete BEFORE DELETE ON item_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_validations_no_update BEFORE UPDATE ON item_validations
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_validations_no_delete BEFORE DELETE ON item_validations
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_instances_no_update BEFORE UPDATE ON item_instances
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_instances_no_delete BEFORE DELETE ON item_instances
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER blueprint_revisions_no_update BEFORE UPDATE ON blueprint_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER blueprint_revisions_no_delete BEFORE DELETE ON blueprint_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "students" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "kind" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT students_kind CHECK (kind IN ('student','preview')));
CREATE UNIQUE INDEX "index_students_on_key" ON "students" ("key");
CREATE TABLE "decisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "subject_id" integer, "student_id" integer, "payload_json" text NOT NULL, "request_id" varchar NOT NULL, "teacher_login" varchar NOT NULL, "remote_addr" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "groups" varchar DEFAULT '' NOT NULL, "user_agent" varchar DEFAULT '' NOT NULL, "request_path" varchar DEFAULT '' NOT NULL, CONSTRAINT "fk_rails_7a1a6ec8a0"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
, CONSTRAINT "fk_rails_00cea4747f"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
);
CREATE INDEX "index_decisions_on_subject_id" ON "decisions" ("subject_id");
CREATE INDEX "index_decisions_on_student_id" ON "decisions" ("student_id");
CREATE UNIQUE INDEX "index_decisions_on_request_id" ON "decisions" ("request_id");
CREATE TABLE "diagnosis_runs" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "student_id" integer NOT NULL, "subject_id" integer NOT NULL, "blueprint_revision_id" integer NOT NULL, "sequence" integer NOT NULL, "seed_salt" varchar NOT NULL, "rules_version" varchar NOT NULL, "engine_version" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_8fc541c4a2"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
, CONSTRAINT "fk_rails_fb8ad064bd"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
, CONSTRAINT "fk_rails_54558fd58d"
FOREIGN KEY ("blueprint_revision_id")
  REFERENCES "blueprint_revisions" ("id")
);
CREATE INDEX "index_diagnosis_runs_on_student_id" ON "diagnosis_runs" ("student_id");
CREATE INDEX "index_diagnosis_runs_on_subject_id" ON "diagnosis_runs" ("subject_id");
CREATE INDEX "index_diagnosis_runs_on_blueprint_revision_id" ON "diagnosis_runs" ("blueprint_revision_id");
CREATE UNIQUE INDEX "index_diagnosis_runs_on_student_id_and_subject_id_and_sequence" ON "diagnosis_runs" ("student_id", "subject_id", "sequence");
CREATE TABLE "diagnosis_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "diagnosis_run_id" integer NOT NULL, "seq" integer NOT NULL, "kind" varchar NOT NULL, "payload_json" text, "at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_d98a18cb07"
FOREIGN KEY ("diagnosis_run_id")
  REFERENCES "diagnosis_runs" ("id")
);
CREATE INDEX "index_diagnosis_events_on_diagnosis_run_id" ON "diagnosis_events" ("diagnosis_run_id");
CREATE UNIQUE INDEX "index_diagnosis_events_on_diagnosis_run_id_and_seq" ON "diagnosis_events" ("diagnosis_run_id", "seq");
CREATE TABLE "item_served" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "diagnosis_event_id" integer NOT NULL, "item_instance_id" integer NOT NULL, "skill_key" varchar NOT NULL, "shown_order_json" text, "id_map_json" text, "created_at" datetime(6) NOT NULL, "formula_sheet_available" boolean DEFAULT FALSE NOT NULL, CONSTRAINT "fk_rails_b8f6754796"
FOREIGN KEY ("diagnosis_event_id")
  REFERENCES "diagnosis_events" ("id")
, CONSTRAINT "fk_rails_af0a6a9d92"
FOREIGN KEY ("item_instance_id")
  REFERENCES "item_instances" ("id")
);
CREATE UNIQUE INDEX "index_item_served_on_diagnosis_event_id" ON "item_served" ("diagnosis_event_id");
CREATE INDEX "index_item_served_on_item_instance_id" ON "item_served" ("item_instance_id");
CREATE TABLE "attempts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "student_id" integer NOT NULL, "context" varchar NOT NULL, "served_event_id" integer, "client_attempt_id" varchar NOT NULL, "item_instance_id" integer NOT NULL, "raw" text NOT NULL, "source" varchar NOT NULL, "answered_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_4d72795245"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
, CONSTRAINT "fk_rails_36356d6479"
FOREIGN KEY ("served_event_id")
  REFERENCES "diagnosis_events" ("id")
, CONSTRAINT "fk_rails_6a62c99be5"
FOREIGN KEY ("item_instance_id")
  REFERENCES "item_instances" ("id")
, CONSTRAINT attempts_context CHECK (context IN ('diagnosis','teacher_preview','warmup')));
CREATE INDEX "index_attempts_on_student_id" ON "attempts" ("student_id");
CREATE UNIQUE INDEX "index_attempts_on_served_event_id" ON "attempts" ("served_event_id");
CREATE UNIQUE INDEX "index_attempts_on_client_attempt_id" ON "attempts" ("client_attempt_id");
CREATE INDEX "index_attempts_on_item_instance_id" ON "attempts" ("item_instance_id");
CREATE TABLE "attempt_gradings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "attempt_id" integer NOT NULL, "seq" integer NOT NULL, "verdict" varchar NOT NULL, "error_codes_json" text, "form_violations_json" text, "normalized" text, "method" varchar, "grader" varchar NOT NULL, "grader_version" varchar NOT NULL, "ce_version" varchar, "source" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_3c97fc2b8c"
FOREIGN KEY ("attempt_id")
  REFERENCES "attempts" ("id")
, CONSTRAINT attempt_gradings_source CHECK (source IN ('sync','retry')), CONSTRAINT attempt_gradings_method CHECK (method IS NULL OR method IN ('exact','float')));
CREATE INDEX "index_attempt_gradings_on_attempt_id" ON "attempt_gradings" ("attempt_id");
CREATE UNIQUE INDEX "index_attempt_gradings_on_attempt_id_and_seq" ON "attempt_gradings" ("attempt_id", "seq");
CREATE TABLE "app_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "student_id" integer, "payload_json" text, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_783009c2fd"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
);
CREATE INDEX "index_app_events_on_student_id" ON "app_events" ("student_id");
CREATE TRIGGER students_no_update BEFORE UPDATE ON students
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER students_no_delete BEFORE DELETE ON students
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER decisions_no_update BEFORE UPDATE ON decisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER decisions_no_delete BEFORE DELETE ON decisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER diagnosis_runs_no_update BEFORE UPDATE ON diagnosis_runs
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER diagnosis_runs_no_delete BEFORE DELETE ON diagnosis_runs
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER diagnosis_events_no_update BEFORE UPDATE ON diagnosis_events
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER diagnosis_events_no_delete BEFORE DELETE ON diagnosis_events
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_served_no_update BEFORE UPDATE ON item_served
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_served_no_delete BEFORE DELETE ON item_served
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER attempts_no_update BEFORE UPDATE ON attempts
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER attempts_no_delete BEFORE DELETE ON attempts
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER attempt_gradings_no_update BEFORE UPDATE ON attempt_gradings
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER attempt_gradings_no_delete BEFORE DELETE ON attempt_gradings
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER app_events_no_update BEFORE UPDATE ON app_events
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER app_events_no_delete BEFORE DELETE ON app_events
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "api_tokens" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "public_id" varchar NOT NULL, "secret_sha256" varchar NOT NULL, "role" varchar NOT NULL, "label" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT api_tokens_public_id_length CHECK (length(public_id) = 8), CONSTRAINT api_tokens_sha256_length CHECK (length(secret_sha256) = 64), CONSTRAINT api_tokens_role CHECK (role IN ('agent_claude','agent_omp','ci')));
CREATE UNIQUE INDEX "index_api_tokens_on_public_id" ON "api_tokens" ("public_id");
CREATE TABLE "api_token_revocations" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "api_token_id" integer NOT NULL, "reason" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_b9e431c1e1"
FOREIGN KEY ("api_token_id")
  REFERENCES "api_tokens" ("id")
);
CREATE UNIQUE INDEX "index_api_token_revocations_on_api_token_id" ON "api_token_revocations" ("api_token_id");
CREATE TRIGGER api_tokens_no_update BEFORE UPDATE ON api_tokens
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER api_tokens_no_delete BEFORE DELETE ON api_tokens
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER api_token_revocations_no_update BEFORE UPDATE ON api_token_revocations
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER api_token_revocations_no_delete BEFORE DELETE ON api_token_revocations
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "item_reviews" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "checklist_json" text NOT NULL, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ec107e989d"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
, CONSTRAINT "fk_rails_f9dc7f7c53"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_item_reviews_on_item_revision_id" ON "item_reviews" ("item_revision_id");
CREATE INDEX "index_item_reviews_on_agent_session_id" ON "item_reviews" ("agent_session_id");
CREATE TABLE "blind_solves" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "answers_json" text NOT NULL, "results_json" text NOT NULL, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_cc8f34abcd"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
, CONSTRAINT "fk_rails_2bc0056230"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_blind_solves_on_item_revision_id" ON "blind_solves" ("item_revision_id");
CREATE INDEX "index_blind_solves_on_agent_session_id" ON "blind_solves" ("agent_session_id");
CREATE TABLE "review_findings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "source" varchar NOT NULL, "item_review_id" integer, "blind_solve_id" integer, "severity" varchar NOT NULL, "code" varchar, "instance" integer, "field" varchar NOT NULL, "quote" text NOT NULL, "problem_it" text NOT NULL, "fix_it" text NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_8893ccc3bb"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
, CONSTRAINT "fk_rails_6a4a723a38"
FOREIGN KEY ("item_review_id")
  REFERENCES "item_reviews" ("id")
, CONSTRAINT "fk_rails_af83657749"
FOREIGN KEY ("blind_solve_id")
  REFERENCES "blind_solves" ("id")
, CONSTRAINT review_findings_source CHECK (source IN ('review','blind_solve')), CONSTRAINT review_findings_severity CHECK (severity IN ('blocker','major','minor')));
CREATE INDEX "index_review_findings_on_item_revision_id" ON "review_findings" ("item_revision_id");
CREATE INDEX "index_review_findings_on_item_review_id" ON "review_findings" ("item_review_id");
CREATE INDEX "index_review_findings_on_blind_solve_id" ON "review_findings" ("blind_solve_id");
CREATE TABLE "grade_proposals" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "attempt_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "points_json" text NOT NULL, "missing_it" text, "total" integer NOT NULL, "max_total" integer NOT NULL, "threshold" float NOT NULL, "meets_threshold" boolean NOT NULL, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_6b13eee236"
FOREIGN KEY ("attempt_id")
  REFERENCES "attempts" ("id")
, CONSTRAINT "fk_rails_36d8f549cd"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_grade_proposals_on_attempt_id" ON "grade_proposals" ("attempt_id");
CREATE INDEX "index_grade_proposals_on_agent_session_id" ON "grade_proposals" ("agent_session_id");
CREATE TRIGGER item_reviews_no_update BEFORE UPDATE ON item_reviews
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER item_reviews_no_delete BEFORE DELETE ON item_reviews
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER blind_solves_no_update BEFORE UPDATE ON blind_solves
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER blind_solves_no_delete BEFORE DELETE ON blind_solves
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER review_findings_no_update BEFORE UPDATE ON review_findings
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER review_findings_no_delete BEFORE DELETE ON review_findings
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER grade_proposals_no_update BEFORE UPDATE ON grade_proposals
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER grade_proposals_no_delete BEFORE DELETE ON grade_proposals
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "finding_responses" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "review_finding_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "stance" varchar NOT NULL, "item_revision_id" integer, "note_it" text NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_bc5c7f703f"
FOREIGN KEY ("review_finding_id")
  REFERENCES "review_findings" ("id")
, CONSTRAINT "fk_rails_0d5b50aaf3"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
, CONSTRAINT "fk_rails_a6ac31c714"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
, CONSTRAINT finding_responses_stance CHECK (stance IN ('item_right','fixed')), CONSTRAINT finding_responses_revision CHECK ((stance = 'fixed') = (item_revision_id IS NOT NULL)), CONSTRAINT finding_responses_note_length CHECK (length(note_it) BETWEEN 1 AND 700));
CREATE INDEX "index_finding_responses_on_review_finding_id" ON "finding_responses" ("review_finding_id");
CREATE INDEX "index_finding_responses_on_agent_session_id" ON "finding_responses" ("agent_session_id");
CREATE INDEX "index_finding_responses_on_item_revision_id" ON "finding_responses" ("item_revision_id");
CREATE TRIGGER finding_responses_no_update BEFORE UPDATE ON finding_responses
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER finding_responses_no_delete BEFORE DELETE ON finding_responses
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "agent_sessions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "label" varchar NOT NULL, "role" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "agent" varchar, "model" varchar, "token_id" varchar, CONSTRAINT agent_sessions_role CHECK (role IN ('author','verifier','reviewer','solver','grader','operator','arbiter')));
CREATE TRIGGER agent_sessions_no_update BEFORE UPDATE ON agent_sessions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER agent_sessions_no_delete BEFORE DELETE ON agent_sessions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "finding_assessments" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "review_finding_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "verdict" varchar NOT NULL, "note_it" text NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_633fb8fe9e"
FOREIGN KEY ("review_finding_id")
  REFERENCES "review_findings" ("id")
, CONSTRAINT "fk_rails_9b8659b2e6"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
, CONSTRAINT finding_assessments_verdict CHECK (verdict IN ('author_right','finding_right','unclear')), CONSTRAINT finding_assessments_note_length CHECK (length(note_it) BETWEEN 1 AND 500));
CREATE INDEX "index_finding_assessments_on_review_finding_id" ON "finding_assessments" ("review_finding_id");
CREATE INDEX "index_finding_assessments_on_agent_session_id" ON "finding_assessments" ("agent_session_id");
CREATE TRIGGER finding_assessments_no_update BEFORE UPDATE ON finding_assessments
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER finding_assessments_no_delete BEFORE DELETE ON finding_assessments
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "lessons" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "key" varchar NOT NULL, "kind" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ffc4753ede"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
, CONSTRAINT lessons_kind CHECK (kind IN ('ripasso','ponte','lezione')));
CREATE INDEX "index_lessons_on_subject_id" ON "lessons" ("subject_id");
CREATE UNIQUE INDEX "index_lessons_on_key" ON "lessons" ("key");
CREATE TABLE "lesson_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "lesson_id" integer NOT NULL, "seq" integer NOT NULL, "base_revision_id" integer, "source_md" text NOT NULL, "source_sha256" varchar NOT NULL, "body_json" text NOT NULL, "rules_version" varchar NOT NULL, "warnings_json" text NOT NULL, "author_session_id" integer, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_9a9f6c634e"
FOREIGN KEY ("lesson_id")
  REFERENCES "lessons" ("id")
, CONSTRAINT "fk_rails_b599e27bb7"
FOREIGN KEY ("base_revision_id")
  REFERENCES "lesson_revisions" ("id")
, CONSTRAINT "fk_rails_b862f0f468"
FOREIGN KEY ("author_session_id")
  REFERENCES "agent_sessions" ("id")
, CONSTRAINT lesson_revisions_sha256_length CHECK (length(source_sha256) = 64));
CREATE INDEX "index_lesson_revisions_on_lesson_id" ON "lesson_revisions" ("lesson_id");
CREATE INDEX "index_lesson_revisions_on_base_revision_id" ON "lesson_revisions" ("base_revision_id");
CREATE INDEX "index_lesson_revisions_on_author_session_id" ON "lesson_revisions" ("author_session_id");
CREATE UNIQUE INDEX "index_lesson_revisions_on_lesson_id_and_seq" ON "lesson_revisions" ("lesson_id", "seq");
CREATE TABLE "lesson_reviews" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "lesson_revision_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "checklist_json" text NOT NULL, "recomputed_json" text NOT NULL, "findings_json" text NOT NULL, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_1575fe637b"
FOREIGN KEY ("lesson_revision_id")
  REFERENCES "lesson_revisions" ("id")
, CONSTRAINT "fk_rails_d43de99a9c"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_lesson_reviews_on_lesson_revision_id" ON "lesson_reviews" ("lesson_revision_id");
CREATE INDEX "index_lesson_reviews_on_agent_session_id" ON "lesson_reviews" ("agent_session_id");
CREATE UNIQUE INDEX "idx_on_lesson_revision_id_agent_session_id_68261c0155" ON "lesson_reviews" ("lesson_revision_id", "agent_session_id");
CREATE TABLE "course_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "seq" integer NOT NULL, "skill_graph_revision_id" integer NOT NULL, "body_json" text NOT NULL, "warnings_json" text NOT NULL, "author_session_id" integer, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_008dfdd7b2"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
, CONSTRAINT "fk_rails_1ba6b5f8f1"
FOREIGN KEY ("skill_graph_revision_id")
  REFERENCES "skill_graph_revisions" ("id")
, CONSTRAINT "fk_rails_760e846456"
FOREIGN KEY ("author_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_course_revisions_on_subject_id" ON "course_revisions" ("subject_id");
CREATE INDEX "index_course_revisions_on_skill_graph_revision_id" ON "course_revisions" ("skill_graph_revision_id");
CREATE INDEX "index_course_revisions_on_author_session_id" ON "course_revisions" ("author_session_id");
CREATE UNIQUE INDEX "index_course_revisions_on_subject_id_and_seq" ON "course_revisions" ("subject_id", "seq");
CREATE TABLE "topic_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "lesson_id" integer NOT NULL, "seq" integer NOT NULL, "course_revision_id" integer NOT NULL, "lesson_revision_id" integer NOT NULL, "body_json" text NOT NULL, "author_session_id" integer, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_9db86ce251"
FOREIGN KEY ("lesson_id")
  REFERENCES "lessons" ("id")
, CONSTRAINT "fk_rails_30c3910a96"
FOREIGN KEY ("course_revision_id")
  REFERENCES "course_revisions" ("id")
, CONSTRAINT "fk_rails_7f6b8598ef"
FOREIGN KEY ("lesson_revision_id")
  REFERENCES "lesson_revisions" ("id")
, CONSTRAINT "fk_rails_11ac084bde"
FOREIGN KEY ("author_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_topic_revisions_on_lesson_id" ON "topic_revisions" ("lesson_id");
CREATE INDEX "index_topic_revisions_on_course_revision_id" ON "topic_revisions" ("course_revision_id");
CREATE INDEX "index_topic_revisions_on_lesson_revision_id" ON "topic_revisions" ("lesson_revision_id");
CREATE INDEX "index_topic_revisions_on_author_session_id" ON "topic_revisions" ("author_session_id");
CREATE UNIQUE INDEX "index_topic_revisions_on_lesson_id_and_seq" ON "topic_revisions" ("lesson_id", "seq");
CREATE TRIGGER lessons_no_update BEFORE UPDATE ON lessons
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER lessons_no_delete BEFORE DELETE ON lessons
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER lesson_revisions_no_update BEFORE UPDATE ON lesson_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER lesson_revisions_no_delete BEFORE DELETE ON lesson_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER lesson_reviews_no_update BEFORE UPDATE ON lesson_reviews
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER lesson_reviews_no_delete BEFORE DELETE ON lesson_reviews
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER course_revisions_no_update BEFORE UPDATE ON course_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER course_revisions_no_delete BEFORE DELETE ON course_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER topic_revisions_no_update BEFORE UPDATE ON topic_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER topic_revisions_no_delete BEFORE DELETE ON topic_revisions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "practice_serves" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "student_id" integer NOT NULL, "topic_revision_id" integer NOT NULL, "skill_key" varchar NOT NULL, "item_instance_id" integer NOT NULL, "reason" varchar NOT NULL, "parent_serve_id" integer, "error_code" varchar, "seed" integer NOT NULL, "shown_order_json" text, "id_map_json" text, "rules_version" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_ad377e6fef"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
, CONSTRAINT "fk_rails_aeaabb8641"
FOREIGN KEY ("topic_revision_id")
  REFERENCES "topic_revisions" ("id")
, CONSTRAINT "fk_rails_9d69e95aba"
FOREIGN KEY ("item_instance_id")
  REFERENCES "item_instances" ("id")
, CONSTRAINT "fk_rails_169e4c5f79"
FOREIGN KEY ("parent_serve_id")
  REFERENCES "practice_serves" ("id")
, CONSTRAINT practice_serves_reason CHECK (reason IN ('next','prova_questo','after_solution','reseen')), CONSTRAINT practice_serves_error_code CHECK ((reason = 'prova_questo') = (error_code IS NOT NULL)), CONSTRAINT practice_serves_parent CHECK (reason NOT IN ('prova_questo','after_solution') OR parent_serve_id IS NOT NULL));
CREATE INDEX "index_practice_serves_on_student_id" ON "practice_serves" ("student_id");
CREATE INDEX "index_practice_serves_on_topic_revision_id" ON "practice_serves" ("topic_revision_id");
CREATE INDEX "index_practice_serves_on_item_instance_id" ON "practice_serves" ("item_instance_id");
CREATE INDEX "index_practice_serves_on_parent_serve_id" ON "practice_serves" ("parent_serve_id");
CREATE INDEX "index_practice_serves_on_student_id_and_skill_key_and_id" ON "practice_serves" ("student_id", "skill_key", "id");
CREATE INDEX "index_practice_serves_on_student_id_and_item_instance_id" ON "practice_serves" ("student_id", "item_instance_id");
CREATE TABLE "practice_attempts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "student_id" integer NOT NULL, "practice_serve_id" integer NOT NULL, "try_number" integer NOT NULL, "client_attempt_id" varchar NOT NULL, "raw" text NOT NULL, "source" varchar NOT NULL, "hints_before" integer NOT NULL, "aided" boolean NOT NULL, "answered_at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_cebb17abab"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
, CONSTRAINT "fk_rails_543744633b"
FOREIGN KEY ("practice_serve_id")
  REFERENCES "practice_serves" ("id")
, CONSTRAINT practice_attempts_try_number CHECK (try_number BETWEEN 1 AND 3), CONSTRAINT practice_attempts_source CHECK (source IN ('text','mathlive','button')), CONSTRAINT practice_attempts_hints_before CHECK (hints_before >= 0));
CREATE INDEX "index_practice_attempts_on_student_id" ON "practice_attempts" ("student_id");
CREATE INDEX "index_practice_attempts_on_practice_serve_id" ON "practice_attempts" ("practice_serve_id");
CREATE UNIQUE INDEX "index_practice_attempts_on_practice_serve_id_and_try_number" ON "practice_attempts" ("practice_serve_id", "try_number");
CREATE UNIQUE INDEX "index_practice_attempts_on_client_attempt_id" ON "practice_attempts" ("client_attempt_id");
CREATE TABLE "practice_gradings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "practice_attempt_id" integer NOT NULL, "seq" integer NOT NULL, "verdict" varchar NOT NULL, "error_codes_json" text, "form_violations_json" text, "normalized" text, "method" varchar, "grader" varchar NOT NULL, "grader_version" varchar NOT NULL, "ce_version" varchar, "source" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_78df2809fa"
FOREIGN KEY ("practice_attempt_id")
  REFERENCES "practice_attempts" ("id")
, CONSTRAINT practice_gradings_source CHECK (source IN ('sync','retry')), CONSTRAINT practice_gradings_method CHECK (method IS NULL OR method IN ('exact','float')));
CREATE INDEX "index_practice_gradings_on_practice_attempt_id" ON "practice_gradings" ("practice_attempt_id");
CREATE UNIQUE INDEX "index_practice_gradings_on_practice_attempt_id_and_seq" ON "practice_gradings" ("practice_attempt_id", "seq");
CREATE TABLE "practice_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "student_id" integer NOT NULL, "kind" varchar NOT NULL, "practice_serve_id" integer, "topic_revision_id" integer, "lesson_revision_id" integer, "payload_json" text NOT NULL, "at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_98d31be146"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
, CONSTRAINT "fk_rails_c0429231ab"
FOREIGN KEY ("practice_serve_id")
  REFERENCES "practice_serves" ("id")
, CONSTRAINT "fk_rails_e02e028a87"
FOREIGN KEY ("topic_revision_id")
  REFERENCES "topic_revisions" ("id")
, CONSTRAINT "fk_rails_1ad12539cc"
FOREIGN KEY ("lesson_revision_id")
  REFERENCES "lesson_revisions" ("id")
, CONSTRAINT practice_events_kind CHECK (kind IN ('lesson_opened','lesson_solution_shown','hint_shown','solution_shown')), CONSTRAINT practice_events_serve CHECK (kind NOT IN ('hint_shown','solution_shown') OR practice_serve_id IS NOT NULL), CONSTRAINT practice_events_lesson CHECK (kind NOT IN ('lesson_opened','lesson_solution_shown') OR (lesson_revision_id IS NOT NULL AND topic_revision_id IS NOT NULL)));
CREATE INDEX "index_practice_events_on_student_id" ON "practice_events" ("student_id");
CREATE INDEX "index_practice_events_on_practice_serve_id" ON "practice_events" ("practice_serve_id");
CREATE INDEX "index_practice_events_on_topic_revision_id" ON "practice_events" ("topic_revision_id");
CREATE INDEX "index_practice_events_on_lesson_revision_id" ON "practice_events" ("lesson_revision_id");
CREATE TABLE "student_questions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "student_id" integer NOT NULL, "client_question_id" varchar NOT NULL, "topic_revision_id" integer, "lesson_revision_id" integer, "practice_serve_id" integer, "section" varchar, "exercise" integer, "text_it" text, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_731cd3820e"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
, CONSTRAINT "fk_rails_de96d5a88b"
FOREIGN KEY ("topic_revision_id")
  REFERENCES "topic_revisions" ("id")
, CONSTRAINT "fk_rails_97c2fca46e"
FOREIGN KEY ("lesson_revision_id")
  REFERENCES "lesson_revisions" ("id")
, CONSTRAINT "fk_rails_687ca3736c"
FOREIGN KEY ("practice_serve_id")
  REFERENCES "practice_serves" ("id")
, CONSTRAINT student_questions_section CHECK (section IS NULL OR section IN ('why','idea','example','mistakes','try','solutions','book','summary','practice')), CONSTRAINT student_questions_text_length CHECK (text_it IS NULL OR length(text_it) BETWEEN 1 AND 300));
CREATE INDEX "index_student_questions_on_student_id" ON "student_questions" ("student_id");
CREATE INDEX "index_student_questions_on_topic_revision_id" ON "student_questions" ("topic_revision_id");
CREATE INDEX "index_student_questions_on_lesson_revision_id" ON "student_questions" ("lesson_revision_id");
CREATE INDEX "index_student_questions_on_practice_serve_id" ON "student_questions" ("practice_serve_id");
CREATE UNIQUE INDEX "index_student_questions_on_client_question_id" ON "student_questions" ("client_question_id");
CREATE TRIGGER practice_serves_no_update BEFORE UPDATE ON practice_serves
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER practice_serves_no_delete BEFORE DELETE ON practice_serves
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER practice_attempts_no_update BEFORE UPDATE ON practice_attempts
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER practice_attempts_no_delete BEFORE DELETE ON practice_attempts
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER practice_gradings_no_update BEFORE UPDATE ON practice_gradings
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER practice_gradings_no_delete BEFORE DELETE ON practice_gradings
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER practice_events_no_update BEFORE UPDATE ON practice_events
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER practice_events_no_delete BEFORE DELETE ON practice_events
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER student_questions_no_update BEFORE UPDATE ON student_questions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER student_questions_no_delete BEFORE DELETE ON student_questions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "lesson_renders" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "lesson_revision_id" integer NOT NULL, "status" varchar NOT NULL, "rules_version" varchar, "harness_version" varchar NOT NULL, "chrome_version" varchar, "attempt" integer, "result_json" text NOT NULL, "shots_json" text NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_c2685b4828"
FOREIGN KEY ("lesson_revision_id")
  REFERENCES "lesson_revisions" ("id")
, CONSTRAINT lesson_renders_status CHECK (status IN ('passed','failed','error')));
CREATE INDEX "index_lesson_renders_on_lesson_revision_id" ON "lesson_renders" ("lesson_revision_id") /*application='Banco'*/;
CREATE INDEX "index_lesson_renders_on_lesson_revision_id_and_id" ON "lesson_renders" ("lesson_revision_id", "id") /*application='Banco'*/;
CREATE TRIGGER lesson_renders_no_update BEFORE UPDATE ON lesson_renders
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER lesson_renders_no_delete BEFORE DELETE ON lesson_renders
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
INSERT INTO "schema_migrations" (version) VALUES
('20261010120001'),
('20261009100003'),
('20261009100002'),
('20261009100001'),
('20261008200002'),
('20261008200001'),
('20261008100001'),
('20261007100001'),
('20261004300001'),
('20261004200001'),
('20261004100001'),
('20261003300001'),
('20261003200001'),
('20261003100004'),
('20261003100003'),
('20261003100002'),
('20261003100001');

