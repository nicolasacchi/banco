module Search
  # The vectors of the content documents (D-300): one per document, float32 blobs in `search_vectors`, with the model and the
  # dimension that made them. Never a student_answer and never a document of the teacher's audience: those kinds are not
  # eligible, so no student text goes to the embedding model.
  #
  #   Search::Vectors.build!(embedder)   # embeds what has no current vector (new, changed, or made by another model); in the index
  #                                      # job and the rebuild task, never in a request
  #   Search::Vectors.status             # {eligible:, with_vectors:, missing:, model:}
  #
  # A document's vector is current when its digest equals the document's and its model and dimension are the embedder's. A document
  # that changed is re-inserted by Search::Index (which drops its vector), so the next build embeds it.
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

    def eligible_sql = "d.kind IN (#{ELIGIBLE_KINDS.map { |k| "'#{k}'" }.join(', ')}) AND d.audience <> 'teacher'"

    # [[id, title, body, digest]]: eligible documents with no current vector.
    def pending(embedder, limit: nil)
      sql = +"SELECT d.id, d.title, d.body, d.digest FROM search_documents d LEFT JOIN search_vectors v ON v.doc_id = d.id " \
             "WHERE #{eligible_sql} AND (v.doc_id IS NULL OR v.digest <> d.digest OR v.model <> ?#{' OR v.dim <> ?' if embedder.dimension}) ORDER BY d.id"
      binds = [ embedder.model ]
      binds << embedder.dimension if embedder.dimension
      sql << " LIMIT #{Integer(limit)}" if limit
      Index.rows(sql, *binds)
    end

    # Embeds what is pending, BATCH documents a request, until none is left, the +deadline+ (seconds) passes or the service fails.
    # Never raises for a service that is down: the lexical index is whole without vectors. Returns
    # {embedded:, pending:, down:, seconds:}.
    def build!(embedder = Embedder.current, deadline: nil)
      Schema.ensure!
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return { embedded: 0, pending: 0, down: false, seconds: 0.0, configured: false } unless embedder

      forget_stale(embedder)
      embedded = 0
      down = false
      todo = pending(embedder)
      todo.each_slice(BATCH) do |batch|
        break if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > deadline

        vectors = embedder.embed_documents(batch.map { |row| text_of(row) })
        store(batch, vectors, embedder)
        embedded += batch.size
      rescue Embedder::Unavailable => e
        Rails.logger.warn("search: the embedding service failed while indexing (#{e.message.first(120)}); #{todo.size - embedded} documents left for the next run")
        down = true
        break
      end
      { embedded: embedded, pending: todo.size - embedded, down: down, seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, configured: true }
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
