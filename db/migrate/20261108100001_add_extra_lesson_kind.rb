# D-324: topics outside the programme («Fuori programma»), keys extra.<subject>.<slug>. lessons.kind has a CHECK
# constraint, and SQLite cannot change a constraint in place, so the table is rebuilt as in AddArbiterRole: Rails
# copies the rows with their ids (the children keep their foreign keys, checked below) and the append-only
# triggers are installed again on the new table.
class AddExtraLessonKind < ActiveRecord::Migration[8.1]
  OLD = "kind IN ('ripasso','ponte','lezione')".freeze
  NEW = "kind IN ('ripasso','ponte','lezione','extra')".freeze

  def up
    rebuild(OLD, NEW)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "extra lessons may exist and the ledger is append-only" if select_value("SELECT 1 FROM lessons WHERE kind = 'extra'")

    rebuild(NEW, OLD)
  end

  private

  def rebuild(from, to)
    remove_check_constraint :lessons, from, name: "lessons_kind"
    add_check_constraint :lessons, to, name: "lessons_kind"
    Banco::AppendOnly.install(connection, :lessons)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
