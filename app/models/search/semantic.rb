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

    # [Hit] by cosine (the score), best first, each at least +min+. +exclude+: a document id left out (the object of a "Simili").
    def nearest(engine, vector, model:, filters:, limit:, min:, exclude: nil)
      where, binds = engine.where(filters)
      where = "#{where} AND #{Vectors.eligible_sql}"
      if exclude
        where += " AND d.id <> ?"
        binds += [ exclude ]
      end
      rows = engine.select("SELECT v.doc_id, v.coarse FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id WHERE v.model = ? AND v.dim = ? AND #{where}",
                           [ model, vector.size, *binds ])
      return [] if rows.empty?

      ids = candidates(rows, vector)
      exact = engine.select("SELECT #{Engine::COLUMNS}, v.vec AS vec FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id WHERE d.id IN (#{ids.map { |i| Integer(i) }.join(', ')})", [])
      scored = exact.map { |row| [ dot(vector, Vectors.unpack(row["vec"])), row ] }.select { |score, _| score >= min }
      scored.sort_by { |score, row| [ -score, row["id"] ] }.first(limit).map do |score, row|
        engine.hit(row.except("vec").merge("score" => score), :semantic)
      end
    end

    # The ids of the rows whose coarse form is nearest to the question's.
    def candidates(rows, vector)
      return rows.map { |r| r["doc_id"] } if vector.size <= Vectors::COARSE || rows.size <= CANDIDATES

      query = Vectors.coarse(vector)
      rows.max_by(CANDIDATES) { |row| dot(query, Vectors.unpack(row["coarse"])) }.map { |r| r["doc_id"] }
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
