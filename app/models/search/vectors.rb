module Search
  # The vectors of the content documents (D-300): one per document, float32 blobs in `search_vectors`, with the model and the
  # dimension that made them. Never a student_answer and never a document of the teacher's audience: those kinds are not
  # eligible, so no student text goes to the embedding model.
  #
  #   Search::Vectors.build!(embedder)   # embeds what has no current vector (new, changed, or made by another model), newest first; in
  #                                      # SearchEmbedJob and the rebuild task (through Search::Indexer.embed!), never in a request
  #   Search::Vectors.status             # {eligible:, with_vectors:, missing:, model:}
  #
  # A document's vector is current when its digest equals the document's and its model and dimension are the embedder's. A document
  # that changed is re-inserted by Search::Index: its vector is kept when the text sent to the model is the same (a change of status,
  # D-315) and dropped otherwise, so the next build embeds it. A new document whose text is that of a document of the same object (an
  # unchanged instance or card of a new revision) gets that document's vector (donors, snapshot, give and redate, from Search::Index).
  #
  # Cosine without a numeric library: a vector of 1024 floats against 9,600 documents is 10 million multiplications, about a second
  # in Ruby. So every vector also has a coarse form (COARSE signed sums of the dimensions, a sparse random projection, normalized
  # like the original); the question is compared with the coarse forms of the documents the scope may see, the best CANDIDATES go
  # to the exact comparison. See Search::Semantic.
  module Vectors
    BATCH = 8
    COARSE = 128
    ELIGIBLE_KINDS = (Doc::KINDS - Doc::TEACHER_KINDS).freeze
    EMBED_CHARS = 2000

    module_function

    def connection = Record.connection

    def normalize(vector)
      norm = Math.sqrt(vector.sum { |x| x * x })
      norm.zero? ? vector : vector.map { |x| x / norm }
    end

    def pack(vector) = vector.pack("e*")

    def unpack(blob) = blob.unpack("e*")

    # The coarse form: COARSE sums of the dimensions with a fixed pseudo-random sign and bucket for each, normalized. The same
    # projection serves the questions and the documents (it depends only on the dimension).
    def coarse(vector)
      return vector if vector.size <= COARSE

      buckets, signs = projection(vector.size)
      out = Array.new(COARSE, 0.0)
      vector.each_with_index { |x, i| out[buckets[i]] += signs[i] * x }
      normalize(out)
    end

    def projection(dimension)
      (@projections ||= {})[dimension] ||= begin
        random = Random.new(0x62616e63)
        order = (0...dimension).to_a.shuffle(random: random)
        buckets = Array.new(dimension)
        order.each_with_index { |dim, position| buckets[dim] = position % COARSE }
        [ buckets, Array.new(dimension) { random.rand < 0.5 ? -1.0 : 1.0 } ].freeze
      end
    end

    def text_of(row) = "#{row[1]}\n#{row[2]}".first(EMBED_CHARS)

    # What a vector depends on besides the model: the text sent for the document. Two documents with the same text key share a vector.
    def text_key(title, body) = Digest::SHA256.hexdigest(text_of([ nil, title, body ]))

    def eligible_sql = "d.kind IN (#{ELIGIBLE_KINDS.map { |k| "'#{k}'" }.join(', ')}) AND d.audience <> 'teacher'"

    # [[id, title, body, digest]]: eligible documents with no current vector, the newest first (D-315: what an author has just submitted
    # does not wait behind older documents; a new revision's documents are new rows, so they have the highest ids).
    def pending(embedder, limit: nil)
      sql = +"SELECT d.id, d.title, d.body, d.digest FROM #{pending_from(embedder)} ORDER BY d.id DESC"
      sql << " LIMIT #{Integer(limit)}" if limit
      Index.rows(sql, *pending_binds(embedder))
    end

    # How many eligible documents wait for a vector of this embedder (what "Simili" says of an object that has none yet).
    def waiting(embedder) = embedder ? Index.rows("SELECT COUNT(*) FROM #{pending_from(embedder)}", *pending_binds(embedder)).dig(0, 0).to_i : 0

    def pending?(embedder) = embedder ? Index.rows("SELECT 1 FROM #{pending_from(embedder)} LIMIT 1", *pending_binds(embedder)).any? : false

    def pending_from(embedder)
      "search_documents d LEFT JOIN search_vectors v ON v.doc_id = d.id WHERE #{eligible_sql} " \
        "AND (v.doc_id IS NULL OR v.digest <> d.digest OR v.model <> ?#{' OR v.dim <> ?' if embedder.dimension})"
    end

    def pending_binds(embedder) = [ embedder.model, *([ embedder.dimension ] if embedder.dimension) ]

    # Seconds a lease lasts between two renewals (Search::Lease): one request at the embedder's timeout, the wait before a retry, a margin.
    def lease_ttl(embedder, retry_wait: 0)
      timeout = embedder.respond_to?(:document_timeout) ? embedder.document_timeout.to_f : 60.0
      (timeout + retry_wait.to_f + 60).ceil
    end

    # {text key => doc id}: the documents of +group+ with one of +keys+ whose vector is current, read by Search::Index before it rewrites
    # the group (the donors). Only the documents of the same objects (an item's other revision, a lesson whose status changed); all of the
    # group when there are many keys (a builder that changed every row).
    def donors(group, keys)
      keys = keys.compact.uniq
      return {} if keys.empty?

      sql = +"SELECT d.id, d.title, d.body FROM search_documents d JOIN search_vectors v ON v.doc_id = d.id AND v.digest = d.digest WHERE d.grp = ? AND #{eligible_sql}"
      binds = [ group ]
      if keys.size <= 500
        sql << " AND d.key IN (#{keys.map { '?' }.join(', ')})"
        binds.concat(keys)
      end
      Index.rows(sql, *binds).each_with_object({}) { |(id, title, body), out| out[text_key(title, body)] ||= id }
    end

    # {doc id => [model, dim, vec, coarse]}: the vectors of these documents, read into memory before Search::Index rewrites a group.
    def snapshot(ids)
      ids = ids.compact.uniq
      return {} if ids.empty?

      Index.rows("SELECT doc_id, model, dim, vec, coarse FROM search_vectors WHERE doc_id IN (#{ids.map { |i| Integer(i) }.join(', ')})")
           .to_h { |doc_id, *vector| [ doc_id, vector ] }
    end

    # Gives document +id+ (just written with +digest+) a vector read by snapshot. True when it did (nil: the donor had none).
    def give(id, digest, vector)
      return false unless vector

      model, dim, vec, coarse = vector
      Index.write("INSERT INTO search_vectors (doc_id, digest, model, dim, vec, coarse) VALUES (?, ?, ?, ?, ?, ?) " \
                  "ON CONFLICT(doc_id) DO UPDATE SET digest = excluded.digest, model = excluded.model, dim = excluded.dim, vec = excluded.vec, coarse = excluded.coarse",
                  id, digest, model, dim, blob(vec), blob(coarse))
      true
    end

    # The vector a rewritten row kept (same text) now belongs to its new digest. True when there was one.
    def redate(id, digest)
      Index.write("UPDATE search_vectors SET digest = ? WHERE doc_id = ?", digest, id)
      connection.select_value("SELECT changes()").to_i.positive?
    end

    # Embeds what is pending, newest first, BATCH documents a request, until none is left (or the +limit+ documents taken are done), the
    # +deadline+ (seconds) passes, the service fails or the +lease+ (Search::Lease, renewed before each request) is lost. Never raises for
    # a service that is down: the lexical index is whole without vectors. Returns {embedded:, pending:, down:, seconds:, lost:, ...};
    # pending counts what was taken and not embedded.
    def build!(embedder = Embedder.current, deadline: nil, limit: nil, lease: nil, retries: 0, retry_wait: 0, sleeper: Kernel.method(:sleep), every: nil,
               progress: nil)
      Schema.ensure!
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return { embedded: 0, pending: 0, down: false, seconds: 0.0, configured: false, skipped: 0 } unless embedder

      forget_stale(embedder)
      embedded = 0
      skipped = 0
      skipped_docs = 0
      down = false
      lost = false
      ttl = lease_ttl(embedder, retry_wait: retry_wait)
      todo = pending(embedder, limit: limit)
      todo.each_slice(BATCH).with_index(1) do |batch, number|
        break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > deadline

        attempts = 0
        begin
          if lease && !lease.renew(ttl)
            lost = true
            break
          end
          vectors = embedder.embed_documents(batch.map { |row| text_of(row) })
          store(batch, vectors, embedder)
          embedded += batch.size
        rescue Embedder::Unavailable => e
          Rails.logger.warn("search: the embedding service failed while indexing (#{e.message.first(120)}); #{todo.size - embedded} documents left for the next run")
          if retries.zero?
            down = true
            break
          end
          # The service may still be computing the abandoned batch: wait for it to drain, then ask again; a batch that stays
          # unanswered is skipped (the next run picks it up) and the rebuild goes on.
          if attempts < retries
            attempts += 1
            sleeper.call(retry_wait)
            retry
          end
          skipped += 1
          skipped_docs += batch.size
        end
        progress&.call(embedded: embedded, total: todo.size, skipped: skipped, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) if every && (number % every).zero?
      end
      { embedded: embedded, pending: todo.size - embedded, down: down, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, configured: true,
        skipped: skipped, skipped_documents: skipped_docs, lost: lost }
    end

    def store(batch, vectors, embedder)
      connection.transaction do
        batch.zip(vectors).each do |(id, _title, _body, digest), vector|
          Index.write("INSERT INTO search_vectors (doc_id, digest, model, dim, vec, coarse) VALUES (?, ?, ?, ?, ?, ?) " \
                      "ON CONFLICT(doc_id) DO UPDATE SET digest = excluded.digest, model = excluded.model, dim = excluded.dim, vec = excluded.vec, coarse = excluded.coarse",
                      id, digest, embedder.model, vector.size, blob(pack(vector)), blob(pack(coarse(vector))))
        end
      end
    end

    # Vectors of another model or dimension are dropped when the embedder is known (the stale ones are re-embedded as pending).
    def forget_stale(embedder)
      Index.write("DELETE FROM search_vectors WHERE model <> ?", embedder.model)
      Index.write("DELETE FROM search_vectors WHERE dim <> ?", embedder.dimension) if embedder.dimension
    end

    # Whether some eligible document has a vector of this embedder's model (before the first build, the search stays lexical).
    def any?(embedder) = Index.rows("SELECT 1 FROM search_vectors WHERE model = ? LIMIT 1", embedder.model).any?

    # What `bin/rails banco:search:status` says.
    def status(embedder = Embedder.current)
      Schema.ensure!
      eligible = Index.rows("SELECT COUNT(*) FROM search_documents d WHERE #{eligible_sql}").dig(0, 0).to_i
      held = Index.rows("SELECT COUNT(*), MIN(model), MAX(model), MIN(dim), MAX(dim) FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id " \
                        "WHERE #{eligible_sql} AND v.digest = d.digest").first
      current = embedder ? Index.rows("SELECT COUNT(*) FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id WHERE #{eligible_sql} AND v.digest = d.digest AND v.model = ?", embedder.model).dig(0, 0).to_i : 0
      { eligible: eligible, with_vectors: held[0].to_i, current: current, missing: eligible - current, models: [ held[1], held[2] ].compact.uniq,
        dimension: held[3] == held[4] ? held[3] : nil, embedder: embedder&.model }
    end

    # A binary value for a statement with ? placeholders: Rails quotes it as a hex literal, so no byte is altered.
    def blob(string) = ActiveRecord::Type::Binary::Data.new(string)
  end
end
