require "test_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20261119100000_add_schema_comment_pages")
require Rails.root.join("db/migrate/20261119153000_add_changelog_comment_page")

# D-372: `schema` and `schemas` are page kinds of a comment. SQLite cannot change a CHECK in place, so the migration rebuilds comments. This runs
# it on a scratch database made from db/structure.sql with the old CHECK and a few rows, inside a transaction like the real migrator, and proves
# the rows, the ids, the child's foreign key and the append-only triggers survive (as WidenCommentTextMigrationTest does).
class AddSchemaCommentPagesMigrationTest < ActiveSupport::TestCase
  M = AddSchemaCommentPages

  setup do
    @verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    @dir = Dir.mktmpdir("schema-comment-migration")
    @conn = ActiveRecord::ConnectionAdapters::SQLite3Adapter.new(adapter: "sqlite3", database: File.join(@dir, "scratch.sqlite3"))
    # db/structure.sql is after AddChangelogCommentPage (D-375), which added a page kind to the CHECK this migration made
    structure = File.read(Rails.root.join("db/structure.sql")).sub(AddChangelogCommentPage::KIND_NEW, AddChangelogCommentPage::KIND_OLD)
    assert_includes structure, M::KIND_NEW, "db/structure.sql has the new CHECK"
    @conn.raw_connection.execute_batch(structure.sub(M::KIND_NEW, M::KIND_OLD))
    @conn.execute("PRAGMA foreign_keys = ON")
    @conn.execute("INSERT INTO students (id, key, kind, created_at) VALUES (1, 'student', 'student', '2026-11-19')")
    @conn.execute("INSERT INTO comments (id, student_id, client_comment_id, reason, text_it, page_path, page_kind, created_at) VALUES " \
                  "(5, 1, 'c-00000005', 'error', 'Un errore', '/civics', 'civics', '2026-11-19'), (8, 1, 'c-00000008', 'like', NULL, '/today', 'today', '2026-11-19')")
    @conn.execute("INSERT INTO comment_events (id, comment_id, kind, origin, actor, text_it, created_at) VALUES (3, 5, 'reply', 'web', 'nik', 'Ecco.', '2026-11-19')")
  end

  teardown do
    ActiveRecord::Migration.verbose = @verbose
    @conn.disconnect!
    FileUtils.remove_entry(@dir)
  end

  def migrate(direction) = @conn.transaction { M.new.exec_migration(@conn, direction) }

  def insert_comment(kind, path: "/x")
    @conn.execute("INSERT INTO comments (student_id, client_comment_id, reason, text_it, page_path, page_kind, created_at) VALUES (1, 'c-#{SecureRandom.hex(6)}', 'other', 'ok', '#{path}', '#{kind}', '2026-11-19')")
  end

  test "before the migration the two schema page kinds are refused" do
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment("schema") }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment("schemas") }
  end

  test "the rebuild takes the two kinds, still refuses another, and keeps rows, ids and the child" do
    migrate(:up)
    assert_equal [ [ 5, "civics" ], [ 8, "today" ] ], @conn.select_rows("SELECT id, page_kind FROM comments ORDER BY id")
    assert_equal [ [ 3, 5, "Ecco." ] ], @conn.select_rows("SELECT id, comment_id, text_it FROM comment_events")
    assert_empty @conn.select_rows("PRAGMA foreign_key_check")
    assert_nothing_raised { insert_comment("schema", path: "/topics/ripasso.math.demo/schema") }
    assert_nothing_raised { insert_comment("schemas", path: "/schemas") }
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment("elsewhere") }
    assert_equal 9, @conn.select_value("SELECT min(id) FROM comments WHERE id > 8"), "ids continue after the highest"
  end

  test "the rebuilt table is append-only and its child still enforces the foreign key" do
    migrate(:up)
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("UPDATE comments SET reason = 'like' WHERE id = 5") }
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("DELETE FROM comments WHERE id = 8") }
    assert_raises(ActiveRecord::InvalidForeignKey) do
      @conn.execute("INSERT INTO comment_events (comment_id, kind, origin, actor, text_it, created_at) VALUES (4242, 'reply', 'web', 'nik', 'x', '2026-11-19')")
    end
  end

  test "down is refused once a comment is filed on a schema page, and works before" do
    migrate(:up)
    insert_comment("schemas", path: "/schemas")
    assert_raises(ActiveRecord::IrreversibleMigration) { migrate(:down) }
  end

  test "down restores the old CHECK when no comment is on a schema page" do
    migrate(:up)
    migrate(:down)
    assert_raises(ActiveRecord::StatementInvalid) { insert_comment("schema") }
    assert_nothing_raised { insert_comment("civics") }
  end
end
