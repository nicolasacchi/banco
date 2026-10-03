require "test_helper"
require_relative "../support/ledger_rows"

# Firm rule 4: every table except Rails' bookkeeping rejects UPDATE and DELETE in
# the database itself.
class AppendOnlyTest < ActiveSupport::TestCase
  include LedgerRows

  CONNECTION = -> { ActiveRecord::Base.connection }

  def guarded_tables = Banco::AppendOnly.guarded_tables(CONNECTION.call)

  test "every table has an UPDATE and a DELETE trigger raising append-only" do
    triggers = CONNECTION.call.select_rows("SELECT tbl_name, sql FROM sqlite_master WHERE type = 'trigger'")
    guarded_tables.each do |table|
      %w[UPDATE DELETE].each do |verb|
        sql = triggers.find { |tbl, body| tbl == table && body.include?("BEFORE #{verb} ON #{table}") }&.last
        assert sql, "#{table} has no BEFORE #{verb} trigger"
        assert_includes sql, "RAISE(ABORT, 'append-only')", "#{table} #{verb} trigger does not abort"
      end
    end
  end

  test "the exemptions are exactly Rails' bookkeeping tables" do
    all = CONNECTION.call.select_values("SELECT name FROM sqlite_master WHERE type = 'table'")
    assert_equal %w[ar_internal_metadata schema_migrations sqlite_sequence], (all - guarded_tables).sort
  end

  test "the test builds a row for every guarded table" do
    assert_equal guarded_tables.sort, build_ledger_rows.keys.sort
  end

  test "update, update_column, update_all, delete, destroy and delete_all are refused on every table" do
    build_ledger_rows.each do |table, record|
      model = record.class
      assert_equal table, model.table_name
      id_column = model.primary_key
      {
        "update" => -> { record.update!(created_at: Time.current) },
        "update_column" => -> { record.update_column(:created_at, 1.day.ago) },
        "update_all" => -> { model.update_all(created_at: 1.day.ago) },
        "delete" => -> { record.delete },
        "destroy" => -> { record.destroy },
        "delete_all" => -> { model.delete_all }
      }.each do |name, action|
        error = assert_raises(ActiveRecord::StatementInvalid, "#{table}: #{name} was not refused") { action.call }
        assert_match(/append-only/, error.message, "#{table}: #{name}")
      end
      assert model.exists?(id_column => record.public_send(id_column)), "#{table}: the row must survive"
    end
  end

  test "raw SQL cannot change a row either" do
    build_ledger_rows
    error = assert_raises(ActiveRecord::StatementInvalid) { CONNECTION.call.execute("UPDATE subjects SET name_it = 'x'") }
    assert_match(/append-only/, error.message)
    error = assert_raises(ActiveRecord::StatementInvalid) { CONNECTION.call.execute("DELETE FROM attempts") }
    assert_match(/append-only/, error.message)
  end

  test "db/structure.sql carries the triggers" do
    sql = Rails.root.join("db/structure.sql").read
    assert_operator sql.size, :>, 0
    assert_equal guarded_tables.size * 2, sql.scan("CREATE TRIGGER").size
  end
end
