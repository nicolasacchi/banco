module Search
  # The schema of the search database, in code: the file is derived and disposable, so a version change drops
  # everything and the next rebuild fills it again (no migrations, no append-only triggers).
  #
  #   search_documents  one row per searchable unit (kind, key, revision, status, title, body, anchor, ...)
  #   search_fts        FTS5, unicode61 with remove_diacritics 2: title, body, stems (Snowball stems of both)
  #   search_trigram    FTS5 trigram, contentless: the typo fallback (folded title and body)
  #   search_meta       schema version, build times
  module Schema
    VERSION = 1

    TABLES = %w[search_documents search_fts search_trigram search_meta].freeze

    module_function

    def connection = Record.connection

    # Creates the tables when the file is new or from another version. Cheap when everything is in place.
    def ensure!
      return if connection.select_value("PRAGMA user_version").to_i == VERSION && present?

      reset!
    end

    # sqlite_master, not connection.table_exists?: Rails does not list virtual (FTS5) tables.
    def present?
      names = connection.select_values("SELECT name FROM sqlite_master WHERE type = 'table'")
      TABLES.all? { |t| names.include?(t) }
    end

    def reset!
      drop!
      create!
    end

    def drop!
      TABLES.each { |t| connection.execute("DROP TABLE IF EXISTS #{t}") }
    end

    def create!
      connection.execute(<<~SQL)
        CREATE TABLE search_documents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          doc_key TEXT NOT NULL UNIQUE,
          grp TEXT NOT NULL,
          kind TEXT NOT NULL,
          audience TEXT NOT NULL,
          subject TEXT,
          key TEXT,
          revision_table TEXT,
          revision_id INTEGER,
          status TEXT,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          anchor TEXT,
          lang TEXT,
          topic_key TEXT,
          skill TEXT,
          student_key TEXT,
          occurred_at TEXT,
          digest TEXT NOT NULL
        )
      SQL
      connection.execute("CREATE INDEX search_documents_grp ON search_documents (grp)")
      connection.execute("CREATE INDEX search_documents_key ON search_documents (key COLLATE NOCASE)")
      connection.execute("CREATE INDEX search_documents_kind ON search_documents (kind, subject)")
      connection.execute("CREATE INDEX search_documents_student ON search_documents (student_key)")
      connection.execute("CREATE VIRTUAL TABLE search_fts USING fts5(title, body, stems, tokenize = 'unicode61 remove_diacritics 2', prefix = '2 3')")
      connection.execute("CREATE VIRTUAL TABLE search_trigram USING fts5(text, tokenize = 'trigram', content = '', contentless_delete = 1)")
      connection.execute("CREATE TABLE search_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
      connection.execute("PRAGMA user_version = #{VERSION}")
    end
  end
end
