require "test_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20261118120000_widen_comment_text_and_add_page_kinds")

# D-361: a comment and a follow-up of the student may be 2000 characters, and `civics` and `not_found` are page kinds. SQLite cannot change a
# CHECK in place, so the migration rebuilds comments and comment_events. This test runs it on a scratch database made from db/structure.sql
# with the three old CHECKs and a few rows, inside a transaction like the real migrator, and proves the rows, the ids, the children's foreign
# keys and the append-only triggers survive (as ArbiterRoleMigrationTest does for agent_sessions).
class WidenCommentTextMigrationTest < ActiveSupport::TestCase
  M = WidenCommentTextAndAddPageKinds
  CHECKS = { M::KIND_NEW => M::KIND_OLD, M::TEXT_NEW => M::TEXT_OLD, M::REPLY_NEW => M::REPLY_OLD }.freeze

  setup do
    @verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    @dir = Dir.mktmpdir("widen-comment-migration")
    @conn = ActiveRecord::ConnectionAdapters::SQLite3Adapter.new(adapter: "sqlite3", database: File.join(@dir, "scratch.sqlite3"))
    structure = File.read(Rails.root.join("db/structure.sql"))
    CHECKS.each do |new, old|
      assert_includes structure, new
      structure = structure.sub(new, old)
    end
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
    @conn.execute("INSERT INTO students (id, key, kind, created_at) VALUES (1, 'student', 'student', '2026-11-18')")
    @conn.execute("INSERT INTO comments (id, student_id, client_comment_id, reason, text_it, page_path, page_kind, created_at) VALUES " \
                  "(5, 1, 'c-00000005', 'error', '#{'x' * 500}', '/privacy', 'privacy', '2026-11-18'), (8, 1, 'c-00000008', 'like', NULL, '/today', 'today', '2026-11-18')")
    @conn.execute("INSERT INTO comment_events (id, comment_id, kind, origin, actor, text_it, created_at) VALUES " \
                  "(3, 5, 'reply', 'web', 'nik', 'Ecco.', '2026-11-18'), (4, 5, 'student_reply', 'student', 'student', '#{'y' * 500}', '2026-11-18')")
  end

  def migrate(direction) = @conn.transaction { M.new.exec_migration(@conn, direction) }

  def insert_comment(text: "ok", kind: "today", id: "c-#{SecureRandom.hex(6)}")
    value = text.nil? ? "NULL" : "'#{text}'"
    @conn.execute("INSERT INTO comments (student_id, client_comment_id, reason, text_it, page_path, page_kind, created_at) VALUES (1, '#{id}', 'other', #{value}, '/x', '#{kind}', '2026-11-18')")
  end

  def insert_reply(text)
    @conn.execute("INSERT INTO comment_events (comment_id, kind, origin, actor, text_it, created_at) VALUES (5, 'student_reply', 'student', 'student', '#{text}', '2026-11-18')")
  end

  test "before the migration 501 characters, a follow-up of 501 and the new page kinds are refused" do
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(text: "x" * 501) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_reply("y" * 501) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(kind: "civics") }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(kind: "not_found") }
  end

  test "the rebuild takes 2000 characters and the two new page kinds, refuses 2001 and keeps rows, ids and children" do
    migrate(:up)
    assert_equal [ [ 5, 500, "privacy" ], [ 8, nil, "today" ] ], @conn.select_rows("SELECT id, length(text_it), page_kind FROM comments ORDER BY id")
    assert_equal [ [ 3, "reply", "Ecco." ], [ 4, "student_reply", "y" * 500 ] ], @conn.select_rows("SELECT id, kind, text_it FROM comment_events ORDER BY id")
    assert_equal [ [ 5 ], [ 5 ] ], @conn.select_rows("SELECT comment_id FROM comment_events ORDER BY id")
    assert_empty @conn.select_rows("PRAGMA foreign_key_check")
    assert_nothing_raised { insert_comment(text: "x" * 2000) }
    assert_nothing_raised { insert_comment(text: "x" * 1500, kind: "civics") }
    assert_nothing_raised { insert_comment(text: nil, kind: "not_found") }
    assert_nothing_raised { insert_reply("y" * 2000) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(text: "x" * 2001) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_reply("y" * 2001) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(text: "") }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(kind: "elsewhere") }
    assert_operator @conn.select_value("SELECT min(id) FROM comments WHERE id > 8"), :==, 9, "ids continue after the highest"
  end

  test "the children still enforce their foreign key to the rebuilt comments" do
    migrate(:up)
    assert_raises(ActiveRecord::InvalidForeignKey) do
      @conn.execute("INSERT INTO comment_events (comment_id, kind, origin, actor, text_it, created_at) VALUES (4242, 'reply', 'web', 'nik', 'x', '2026-11-18')")
    end
  end

  test "the append-only triggers are on both rebuilt tables and work; no other table loses its triggers" do
    before = @conn.select_values("SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name")
    migrate(:up)
    assert_equal before, @conn.select_values("SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name")
    { "comments" => 5, "comment_events" => 3 }.each do |table, id|
      assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("UPDATE #{table} SET created_at = created_at WHERE id = #{id}") }
      assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("DELETE FROM #{table} WHERE id = #{id}") }
    end
  end

  test "down restores the old checks when nothing needs the new ones, and is refused once a comment on a new page exists" do
    migrate(:up)
    migrate(:down)
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(text: "x" * 501) }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment(kind: "civics") }
    assert_equal 2, @conn.select_value("SELECT count(*) FROM comments")
    migrate(:up)
    insert_comment(kind: "not_found")
    assert_raises(ActiveRecord::IrreversibleMigration) { migrate(:down) }
  end

  test "down is refused for a long comment and for a long follow-up" do
    migrate(:up)
    insert_reply("y" * 800)
    assert_raises(ActiveRecord::IrreversibleMigration) { migrate(:down) }
  end

  test "down is refused for a long comment" do
    migrate(:up)
    insert_comment(text: "x" * 800)
    assert_raises(ActiveRecord::IrreversibleMigration) { migrate(:down) }
  end
end
