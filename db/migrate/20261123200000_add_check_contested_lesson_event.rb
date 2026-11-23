# D-396: «Per me va bene così» in a lesson/2. A new kind of lesson event, `check_contested`: the student sent his latest wrong answer of an inline check
# or of an exercise of «Prova tu» to the teacher (the comment is written beside it, by Comments::Intake). lesson_events has CHECK constraints, and
# SQLite cannot change a constraint in place, so the table is rebuilt as in AddExtraLessonKind: Rails copies the rows with their ids and the
# append-only triggers are installed again. The new kind names its card and its block, like a check answer.
class AddCheckContestedLessonEvent < ActiveRecord::Migration[8.1]
  KIND_OLD = "kind IN ('card_seen','check_answered','more_opened','steps_shown','lesson_printed','page_opened','page_event','page_failed')".freeze
  KIND_NEW = "kind IN ('card_seen','check_answered','more_opened','steps_shown','lesson_printed','page_opened','page_event','page_failed','check_contested')".freeze
  CARD_OLD = "kind NOT IN ('card_seen','check_answered') OR card IS NOT NULL".freeze
  CARD_NEW = "kind NOT IN ('card_seen','check_answered','check_contested') OR card IS NOT NULL".freeze
  CONTEST = "kind <> 'check_contested' OR block IS NOT NULL".freeze

  def up
    remove_check_constraint :lesson_events, KIND_OLD, name: "lesson_events_kind"
    remove_check_constraint :lesson_events, CARD_OLD, name: "lesson_events_card"
    add_check_constraint :lesson_events, KIND_NEW, name: "lesson_events_kind"
    add_check_constraint :lesson_events, CARD_NEW, name: "lesson_events_card"
    add_check_constraint :lesson_events, CONTEST, name: "lesson_events_contest"
    finish
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "contested checks may exist and the ledger is append-only" if select_value("SELECT 1 FROM lesson_events WHERE kind = 'check_contested' LIMIT 1")

    remove_check_constraint :lesson_events, CONTEST, name: "lesson_events_contest"
    remove_check_constraint :lesson_events, CARD_NEW, name: "lesson_events_card"
    remove_check_constraint :lesson_events, KIND_NEW, name: "lesson_events_kind"
    add_check_constraint :lesson_events, KIND_OLD, name: "lesson_events_kind"
    add_check_constraint :lesson_events, CARD_OLD, name: "lesson_events_card"
    finish
  end

  private

  def finish
    Banco::AppendOnly.install(connection, :lesson_events)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
