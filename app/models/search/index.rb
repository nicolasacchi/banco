module Search
  # The writer of the search database. A group of documents (lessons, items, answers, ...) is replaced as a whole inside
  # one transaction, but only the rows that changed are written: the rows of an unchanged unit keep their ids, and two
  # builds from the same primary database leave the same rows.
  module Index
    COLUMNS = %w[doc_key grp kind audience subject key revision_table revision_id status title body anchor lang topic_key skill student_key occurred_at digest].freeze
    INSERT_DOCUMENT = "INSERT INTO search_documents (id, #{COLUMNS.join(', ')}) VALUES (#{([ '?' ] * (COLUMNS.size + 1)).join(', ')})".freeze
    TRIGRAM_MAX = 30_000

    module_function

    def connection = Record.connection

    # Runs a statement with ? placeholders (the values are quoted by Rails, never interpolated).
    def write(sql, *binds) = connection.execute(Record.sanitize_sql_array([ sql, *binds ]))

    def rows(sql, *binds) = connection.select_rows(Record.sanitize_sql_array([ sql, *binds ]))

    # docs: [Search::Doc]. Returns {added:, changed:, removed:, kept:}.
    def replace_group(group, docs)
      Schema.ensure!
      docs = docs.uniq(&:doc_key)
      counts = { added: 0, changed: 0, removed: 0, kept: 0 }
      connection.transaction do
        existing = rows("SELECT doc_key, id, digest FROM search_documents WHERE grp = ?", group).to_h { |k, id, d| [ k, [ id, d ] ] }
        docs.each do |doc|
          id, digest = existing.delete(doc.doc_key)
          if id.nil?
            insert(group, doc)
            counts[:added] += 1
          elsif digest != doc.digest
            remove_row(id)
            insert(group, doc, id: id)
            counts[:changed] += 1
          else
            counts[:kept] += 1
          end
        end
        existing.each_value do |id, _|
          remove_row(id)
          counts[:removed] += 1
        end
        set_meta("built_#{group}", Time.current.utc.iso8601)
      end
      counts
    end

    def insert(group, doc, id: nil)
      values = [ doc.doc_key, group, doc.kind, doc.audience, doc.subject, doc.key, doc.revision_table, doc.revision_id, doc.status, doc.title,
                 doc.body, doc.anchor, doc.lang, doc.topic_key, doc.skill, doc.student_key, doc.occurred_at, doc.digest ]
      write(INSERT_DOCUMENT, id, *values)
      id ||= connection.select_value("SELECT last_insert_rowid()").to_i
      text = "#{doc.title}\n#{doc.body}"
      write("INSERT INTO search_fts (rowid, title, body, stems) VALUES (?, ?, ?, ?)", id, doc.title, doc.body, Text.stem_column(text, doc.stem_langs))
      write("INSERT INTO search_trigram (rowid, text) VALUES (?, ?)", id, Text.fold(text).squish.first(TRIGRAM_MAX))
    end

    def remove_row(id)
      write("DELETE FROM search_fts WHERE rowid = ?", id)
      write("DELETE FROM search_trigram WHERE rowid = ?", id)
      write("DELETE FROM search_documents WHERE id = ?", id)
    end

    # Drops every row (the next build fills the index again).
    def clear!
      Schema.ensure!
      connection.transaction do
        connection.execute("DELETE FROM search_fts")
        connection.execute("DELETE FROM search_trigram")
        connection.execute("DELETE FROM search_documents")
        connection.execute("DELETE FROM search_meta")
      end
    end

    def set_meta(key, value)
      write("INSERT INTO search_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", key, value)
    end

    def meta(key) = rows("SELECT value FROM search_meta WHERE key = ?", key).dig(0, 0)

    def count = Document.count

    # True once some group has been built: before the first build the doors say the index is empty.
    def built? = Document.exists?
  end
end
