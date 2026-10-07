CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY);
CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL);
CREATE TABLE "subjects" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "name_it" varchar NOT NULL, "position" integer NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_subjects_on_key" ON "subjects" ("key") /*application='Banco'*/;
CREATE TABLE "syllabus_sources" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "line_count" integer NOT NULL, "sha256" varchar(64) NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_syllabus_sources_on_key" ON "syllabus_sources" ("key") /*application='Banco'*/;
CREATE TABLE "syllabus_lines" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "syllabus_source_id" integer NOT NULL, "number" integer NOT NULL, "text" text NOT NULL, "origin" varchar NOT NULL, "marker" varchar, "parts_json" text, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_337129165a"
FOREIGN KEY ("syllabus_source_id")
  REFERENCES "syllabus_sources" ("id")
, CONSTRAINT syllabus_lines_origin CHECK (origin IN ('pdf','transcript','operator')));
CREATE INDEX "index_syllabus_lines_on_syllabus_source_id" ON "syllabus_lines" ("syllabus_source_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_syllabus_lines_on_syllabus_source_id_and_number" ON "syllabus_lines" ("syllabus_source_id", "number") /*application='Banco'*/;
CREATE TABLE "reference_texts" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "title" varchar NOT NULL, "source_url" varchar NOT NULL, "sha256" varchar(64) NOT NULL, "body" text NOT NULL, "created_at" datetime(6) NOT NULL);
CREATE UNIQUE INDEX "index_reference_texts_on_key" ON "reference_texts" ("key") /*application='Banco'*/;
CREATE TABLE "skill_graph_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "seq" integer NOT NULL, "body_json" text NOT NULL, "author_session_id" integer, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_511ad51e6c"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
);
CREATE INDEX "index_skill_graph_revisions_on_subject_id" ON "skill_graph_revisions" ("subject_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_skill_graph_revisions_on_subject_id_and_seq" ON "skill_graph_revisions" ("subject_id", "seq") /*application='Banco'*/;
CREATE TABLE "items" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "key" varchar NOT NULL, "kind" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_2f63756365"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
);
CREATE INDEX "index_items_on_subject_id" ON "items" ("subject_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_items_on_key" ON "items" ("key") /*application='Banco'*/;
CREATE TABLE "item_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_id" integer NOT NULL, "seq" integer NOT NULL, "base_revision_id" integer, "body_json" text NOT NULL, "author_session_id" integer, "file_sessions_json" text, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, "files_json" text /*application='Banco'*/, CONSTRAINT "fk_rails_0ac7a4cb2d"
FOREIGN KEY ("item_id")
  REFERENCES "items" ("id")
);
CREATE INDEX "index_item_revisions_on_item_id" ON "item_revisions" ("item_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_item_revisions_on_item_id_and_seq" ON "item_revisions" ("item_id", "seq") /*application='Banco'*/;
CREATE TABLE "item_validations" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "seq" integer NOT NULL, "status" varchar NOT NULL, "codes_json" text, "created_at" datetime(6) NOT NULL, "findings_json" text /*application='Banco'*/, "rules_version" varchar /*application='Banco'*/, "grader_version" varchar /*application='Banco'*/, "harness_version" varchar /*application='Banco'*/, "chrome_version" varchar /*application='Banco'*/, "instances_sha256" varchar(64) /*application='Banco'*/, "attempt" integer /*application='Banco'*/, CONSTRAINT "fk_rails_3879210719"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
);
CREATE INDEX "index_item_validations_on_item_revision_id" ON "item_validations" ("item_revision_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_item_validations_on_item_revision_id_and_seq" ON "item_validations" ("item_revision_id", "seq") /*application='Banco'*/;
CREATE TABLE "item_instances" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "seed" integer, "display_json" text NOT NULL, "answer_json" text NOT NULL, "errors_json" text, "solution_json" text, "fingerprint" varchar(64) NOT NULL, "created_at" datetime(6) NOT NULL, "accept_json" text, CONSTRAINT "fk_rails_07564fabf6"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
);
CREATE INDEX "index_item_instances_on_item_revision_id" ON "item_instances" ("item_revision_id") /*application='Banco'*/;
CREATE INDEX "index_item_instances_on_item_revision_id_and_fingerprint" ON "item_instances" ("item_revision_id", "fingerprint") /*application='Banco'*/;
CREATE TABLE "blueprint_revisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "subject_id" integer NOT NULL, "skill_graph_revision_id" integer NOT NULL, "seq" integer NOT NULL, "body_json" text NOT NULL, "author_session_id" integer, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_320fc6e2d7"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
, CONSTRAINT "fk_rails_77b7161d1c"
FOREIGN KEY ("skill_graph_revision_id")
  REFERENCES "skill_graph_revisions" ("id")
);
CREATE INDEX "index_blueprint_revisions_on_subject_id" ON "blueprint_revisions" ("subject_id") /*application='Banco'*/;
CREATE INDEX "index_blueprint_revisions_on_skill_graph_revision_id" ON "blueprint_revisions" ("skill_graph_revision_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_blueprint_revisions_on_subject_id_and_seq" ON "blueprint_revisions" ("subject_id", "seq") /*application='Banco'*/;
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
CREATE TABLE "agent_sessions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "label" varchar NOT NULL, "role" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "agent" varchar /*application='Banco'*/, "model" varchar /*application='Banco'*/, "token_id" varchar, CONSTRAINT agent_sessions_role CHECK (role IN ('author','verifier','reviewer','solver','grader','operator')));
CREATE TRIGGER agent_sessions_no_update BEFORE UPDATE ON agent_sessions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TRIGGER agent_sessions_no_delete BEFORE DELETE ON agent_sessions
BEGIN SELECT RAISE(ABORT, 'append-only'); END;
CREATE TABLE "students" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "key" varchar NOT NULL, "kind" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT students_kind CHECK (kind IN ('student','preview')));
CREATE UNIQUE INDEX "index_students_on_key" ON "students" ("key") /*application='Banco'*/;
CREATE TABLE "decisions" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "subject_id" integer, "student_id" integer, "payload_json" text NOT NULL, "request_id" varchar NOT NULL, "teacher_login" varchar NOT NULL, "remote_addr" varchar NOT NULL, "created_at" datetime(6) NOT NULL, "groups" varchar DEFAULT '' NOT NULL /*application='Banco'*/, "user_agent" varchar DEFAULT '' NOT NULL /*application='Banco'*/, "request_path" varchar DEFAULT '' NOT NULL /*application='Banco'*/, CONSTRAINT "fk_rails_7a1a6ec8a0"
FOREIGN KEY ("subject_id")
  REFERENCES "subjects" ("id")
