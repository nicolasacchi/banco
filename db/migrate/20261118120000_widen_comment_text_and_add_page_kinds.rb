# D-361: a comment and the student's follow-up may be up to 2000 characters (was 500), and a comment can be written on two more
# pages, `civics` (Educazione civica) and `not_found` (the student's own 404). comments has CHECKs on text_it and page_kind,
# comment_events one on the text of a student_reply, and SQLite cannot change a constraint in place, so both tables are rebuilt
# as in AddPrivacyAccountCommentPages and AddStudentReplyCommentEvent: Rails copies the rows with their ids (the children
# keep their foreign keys, checked below) and the append-only triggers are installed again.
class WidenCommentTextAndAddPageKinds < ActiveRecord::Migration[8.1]
  KINDS = "'today','subjects','subject','topic','lesson','practice','diagnosis','warmup','sitting','results','settings','search','comments','privacy','account'".freeze
  KIND_OLD = "page_kind IN (#{KINDS})".freeze
  KIND_NEW = "page_kind IN (#{KINDS},'civics','not_found')".freeze
  TEXT_OLD = "text_it IS NULL OR length(text_it) BETWEEN 1 AND 500".freeze
  TEXT_NEW = "text_it IS NULL OR length(text_it) BETWEEN 1 AND 2000".freeze
  REPLY_OLD = "kind <> 'student_reply' OR (text_it IS NOT NULL AND length(text_it) BETWEEN 1 AND 500)".freeze
  REPLY_NEW = "kind <> 'student_reply' OR (text_it IS NOT NULL AND length(text_it) BETWEEN 1 AND 2000)".freeze

  def up
    swap(:comments, "comments_page_kind", KIND_OLD, KIND_NEW)
    swap(:comments, "comments_text_length", TEXT_OLD, TEXT_NEW)
    swap(:comment_events, "comment_events_student_reply_text", REPLY_OLD, REPLY_NEW)
    finish
  end

  def down
    if select_value("SELECT 1 FROM comments WHERE page_kind IN ('civics','not_found') OR length(text_it) > 500 LIMIT 1") ||
       select_value("SELECT 1 FROM comment_events WHERE kind = 'student_reply' AND length(text_it) > 500 LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "comments on the new pages or longer than 500 characters may exist and the ledger is append-only"
    end

    swap(:comment_events, "comment_events_student_reply_text", REPLY_NEW, REPLY_OLD)
    swap(:comments, "comments_text_length", TEXT_NEW, TEXT_OLD)
    swap(:comments, "comments_page_kind", KIND_NEW, KIND_OLD)
    finish
  end

  private

  def swap(table, name, old, new)
    remove_check_constraint table, old, name: name
    add_check_constraint table, new, name: name
  end

  def finish
    Banco::AppendOnly.install(connection, :comments)
    Banco::AppendOnly.install(connection, :comment_events)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
