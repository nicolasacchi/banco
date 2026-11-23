require "test_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20261123100000_add_student_withdrawn_comment_event")

# D-397: `student_withdrawn` is a kind of comment event, the student's own (origin student). SQLite cannot change a CHECK in place, so the migration
# rebuilds comment_events. This runs it on a scratch database made from db/structure.sql with the old CHECKs and a few rows, inside a transaction
# like the real migrator, and proves the rows, the ids, the foreign key and the append-only triggers survive (as AddChangelogCommentPageMigrationTest does).
class AddStudentWithdrawnCommentEventMigrationTest < ActiveSupport::TestCase
  M = AddStudentWithdrawnCommentEvent

  setup do
    @verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    @dir = Dir.mktmpdir("withdrawn-comment-migration")
    @conn = ActiveRecord::ConnectionAdapters::SQLite3Adapter.new(adapter: "sqlite3", database: File.join(@dir, "scratch.sqlite3"))
    structure = File.read(Rails.root.join("db/structure.sql"))
    assert_includes structure, M::KIND_NEW, "db/structure.sql has the new kind CHECK"
    assert_includes structure, M::STUDENT_NEW, "db/structure.sql has the new student CHECK"
    @conn.raw_connection.execute_batch(structure.sub(M::KIND_NEW, M::KIND_OLD).sub(M::STUDENT_NEW, M::STUDENT_OLD))
    @conn.execute("PRAGMA foreign_keys = ON")
    @conn.execute("INSERT INTO students (id, key, kind, created_at) VALUES (1, 'student', 'student', '2026-11-23')")
    @conn.execute("INSERT INTO comments (id, student_id, client_comment_id, reason, text_it, page_path, page_kind, created_at) VALUES " \
                  "(5, 1, 'c-00000005', 'error', 'Un errore', '/today', 'today', '2026-11-23'), (8, 1, 'c-00000008', 'like', NULL, '/today', 'today', '2026-11-23')")
    @conn.execute("INSERT INTO comment_events (id, comment_id, kind, origin, actor, text_it, created_at) VALUES (3, 5, 'reply', 'web', 'nik', 'Ecco.', '2026-11-23')")
  end

  teardown do
    ActiveRecord::Migration.verbose = @verbose
    @conn.disconnect!
    FileUtils.remove_entry(@dir)
  end

  def migrate(direction) = @conn.transaction { M.new.exec_migration(@conn, direction) }

  def withdraw(comment_id, origin: "student")
    @conn.execute("INSERT INTO comment_events (comment_id, kind, origin, actor, created_at) VALUES (#{comment_id}, 'student_withdrawn', '#{origin}', 'student', '2026-11-23')")
  end

  test "before the migration the kind is refused" do
    assert_raises(ActiveRecord::StatementInvalid) { withdraw(8) }
  end

  test "the rebuild takes the kind from the student alone, still refuses another kind, and keeps rows, ids and the foreign key" do
    migrate(:up)
    assert_equal [ [ 3, 5, "reply", "Ecco." ] ], @conn.select_rows("SELECT id, comment_id, kind, text_it FROM comment_events")
    assert_empty @conn.select_rows("PRAGMA foreign_key_check")
    assert_nothing_raised { withdraw(8) }
    %w[web api console].each { |origin| assert_raises(ActiveRecord::StatementInvalid, origin) { withdraw(8, origin: origin) } }
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("INSERT INTO comment_events (comment_id, kind, origin, actor, created_at) VALUES (8, 'student_vanished', 'student', 'student', '2026-11-23')") }
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("INSERT INTO comment_events (comment_id, kind, origin, actor, created_at) VALUES (8, 'read', 'student', 'student', '2026-11-23')") }
    assert_nothing_raised { @conn.execute("INSERT INTO comment_events (comment_id, kind, origin, actor, text_it, created_at) VALUES (8, 'student_reply', 'student', 'student', 'Grazie.', '2026-11-23')") }
    assert_equal 4, @conn.select_value("SELECT min(id) FROM comment_events WHERE id > 3"), "ids continue after the highest"
  end

  test "the rebuilt table is append-only and still enforces the foreign key" do
    migrate(:up)
    withdraw(8)
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("UPDATE comment_events SET actor = 'x' WHERE kind = 'student_withdrawn'") }
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("DELETE FROM comment_events WHERE kind = 'student_withdrawn'") }
    assert_raises(ActiveRecord::InvalidForeignKey) { withdraw(4242) }
  end

  test "down is refused once a comment was withdrawn, and works before" do
    migrate(:up)
    withdraw(8)
    assert_raises(ActiveRecord::IrreversibleMigration) { migrate(:down) }
  end

  test "down restores the old CHECKs when no comment was withdrawn" do
    migrate(:up)
    migrate(:down)
    assert_raises(ActiveRecord::StatementInvalid) { withdraw(8) }
    assert_equal [ [ 3 ] ], @conn.select_rows("SELECT id FROM comment_events")
  end
end