, CONSTRAINT "fk_rails_00cea4747f"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
);
CREATE INDEX "index_decisions_on_subject_id" ON "decisions" ("subject_id") /*application='Banco'*/;
CREATE INDEX "index_decisions_on_student_id" ON "decisions" ("student_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_decisions_on_request_id" ON "decisions" ("request_id") /*application='Banco'*/;
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
CREATE INDEX "index_diagnosis_runs_on_student_id" ON "diagnosis_runs" ("student_id") /*application='Banco'*/;
CREATE INDEX "index_diagnosis_runs_on_subject_id" ON "diagnosis_runs" ("subject_id") /*application='Banco'*/;
CREATE INDEX "index_diagnosis_runs_on_blueprint_revision_id" ON "diagnosis_runs" ("blueprint_revision_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_diagnosis_runs_on_student_id_and_subject_id_and_sequence" ON "diagnosis_runs" ("student_id", "subject_id", "sequence") /*application='Banco'*/;
CREATE TABLE "diagnosis_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "diagnosis_run_id" integer NOT NULL, "seq" integer NOT NULL, "kind" varchar NOT NULL, "payload_json" text, "at" datetime(6) NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_d98a18cb07"
FOREIGN KEY ("diagnosis_run_id")
  REFERENCES "diagnosis_runs" ("id")
);
CREATE INDEX "index_diagnosis_events_on_diagnosis_run_id" ON "diagnosis_events" ("diagnosis_run_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_diagnosis_events_on_diagnosis_run_id_and_seq" ON "diagnosis_events" ("diagnosis_run_id", "seq") /*application='Banco'*/;
CREATE TABLE "item_served" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "diagnosis_event_id" integer NOT NULL, "item_instance_id" integer NOT NULL, "skill_key" varchar NOT NULL, "shown_order_json" text, "id_map_json" text, "created_at" datetime(6) NOT NULL, "formula_sheet_available" boolean DEFAULT FALSE NOT NULL, CONSTRAINT "fk_rails_b8f6754796"
FOREIGN KEY ("diagnosis_event_id")
  REFERENCES "diagnosis_events" ("id")
, CONSTRAINT "fk_rails_af0a6a9d92"
FOREIGN KEY ("item_instance_id")
  REFERENCES "item_instances" ("id")
);
CREATE UNIQUE INDEX "index_item_served_on_diagnosis_event_id" ON "item_served" ("diagnosis_event_id") /*application='Banco'*/;
CREATE INDEX "index_item_served_on_item_instance_id" ON "item_served" ("item_instance_id") /*application='Banco'*/;
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
CREATE INDEX "index_attempts_on_student_id" ON "attempts" ("student_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_attempts_on_served_event_id" ON "attempts" ("served_event_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_attempts_on_client_attempt_id" ON "attempts" ("client_attempt_id") /*application='Banco'*/;
CREATE INDEX "index_attempts_on_item_instance_id" ON "attempts" ("item_instance_id") /*application='Banco'*/;
CREATE TABLE "attempt_gradings" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "attempt_id" integer NOT NULL, "seq" integer NOT NULL, "verdict" varchar NOT NULL, "error_codes_json" text, "form_violations_json" text, "normalized" text, "method" varchar, "grader" varchar NOT NULL, "grader_version" varchar NOT NULL, "ce_version" varchar, "source" varchar NOT NULL, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_3c97fc2b8c"
FOREIGN KEY ("attempt_id")
  REFERENCES "attempts" ("id")
, CONSTRAINT attempt_gradings_source CHECK (source IN ('sync','retry')), CONSTRAINT attempt_gradings_method CHECK (method IS NULL OR method IN ('exact','float')));
CREATE INDEX "index_attempt_gradings_on_attempt_id" ON "attempt_gradings" ("attempt_id") /*application='Banco'*/;
CREATE UNIQUE INDEX "index_attempt_gradings_on_attempt_id_and_seq" ON "attempt_gradings" ("attempt_id", "seq") /*application='Banco'*/;
CREATE TABLE "app_events" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "kind" varchar NOT NULL, "student_id" integer, "payload_json" text, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_783009c2fd"
FOREIGN KEY ("student_id")
  REFERENCES "students" ("id")
);
CREATE INDEX "index_app_events_on_student_id" ON "app_events" ("student_id") /*application='Banco'*/;
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
CREATE UNIQUE INDEX "index_api_tokens_on_public_id" ON "api_tokens" ("public_id") /*application='Banco'*/;
CREATE TABLE "api_token_revocations" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "api_token_id" integer NOT NULL, "reason" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_b9e431c1e1"
FOREIGN KEY ("api_token_id")
  REFERENCES "api_tokens" ("id")
);
CREATE UNIQUE INDEX "index_api_token_revocations_on_api_token_id" ON "api_token_revocations" ("api_token_id") /*application='Banco'*/;
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
CREATE INDEX "index_item_reviews_on_item_revision_id" ON "item_reviews" ("item_revision_id") /*application='Banco'*/;
CREATE INDEX "index_item_reviews_on_agent_session_id" ON "item_reviews" ("agent_session_id") /*application='Banco'*/;
CREATE TABLE "blind_solves" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "item_revision_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "answers_json" text NOT NULL, "results_json" text NOT NULL, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_cc8f34abcd"
FOREIGN KEY ("item_revision_id")
  REFERENCES "item_revisions" ("id")
