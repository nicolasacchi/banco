require "test_helper"
require_relative "../../support/student_export_world"
require_relative "../../support/zip_reader"

# D-360: «Scarica i miei dati». The zip holds every row about the student and nothing of anyone else; every table of db/structure.sql that
# holds a student's rows is in it (or the test fails and says which), and a table that is not about a student says why.
class StudentExportTest < ActiveSupport::TestCase
  include StudentExportWorld

  SCHEMA = Rails.root.join("db/structure.sql").read
  # { table => its CREATE TABLE body } from the committed schema, the same file bin/check-structure guards.
  TABLES = SCHEMA.scan(/^CREATE TABLE "(\w+)" \((.*?)\);$/m).to_h.freeze

  setup { build_export_world }

  def export(of = student) = Privacy::StudentExport.new(of)

  def archive(of = student) = ZipReader.read(export(of).zip)

  def json(name, of = student) = JSON.parse(archive(of).fetch(name))

  # ---- the schema ---------------------------------------------------------------------------------------

  test "the schema is read whole" do
    assert_operator TABLES.size, :>=, 55
    assert_includes TABLES.keys, "practice_attempts"
  end

  test "every table that has a student_id is exported" do
    with_student = TABLES.select { |_, body| body.include?('"student_id" integer') }.keys
    assert_includes with_student, "attempts"
    assert_empty with_student - Privacy::StudentExport.table_names,
                 "these tables hold a student's rows and are not in the export: add them to Privacy::StudentExport::TABLES (and its README line)"
  end

  test "every table is exported or listed as not about a student, with the reason, and never both" do
    exported = Privacy::StudentExport.table_names
    listed = Privacy::StudentExport::NOT_EXPORTED.keys
    assert_empty TABLES.keys - exported - listed, "a new table: export it (TABLES) or say why not (NOT_EXPORTED_BY_REASON)"
    assert_empty exported + listed - TABLES.keys, "the export names a table that is not in the schema"
    assert_empty exported & listed
    assert(Privacy::StudentExport::NOT_EXPORTED.values.all?(&:present?))
  end

  test "a table that hangs from a student's table by a foreign key is exported too" do
    exported = Privacy::StudentExport.table_names
    hanging = TABLES.reject { |name, _| exported.include?(name) }.select { |_, body| (body.scan(/REFERENCES "(\w+)"/).flatten & exported).any? }.keys
    assert_empty hanging, "these tables point to rows of the student's tables: export them or restructure"
  end

  test "every export table has its JSON file and its line in the README" do
    files = archive
    readme = files.fetch("README.txt")
    Privacy::StudentExport::TABLES.each do |table|
      assert files.key?(table.path), table.path
      assert_includes readme, "- #{table.path}: ", table.name
    end
    assert_includes files.keys, "preferences.json"
    assert_equal %w[README.txt riepilogo.html preferences.json], files.keys.first(3)
  end

  # ---- his rows -------------------------------------------------------------------------------------------

  test "every table of the export has at least his one row in the test world, and every file is a JSON array of objects" do
    counts = export.counts
    Privacy::StudentExport::TABLES.each do |table|
      assert_operator counts.fetch(table.name), :>=, 1, "#{table.name} has no row in the world: add one to LedgerRows or StudentExportWorld"
      data = json(table.path)
      assert_kind_of Array, data, table.path
      assert(data.all?(Hash), table.path)
    end
  end

  test "the student, his answers and the readable names" do
    assert_equal [ { "id" => student.id, "key" => "student", "kind" => "student", "created_at" => student.reload.created_at.utc.iso8601(6) } ], json("student.json")
    attempt = json("attempts.json").sole
    assert_equal [ "42", "diagnosis", "item-1", 1 ], attempt.values_at("raw", "context", "item_key", "item_revision")
    assert_equal "math", json("diagnosis_runs.json").sole["subject_key"]
    serve = json("practice_serves.json").sole
    assert_equal [ "ripasso.math.demo", "item-1" ], serve.values_at("lesson_key", "item_key")
    assert_equal "42", json("practice_attempts.json").sole["raw"]
    assert_equal "correct", json("practice_gradings.json").sole["verdict"]
    assert_equal "Non ho capito.", json("student_questions.json").sole["text_it"]
    assert_equal({ "n" => 1, "auto" => false }, json("practice_events.json").sole["payload"])
  end

  test "the preferences: the ones in force and every change" do
    prefs = json("preferences.json")
    assert_equal [ "dark", "large", "en" ], prefs["current"].values_at("theme", "size", "language")
    assert_equal [ "dark", "dark" ], prefs["history"].map { |entry| entry["theme"] }
    assert_equal [ "it", "en" ], prefs["history"].map { |entry| entry["language"] }, "the second change is the language"
    assert(prefs["history"].all? { |entry| entry["at"].present? })
  end

  test "the app events about him: his reminders and downloads, not the teacher's own events" do
    kinds = json("app_events.json").map { |event| event["kind"] }
    assert_includes kinds, "practice_reminder_shown"
    assert_includes kinds, "student_preference"
    assert_not_includes kinds, "teacher_viewed_item"
  end

  test "the teacher's decisions about him are there, with who and when, and none about anyone else" do
    decisions = json("decisions.json")
    assert_equal [ "record_consent" ], decisions.map { |d| d["kind"] }
    consent = decisions.sole
    assert_equal [ "nik", "api" ], consent.values_at("teacher_login", "via")
    assert_equal "Consenso dei genitori.", consent["payload"]["reason_it"]
    assert consent["created_at"].present?
  end

  test "the comments with every event: the teacher's replies, his own answer and his address only on that one" do
    comments = json("comments.json")
    assert_equal [ "today" ], comments.map { |c| c["page_kind"] }
    events = json("comment_events.json")
    assert_equal %w[read reply resolved student_reply], events.map { |e| e["kind"] }
    assert_equal "Ecco la risposta del docente.", events.find { |e| e["kind"] == "reply" }["text_it"]
    assert_equal({ "student_reply" => OWN_ADDR }, events.select { |e| e.key?("remote_addr") }.to_h { |e| [ e["kind"], e["remote_addr"] ] })
  end

  # ---- what is not in the file ----------------------------------------------------------------------------

  test "nothing of another student is in any file" do
    archive.each { |name, content| assert_not_includes content, OTHER_MARKER, name }
    assert_equal [ student.id ], json("student.json").map { |row| row["id"] }
    %w[attempts comments practice_serves practice_attempts lesson_events student_questions app_events decisions].each do |file|
      assert(json("#{file}.json").all? { |row| row["student_id"].nil? || row["student_id"] == student.id }, file)
    end
    assert_equal 1, json("attempts.json").size
    mine = json("comments.json").map { |c| c["id"] }
    assert(json("comment_events.json").all? { |e| mine.include?(e["comment_id"]) })
    assert_equal [ other.id ], json("student.json", other).map { |row| row["id"] }
    assert_includes archive(other).fetch("attempts.json"), OTHER_MARKER
    assert_not_includes archive(other).values.join, "\"42\""
  end

  test "no network address of the teacher or a bot, no user agent, no request id, no token, no seed, no answer key" do
    text = archive.values.join("\n")
    [ TEACHER_ADDR, BOT_ADDR, TEACHER_AGENT, TOKEN_ID, "req-export", "banco-teacher", "/teacher/decisions", "seed_salt", "\"salt\"", "answer_json", "f" * 64 ].each do |secret|
      assert_not_includes text, secret
    end
    assert_includes text, OWN_ADDR
    assert_not_includes json("practice_serves.json").sole.keys, "seed"
    assert_not_includes json("grade_proposals.json").sole.keys, "agent_session_id"
  end

  test "the README and the summary are in Italian, say what each file is and what is left out, and the summary counts per kind" do
    files = archive
    readme = files.fetch("README.txt")
    assert_includes readme, "I dati di banco su student"
    assert_includes readme, "Che cosa non c'è, e perché"
    assert_includes readme, "- comments.json: i commenti che hai scritto"
    assert_includes readme, "Il cookie del dispositivo"
    assert_includes readme, "Le parole che cerchi: banco non le conserva."
    html = files.fetch("riepilogo.html")
    assert_includes html, "<html lang=\"it\">"
    assert_includes html, "<code>attempts.json</code></td><td>1</td>"
    assert_includes html, "hint_shown: 1"
    assert_includes html, "student_reply: 1"
    assert_no_match(%r{https?://}, html)
  end

  test "the file name carries the key and the day, and the preview student has no export" do
    now = Time.utc(2026, 11, 18, 14, 3)
    assert_equal "banco-dati-student-2026-11-18.zip", Privacy::StudentExport.new(student, now: now).filename
    assert_includes Privacy::StudentExport.new(student, now: now).readme, "18/11/2026 alle 14:03"
    assert_raises(ArgumentError) { Privacy::StudentExport.new(Student.create!(key: "preview", kind: "preview")) }
  end

  # ---- read-only ------------------------------------------------------------------------------------------

  test "building the zip writes nothing; recording a download is one app event with who and when" do
    tables = ActiveRecord::Base.connection.tables - %w[sqlite_sequence]
    before = tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] }
    export.zip
    assert_equal before, tables.to_h { |t| [ t, ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{t}") ] }

    assert_difference -> { AppEvent.where(kind: "data_export").count }, 1 do
      assert_no_difference -> { Decision.count + Attempt.count + Comment.count } do
        Privacy::StudentExport.record!(student, by: "teacher", login: "nik")
      end
    end
    event = AppEvent.where(kind: "data_export").sole
    assert_equal student.id, event.student_id
    assert_equal({ "by" => "teacher", "login" => "nik" }, JSON.parse(event.payload_json))
    assert_raises(ArgumentError) { Privacy::StudentExport.record!(student, by: "someone") }
    assert_includes json("app_events.json").map { |e| e["kind"] }, "data_export"
  end
end
