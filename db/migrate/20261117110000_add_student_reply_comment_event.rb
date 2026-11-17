# D-342: the student answers the teacher's reply. A new kind of comment event, `student_reply`: origin `student`, the
# student's own words (1..500 characters, like the comment's). comment_events has CHECK constraints, and SQLite cannot
# change a constraint in place, so the table is rebuilt as in AddExtraLessonKind: Rails copies the rows with their ids
# (the children keep their foreign keys, checked below) and the append-only triggers are installed again.
class AddStudentReplyCommentEvent < ActiveRecord::Migration[8.1]
  KIND_OLD = "kind IN ('reply','read','resolved','reopened','sent_back','reply_seen')".freeze
  KIND_NEW = "kind IN ('reply','read','resolved','reopened','sent_back','reply_seen','student_reply')".freeze
  STUDENT_OLD = "(kind = 'reply_seen') = (origin = 'student')".freeze
  STUDENT_NEW = "(kind IN ('reply_seen','student_reply')) = (origin = 'student')".freeze
  TEXT = "kind <> 'student_reply' OR (text_it IS NOT NULL AND length(text_it) BETWEEN 1 AND 500)".freeze

  def up
    remove_check_constraint :comment_events, KIND_OLD, name: "comment_events_kind"
    remove_check_constraint :comment_events, STUDENT_OLD, name: "comment_events_seen_by_student"
    add_check_constraint :comment_events, KIND_NEW, name: "comment_events_kind"
    add_check_constraint :comment_events, STUDENT_NEW, name: "comment_events_seen_by_student"
    add_check_constraint :comment_events, TEXT, name: "comment_events_student_reply_text"
    finish
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "student replies may exist and the ledger is append-only" if select_value("SELECT 1 FROM comment_events WHERE kind = 'student_reply'")

    remove_check_constraint :comment_events, TEXT, name: "comment_events_student_reply_text"
    remove_check_constraint :comment_events, STUDENT_NEW, name: "comment_events_seen_by_student"
    remove_check_constraint :comment_events, KIND_NEW, name: "comment_events_kind"
    add_check_constraint :comment_events, STUDENT_OLD, name: "comment_events_seen_by_student"
    add_check_constraint :comment_events, KIND_OLD, name: "comment_events_kind"
    finish
  end

  private

  def finish
    Banco::AppendOnly.install(connection, :comment_events)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