, CONSTRAINT "fk_rails_2bc0056230"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_blind_solves_on_item_revision_id" ON "blind_solves" ("item_revision_id") /*application='Banco'*/;
CREATE INDEX "index_blind_solves_on_agent_session_id" ON "blind_solves" ("agent_session_id") /*application='Banco'*/;
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
CREATE INDEX "index_review_findings_on_item_revision_id" ON "review_findings" ("item_revision_id") /*application='Banco'*/;
CREATE INDEX "index_review_findings_on_item_review_id" ON "review_findings" ("item_review_id") /*application='Banco'*/;
CREATE INDEX "index_review_findings_on_blind_solve_id" ON "review_findings" ("blind_solve_id") /*application='Banco'*/;
CREATE TABLE "grade_proposals" ("id" integer PRIMARY KEY AUTOINCREMENT NOT NULL, "attempt_id" integer NOT NULL, "agent_session_id" integer NOT NULL, "points_json" text NOT NULL, "missing_it" text, "total" integer NOT NULL, "max_total" integer NOT NULL, "threshold" float NOT NULL, "meets_threshold" boolean NOT NULL, "brief_sha256" varchar, "created_at" datetime(6) NOT NULL, CONSTRAINT "fk_rails_6b13eee236"
FOREIGN KEY ("attempt_id")
  REFERENCES "attempts" ("id")
, CONSTRAINT "fk_rails_36d8f549cd"
FOREIGN KEY ("agent_session_id")
  REFERENCES "agent_sessions" ("id")
);
CREATE INDEX "index_grade_proposals_on_attempt_id" ON "grade_proposals" ("attempt_id") /*application='Banco'*/;
CREATE INDEX "index_grade_proposals_on_agent_session_id" ON "grade_proposals" ("agent_session_id") /*application='Banco'*/;
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
INSERT INTO "schema_migrations" (version) VALUES
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

