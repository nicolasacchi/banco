require "test_helper"
require "tmpdir"
require Rails.root.join("db/migrate/20261008200001_add_arbiter_role")

# D-222: the agent_sessions role CHECK gains 'arbiter'. SQLite cannot change a CHECK in place, so the
# migration rebuilds the table. This test runs it on a scratch database made from db/structure.sql
# with the old CHECK and a few rows, inside a transaction like the real migrator, and proves the
# rows, the ids, the foreign keys of the children and the append-only triggers survive.
class ArbiterRoleMigrationTest < ActiveSupport::TestCase
  OLD_CHECK = "role IN ('author','verifier','reviewer','solver','grader','operator')".freeze
  NEW_CHECK = "role IN ('author','verifier','reviewer','solver','grader','operator','arbiter')".freeze

  setup do
    @verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    @dir = Dir.mktmpdir("arbiter-migration")
    @conn = ActiveRecord::ConnectionAdapters::SQLite3Adapter.new(adapter: "sqlite3", database: File.join(@dir, "scratch.sqlite3"))
    structure = File.read(Rails.root.join("db/structure.sql"))
    assert_includes structure, NEW_CHECK
    @conn.raw_connection.execute_batch(structure.sub(NEW_CHECK, OLD_CHECK))
    @conn.execute("PRAGMA foreign_keys = ON")
    seed_rows
  end

  teardown do
    ActiveRecord::Migration.verbose = @verbose
    @conn.disconnect!
    FileUtils.remove_entry(@dir)
  end

  def seed_rows
    @conn.execute("INSERT INTO subjects (id, key, name_it, position, created_at) VALUES (1, 'm', 'M', 1, '2026-10-08')")
    @conn.execute("INSERT INTO items (id, subject_id, key, kind, created_at) VALUES (1, 1, 'm-1', 'diagnosis_item', '2026-10-08')")
    @conn.execute("INSERT INTO agent_sessions (id, label, role, created_at, agent, model) VALUES (7, 'a', 'reviewer', '2026-10-08', 'omp', 'm1'), (9, 'b', 'solver', '2026-10-08', 'omp', 'm2')")
    @conn.execute("INSERT INTO item_revisions (id, item_id, seq, body_json, author_session_id, created_at) VALUES (1, 1, 1, '{}', 9, '2026-10-08')")
    @conn.execute("INSERT INTO item_reviews (id, item_revision_id, agent_session_id, checklist_json, created_at) VALUES (1, 1, 7, '[]', '2026-10-08')")
  end

  def migrate(direction)
    @conn.transaction { AddArbiterRole.new.exec_migration(@conn, direction) }
  end

  def role_sql = @conn.select_value("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'agent_sessions'")

  test "before the migration an arbiter row is refused" do
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("INSERT INTO agent_sessions (label, role, created_at) VALUES ('x', 'arbiter', '2026-10-08')") }
  end

  test "the rebuild accepts arbiter and keeps rows, ids, children and foreign keys" do
    migrate(:up)
    assert_includes role_sql, NEW_CHECK
    assert_equal [ [ 7, "reviewer", "omp", "m1" ], [ 9, "solver", "omp", "m2" ] ], @conn.select_rows("SELECT id, role, agent, model FROM agent_sessions ORDER BY id")
    assert_equal [ [ 7 ] ], @conn.select_rows("SELECT agent_session_id FROM item_reviews")
    assert_equal [ [ 9 ] ], @conn.select_rows("SELECT author_session_id FROM item_revisions")
    assert_empty @conn.select_rows("PRAGMA foreign_key_check")
    @conn.execute("INSERT INTO agent_sessions (label, role, created_at, agent, model) VALUES ('c', 'arbiter', '2026-10-08', 'omp', 'claude-opus-5-5')")
    assert_equal 10, @conn.select_value("SELECT max(id) FROM agent_sessions"), "ids continue after the highest"
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("INSERT INTO agent_sessions (label, role, created_at) VALUES ('x', 'nobody', '2026-10-08')") }
  end

  test "the children still enforce their foreign key to the rebuilt table" do
    migrate(:up)
    @conn.execute("PRAGMA foreign_keys = ON")
    assert_raises(ActiveRecord::InvalidForeignKey) do
      @conn.execute("INSERT INTO item_reviews (item_revision_id, agent_session_id, checklist_json, created_at) VALUES (1, 4242, '[]', '2026-10-08')")
    end
  end

  test "the append-only triggers are on the rebuilt table and work" do
    migrate(:up)
    names = @conn.select_values("SELECT name FROM sqlite_master WHERE type = 'trigger' AND tbl_name = 'agent_sessions' ORDER BY name")
    assert_equal %w[agent_sessions_no_delete agent_sessions_no_update], names
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("UPDATE agent_sessions SET label = 'z' WHERE id = 7") }
    assert_raises(ActiveRecord::StatementInvalid) { @conn.execute("DELETE FROM agent_sessions WHERE id = 9") }
  end

  test "every other table keeps its triggers and the rebuilt structure equals db/structure.sql" do
    before = @conn.select_values("SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name")
    migrate(:up)
    assert_equal before, @conn.select_values("SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name")
    sql = ->(c) { c.select_value("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'agent_sessions'").to_s.gsub(%r{\s*/\*application='Banco'\*/}, "").squish }
    live = ActiveRecord::Base.connection
    assert_equal sql.call(live), sql.call(@conn)
  end

  test "down is refused once an arbiter session exists, else it restores the old check" do
    migrate(:up)
    @conn.execute("INSERT INTO agent_sessions (label, role, created_at, agent, model) VALUES ('c', 'arbiter', '2026-10-08', 'omp', 'claude-opus-5-5')")
    assert_raises(ActiveRecord::IrreversibleMigration) { migrate(:down) }
  end

  test "down restores the old check when no arbiter exists" do
    migrate(:up)
    migrate(:down)
    assert_includes role_sql, OLD_CHECK
    assert_equal 2, @conn.select_value("SELECT count(*) FROM agent_sessions")
  end
end
