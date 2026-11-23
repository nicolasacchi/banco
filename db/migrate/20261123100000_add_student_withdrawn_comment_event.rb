# D-397: the student may delete his own comment while the teacher has not replied. The ledger stays append-only, so
# deleting is a new kind of comment event, `student_withdrawn` (origin `student`, no text): the comment's state is
# derived from it ("withdrawn", Comment#state) and his lists hide it, but the row and its history stay and the teacher
# and the API still see it, as «ritirato dallo studente». comment_events has CHECK constraints on the kind and on which
# kinds belong to the student, and SQLite cannot change a constraint in place, so the table is rebuilt as in
# AddStudentReplyCommentEvent: Rails copies the rows with their ids (the children keep their foreign keys, checked
# below) and the append-only triggers are installed again.
class AddStudentWithdrawnCommentEvent < ActiveRecord::Migration[8.1]
  KIND_OLD = "kind IN ('reply','read','resolved','reopened','sent_back','reply_seen','student_reply')".freeze
  KIND_NEW = "kind IN ('reply','read','resolved','reopened','sent_back','reply_seen','student_reply','student_withdrawn')".freeze
  STUDENT_OLD = "(kind IN ('reply_seen','student_reply')) = (origin = 'student')".freeze
  STUDENT_NEW = "(kind IN ('reply_seen','student_reply','student_withdrawn')) = (origin = 'student')".freeze

  def up
    swap(KIND_OLD, KIND_NEW, STUDENT_OLD, STUDENT_NEW)
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "withdrawn comments may exist and the ledger is append-only" if select_value("SELECT 1 FROM comment_events WHERE kind = 'student_withdrawn'")

    swap(KIND_NEW, KIND_OLD, STUDENT_NEW, STUDENT_OLD)
  end

  private

  def swap(kind_from, kind_to, student_from, student_to)
    remove_check_constraint :comment_events, kind_from, name: "comment_events_kind"
    remove_check_constraint :comment_events, student_from, name: "comment_events_seen_by_student"
    add_check_constraint :comment_events, kind_to, name: "comment_events_kind"
    add_check_constraint :comment_events, student_to, name: "comment_events_seen_by_student"
    Banco::AppendOnly.install(connection, :comment_events)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
