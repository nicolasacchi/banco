# D-357: a comment can be written on the privacy page and the account page (the privacy notice itself says «scrivi un commento da
# qualsiasi pagina»). Two new page kinds, `privacy` and `account`. comments has a CHECK on page_kind and SQLite cannot change a
# constraint in place, so the table is rebuilt as in AddStudentReplyCommentEvent: Rails copies the rows with their ids (the
# children keep their foreign keys, checked below) and the append-only triggers are installed again.
class AddPrivacyAccountCommentPages < ActiveRecord::Migration[8.1]
  OLD = "page_kind IN ('today','subjects','subject','topic','lesson','practice','diagnosis','warmup','sitting','results','settings','search','comments')".freeze
  NEW = "page_kind IN ('today','subjects','subject','topic','lesson','practice','diagnosis','warmup','sitting','results','settings','search','comments','privacy','account')".freeze

  def up
    remove_check_constraint :comments, OLD, name: "comments_page_kind"
    add_check_constraint :comments, NEW, name: "comments_page_kind"
    finish
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "comments on these pages may exist and the ledger is append-only" if select_value("SELECT 1 FROM comments WHERE page_kind IN ('privacy','account')")

    remove_check_constraint :comments, NEW, name: "comments_page_kind"
    add_check_constraint :comments, OLD, name: "comments_page_kind"
    finish
  end

  private

  def finish
    Banco::AppendOnly.install(connection, :comments)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
