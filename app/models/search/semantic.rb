module Search
  # The cosine list of the staff's and the agents' search (D-300): the documents of the scope nearest to a vector, brute force.
  #
  # Two passes over the documents the scope may see (the scope's SQL clause picks them, as for the lexical list): the coarse
  # forms (128 floats) of all of them against the question's, then the exact vectors of the best CANDIDATES. The first pass costs
  # 9,600 x 128 multiplications instead of 9,600 x 1,024; the second is exact for the ones that matter. The vectors are
  # normalized, so a cosine is a dot product.
  #
  # Never called for the student's door: Search::Engine reaches it only when the scope says `semantic?`.
  module Semantic
    CANDIDATES = 200

    module_function

    # [Hit] by cosine (the score), best first, each at least +min+. +exclude+: a document id, or ids, left out (the object of a "Simili").
    def nearest(engine, vector, model:, filters:, limit:, min:, exclude: nil)
      nearest_any(engine, { nil => vector }, model: model, filters: filters, limit: limit, min: min, exclude: exclude)
    end

    # The same for several vectors at once (the cards of a lesson, D-315): +queries+ is {label => vector}; a document's score is its
    # cosine with the nearest of them, and its hit's `near` the label of that one. One pass over the documents whatever their number.
    def nearest_any(engine, queries, model:, filters:, limit:, min:, exclude: nil)
      vectors = queries.values
      where, binds = engine.where(filters)
      where = "#{where} AND #{Vectors.eligible_sql}"
      ids = Array(exclude).compact
      where += " AND d.id NOT IN (#{ids.map { |i| Integer(i) }.join(', ')})" if ids.any?
      rows = engine.select("SELECT v.doc_id, v.coarse FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id WHERE v.model = ? AND v.dim = ? AND #{where}",
                           [ model, vectors.first.size, *binds ])
      return [] if rows.empty?

      ids = candidates(rows, vectors)
      exact = engine.select("SELECT #{Engine::COLUMNS}, v.vec AS vec FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id WHERE d.id IN (#{ids.map { |i| Integer(i) }.join(', ')})", [])
      scored = exact.map do |row|
        vec = Vectors.unpack(row["vec"])
        score, label = queries.map { |name, query| [ dot(query, vec), name ] }.max_by(&:first)
        [ score, label, row ]
      end
      scored.select { |score, _, _| score >= min }.sort_by { |score, _, row| [ -score, row["id"] ] }.first(limit).map do |score, label, row|
        engine.hit(row.except("vec").merge("score" => score, "near" => label), :semantic)
      end
    end

    # The ids of the rows whose coarse form is nearest to one of the questions'.
    def candidates(rows, vectors)
      vectors = [ vectors ] unless vectors.first.is_a?(Array)
      return rows.map { |r| r["doc_id"] } if vectors.first.size <= Vectors::COARSE || rows.size <= CANDIDATES

      queries = vectors.map { |v| Vectors.coarse(v) }
      rows.max_by(CANDIDATES) do |row|
        coarse = Vectors.unpack(row["coarse"])
        queries.map { |q| dot(q, coarse) }.max
      end.map { |r| r["doc_id"] }
    end

    def dot(a, b)
      sum = 0.0
      i = 0
      n = a.size
      while i < n
        sum += a[i] * b[i]
        i += 1
      end
      sum
    end
  end
end
