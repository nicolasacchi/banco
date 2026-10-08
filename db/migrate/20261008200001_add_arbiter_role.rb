# D-222: a third reviewer, the arbiter, judges the findings (who is right: the author or the
# finding). agent_sessions.role has a CHECK constraint, and SQLite cannot change a constraint in
# place, so the table is rebuilt. Rails copies the rows with their ids (the children keep their
# foreign keys, checked below) and the append-only triggers are installed again on the new table.
class AddArbiterRole < ActiveRecord::Migration[8.1]
  OLD = "role IN ('author','verifier','reviewer','solver','grader','operator')".freeze
  NEW = "role IN ('author','verifier','reviewer','solver','grader','operator','arbiter')".freeze

  def up
    rebuild(OLD, NEW)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "sessions with the arbiter role may exist and the ledger is append-only" if select_value("SELECT 1 FROM agent_sessions WHERE role = 'arbiter'")

    rebuild(NEW, OLD)
  end

  private

  def rebuild(from, to)
    remove_check_constraint :agent_sessions, from, name: "agent_sessions_role"
    add_check_constraint :agent_sessions, to, name: "agent_sessions_role"
    Banco::AppendOnly.install(connection, :agent_sessions)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
