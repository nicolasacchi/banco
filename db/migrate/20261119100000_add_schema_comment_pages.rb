# D-372: a comment can be written on two more student pages, `schema` (the schema of a topic, /topics/:topic/schema) and `schemas`
# («I miei schemi», /schemas). comments has a CHECK on page_kind and SQLite cannot change a constraint in place, so the table is rebuilt
# as in WidenCommentTextAndAddPageKinds: Rails copies the rows with their ids (comment_events keeps its foreign key, checked below) and
# the append-only triggers are installed again. No existing kind fits: `lesson` and `topic` name other pages, and a comment is filed under
# the kind of the page it was written on (Comments::Pages).
class AddSchemaCommentPages < ActiveRecord::Migration[8.1]
  KINDS = "'today','subjects','subject','topic','lesson','practice','diagnosis','warmup','sitting','results','settings','search','comments','privacy','account','civics','not_found'".freeze
  KIND_OLD = "page_kind IN (#{KINDS})".freeze
  KIND_NEW = "page_kind IN (#{KINDS},'schema','schemas')".freeze

  def up
    swap(KIND_OLD, KIND_NEW)
    finish
  end

  def down
    if select_value("SELECT 1 FROM comments WHERE page_kind IN ('schema','schemas') LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "comments on the schema pages may exist and the ledger is append-only"
    end

    swap(KIND_NEW, KIND_OLD)
    finish
  end

  private

  def swap(old, new)
    remove_check_constraint :comments, old, name: "comments_page_kind"
    add_check_constraint :comments, new, name: "comments_page_kind"
  end

  def finish
    Banco::AppendOnly.install(connection, :comments)
    broken = select_rows("PRAGMA foreign_key_check")
    raise "foreign keys broken after the rebuild: #{broken.first(3).inspect}" if broken.any?
  end
end
