# frozen_string_literal: true

module Banco
  # Firm rule 4: the ledger is append-only. Every table of the primary database
  # except Rails' own bookkeeping rejects UPDATE and DELETE with a SQLite trigger
  # (RAISE(ABORT, 'append-only')). Rails cannot be trusted to enforce this, so the
  # database does; db/structure.sql carries the triggers.
  module AppendOnly
    EXEMPT_TABLES = %w[schema_migrations ar_internal_metadata sqlite_sequence].freeze
    MESSAGE = "append-only"

    def self.install(connection, table)
      %w[UPDATE DELETE].each do |verb|
        connection.execute(<<~SQL)
          CREATE TRIGGER #{trigger_name(table, verb)} BEFORE #{verb} ON #{table}
          BEGIN SELECT RAISE(ABORT, '#{MESSAGE}'); END
        SQL
      end
    end

    def self.trigger_name(table, verb)
      "#{table}_no_#{verb.downcase}"
    end

    # Tables of the connection that must carry the triggers.
    def self.guarded_tables(connection)
      connection.tables - EXEMPT_TABLES
    end
  end
end
