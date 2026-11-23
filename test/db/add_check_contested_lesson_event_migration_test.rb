require "test_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20261123200000_add_check_contested_lesson_event")

# D-396: `check_contested` is a kind of lesson event («Per me va bene così» on a check of a lesson/2). SQLite cannot change a CHECK in place, so the migration
# rebuilds lesson_events. This runs it on a scratch database made from db/structure.sql with the old CHECKs and a few rows, inside a transaction like the
# real migrator, and proves the rows, the ids, the foreign keys and the append-only triggers survive (as AddChangelogCommentPageMigrationTest does).
class AddCheckContestedLessonEventMigrationTest < ActiveSupport::TestCase
  M = AddCheckContestedLessonEvent

  setup do
    @verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    @dir = Dir.mktmpdir("check-contested-migration")
    @conn = ActiveRecord::ConnectionAdapters::SQLite3Adapter.new(adapter: "sqlite3", database: File.join(@dir, "scratch.sqlite3"))
    structure = File.read(Rails.root.join("db/structure.sql"))
    [ M::KIND_NEW, M::CARD_NEW, ", CONSTRAINT lesson_events_contest CHECK (#{M::CONTEST})" ].each { |new| assert_includes structure, new, "db/structure.sql has the new CHECKs" }
    structure = structure.sub(M::KIND_NEW, M::KIND_OLD).sub(M::CARD_NEW, M::CARD_OLD).sub(", CONSTRAINT lesson_events_contest CHECK (#{M::CONTEST})", "")
    @conn.raw_connection.execute_batch(structure)
    @conn.execute("PRAGMA foreign_keys = ON")
    seed_rows
  end

  teardown do
    ActiveRecord::Migration.verbose = @verbose
    @conn.disconnect!
    FileUtils.remove_entry(@dir)
  end

  def seed_rows
    now = "'2026-11-24'"
    @conn.execute("INSERT INTO students (id, key, kind, created_at) VALUES (1, 'student', 'student', #{now})")
    @conn.execute("INSERT INTO subjects (id, key, name_it, position, created_at) VALUES (1, 'math', 'Matematica', 1, #{now})")
    @conn.execute("INSERT INTO skill_graph_revisions (id, subject_id, seq, body_json, created_at) VALUES (1, 1, 1, '{}', #{now})")
    @conn.execute("INSERT INTO course_revisions (id, subject_id, seq, skill_graph_revision_id, body_json, warnings_json, created_at) VALUES (1, 1, 1, 1, '{}', '[]', #{now})")
    @conn.execute("INSERT INTO lessons (id, subject_id, key, kind, created_at) VALUES (1, 1, 'ripasso.math.demo', 'ripasso', #{now})")
    @conn.execute("INSERT INTO lesson_revisions (id, lesson_id, seq, source_md, source_sha256, body_json, rules_version, warnings_json, created_at) VALUES (1, 1, 1, '', '#{'a' * 64}', '{}', 'r', '[]', #{now})")
    @conn.execute("INSERT INTO topic_revisions (id, lesson_id, seq, course_revision_id, lesson_revision_id, body_json, created_at) VALUES (1, 1, 1, 1, 1, '{}', #{now})")
    @conn.execute("INSERT INTO lesson_events (id, student_id, topic_revision_id, lesson_revision_id, kind, card, block, payload_json, grader_version, at, created_at) VALUES " \
                  "(5, 1, 1, 1, 'check_answered', 2, 3, '{}', 'x', #{now}, #{now}), (8, 1, 1, 1, 'card_seen', 2, NULL, '{}', NULL, #{now}, #{now})")
  end

  def migrate(direction) = @conn.transaction { M.new.exec_migration(@conn, direction) }

  def insert_event(kind, card: 2, block: 3)
    @conn.execute("INSERT INTO lesson_events (student_id, topic_revision_id, lesson_revision_id, kind, card, block, payload_json, at, created_at) VALUES " \
                  "(1, 1, 1, '#{kind}', #{card || 'NULL'}, #{block || 'NULL'}, '{}', '2026-11-24', '2026-11-24')")
  end

  test "before the migration the kind is refused" do
    assert_raises(ActiveRecord::StatementInvalid) { insert_event("check_contested") }
  end

  test "the rebuild takes the kind, still refuses another, and keeps rows, ids and foreign keys" do
    migrate(:up)
    assert_equal [ [ 5, "check_answered" ], [ 8, "card_seen" ] ], @conn.select_rows("SELECT id, kind FROM lesson_events ORDER BY id")
    assert_empty @conn.select_rows("PRAGMA foreign_key_check")
    assert_nothing_raised { insert_event("check_contested") }
    assert_raises(ActiveRecord::StatementInvalid) { insert_event("sneaky") }
    assert_equal 9, @conn.select_value("SELECT min(id) FROM lesson_events WHERE id > 8"), "ids continue after the highest"
  end

  test "a contested check names its card and its block, as a card seen does" do
    migrate(:up)
    assert_raises(ActiveRecord::StatementInvalid) { insert_event("check_contested", card: nil) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_event("check_contested", block: nil) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_event("card_seen", card: nil) }
  end

  test "the rebuilt table is append-only and still enforces its foreign keys" do
    migrate(:up)
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("UPDATE lesson_events SET card = 9 WHERE id = 5") }
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("DELETE FROM lesson_events WHERE id = 8") }
    assert_raises(ActiveRecord::InvalidForeignKey) do
      @conn.execute("INSERT INTO lesson_events (student_id, topic_revision_id, lesson_revision_id, kind, card, payload_json, at, created_at) VALUES (4242, 1, 1, 'card_seen', 2, '{}', 'x', 'x')")
    end
  end

  test "down is refused once a check is contested, and works before" do
    migrate(:up)
    insert_event("check_contested")
    assert_raises(ActiveRecord::IrreversibleMigration) { migrate(:down) }
  end

  test "down restores the old CHECKs when no check is contested" do
    migrate(:up)
    migrate(:down)
    assert_raises(ActiveRecord::StatementInvalid) { insert_event("check_contested") }
    assert_nothing_raised { insert_event("card_seen") }
  end
end
