module Search
  # The lexical engine (S1). One question, one scope:
  #
  #   result = Search::Engine.new(scope: Search::Scope::Staff.new).call("equazioni", subject: "math", kind: %w[lesson_card], limit: 20)
  #   result.hits      # => [Search::Hit]
  #   result.semantic  # => false (S2 ranks with vectors for the staff's doors and the agents' only; the student's door never does)
  #
  # Steps: an exact key first; then the words of the question, all of them (FTS5 over title, body and Snowball stems, the last
  # word as a prefix); when that finds few, any of them; when that still finds few, the words corrected by edit distance against
  # the words of the documents the scope may see (found through the trigram table). Hits are ordered by Search::Ranker.
  class Engine
    MIN_HITS = 3
    TITLE_WEIGHT = 12.0
    BODY_WEIGHT = 2.0
    STEMS_WEIGHT = 0.7
    MAX_VARIANTS = 6
    SEMANTIC_LIMIT = 50
    KEY_ORDER = "CASE d.kind WHEN 'topic' THEN 0 WHEN 'item' THEN 1 WHEN 'skill' THEN 2 WHEN 'course' THEN 3 WHEN 'reference_article' THEN 4 ELSE 5 END"
    # bm25 saturates: a word repeated in a long body can tie with the same word in a short title. A title that holds the words
    # gets this much more, in proportion to the share of the words it holds.
    TITLE_BONUS = 3.0
    COLUMNS = "d.id, d.kind, d.subject, d.key, d.revision_table, d.revision_id, d.status, d.title, d.body, d.anchor, d.lang, d.topic_key, d.skill, d.student_key, d.occurred_at"

    class BadKind < StandardError; end
    # A "Simili" asked of a scope or a setup with no vectors (the student's door, no embedding service).
    class SemanticOff < StandardError; end

    Hit = Data.define(:id, :kind, :subject, :key, :revision_table, :revision_id, :status, :title, :body, :anchor, :lang, :topic_key, :skill,
                      :student_key, :occurred_at, :score, :match) do
      # [[text, matched]]: the passage of the body around the first matched word.
      def segments(terms, variants = []) = Text.snippet(body.presence || title, terms, variants: variants)

      def snippet(terms, variants = []) = segments(terms, variants).map(&:first).join
    end
    # corrections: {term => [corrected words]} (what the typo fallback tried); source: the document a "Simili" asked about, else nil.
    Result = Data.define(:query, :terms, :variants, :hits, :semantic, :indexed, :corrections, :source) do
      # True when the hits come from the typo fallback alone: the page then says what it understood instead.
      def only_corrected? = hits.any? && hits.all? { |h| h.match == :typo }

      # [[word, corrected query]] for each corrected word of a term that no hit holds as typed, at most +per+ words a term.
      def suggestions(per: 3)
        corrections.flat_map do |term, words|
          words.first(per).map { |word| [ term, word, Engine.replace_term(query, term, word) ] }
        end
      end
    end

    def self.replace_term(query, term, word)
      query.gsub(/(?<![\p{L}\p{N}])#{Regexp.escape(term)}(?![\p{L}\p{N}])/i, word)
    end

    attr_reader :scope

    def initialize(scope:)
      @scope = scope
    end

    # kind: a kind or a list of kinds of this scope (anything else raises BadKind). student_key only narrows the teacher's answers.
    def call(query, subject: nil, kind: nil, status: nil, limit: 20)
      Schema.ensure!
      kinds = Array(kind).map(&:to_s).reject(&:empty?)
      bad = kinds - scope.kinds
      raise BadKind, bad.first unless bad.empty?

      terms = Text.query_terms(query)
      filters = { subject: subject.presence, kinds: kinds.presence, status: status.presence }
      return Result.new(query: query.to_s, terms: terms, variants: [], hits: [], semantic: false, indexed: Index.built?, corrections: {}, source: nil) if terms.empty?

      embedding = start_embedding(query.to_s)
      lists, corrections = candidates(query.to_s, terms, filters, embedding: embedding)
      Result.new(query: query.to_s, terms: terms, variants: corrections.values.flatten, hits: Ranker.fuse(lists, limit: limit), semantic: lists.key?(:semantic),
                 indexed: Index.built?, corrections: corrections, source: nil)
    end

    # "Simili": the nearest neighbours of an object, from the vectors already stored (no call to the service). +ref+ is a key
    # (math.powers-properties) or an address as Search::Links.address writes it (item:KEY#seed, lesson_card:KEY#scheda-2). The object
    # itself is left out; other documents of the same key (the other instances of an item) are kept, for the reviewer to see them.
    # Only for a scope that may use vectors; kinds default to the family of the object (questions with questions, cards with cards).
    # Returns a Result with semantic false and no hits when the object has no vector (nothing indexed, service never configured).
    def like(ref, subject: nil, kind: nil, status: nil, limit: 20)
      Schema.ensure!
      raise SemanticOff unless scope.semantic?

      kinds = Array(kind).map(&:to_s).reject(&:empty?)
      bad = kinds - scope.kinds
      raise BadKind, bad.first unless bad.empty?

      source = like_source(ref.to_s.strip)
      empty = Result.new(query: ref.to_s, terms: [], variants: [], hits: [], semantic: false, indexed: Index.built?, corrections: {}, source: source)
      return empty unless source

      kinds = FAMILIES.fetch(source.kind, [ source.kind ]) & scope.kinds if kinds.empty?
      row = select("SELECT v.vec FROM search_vectors v WHERE v.doc_id = ?", [ source.id ]).first
      return empty unless row

      filters = { subject: subject.presence, kinds: kinds.presence, status: status.presence }
      hits = Semantic.nearest(self, Vectors.unpack(row["vec"]), model: Embedder.current.model, filters: filters, limit: limit, min: 0.0, exclude: source.id)
      Result.new(query: ref.to_s, terms: [], variants: [], hits: hits, semantic: true, indexed: true, corrections: {}, source: source)
    end

    FAMILIES = { "item" => %w[item item_instance practice_item], "item_instance" => %w[item item_instance practice_item],
                 "practice_item" => %w[item item_instance practice_item], "lesson_card" => %w[lesson_card glossary_term],
                 "glossary_term" => %w[lesson_card glossary_term] }.freeze

    # The document a reference names, among those this scope may see: [kind:]key[#anchor]; a bare key takes the first kind in key_hits' order.
    def like_source(ref)
      kind = nil
      if (m = ref.match(/\A([a-z_]+):(.+)\z/)) && Doc::KINDS.include?(m[1])
        kind = m[1]
        ref = m[2]
      end
      key, anchor = ref.split("#", 2)
      return nil if key.blank?

      where, binds = where({})
      sql = +"SELECT #{COLUMNS} FROM search_documents d WHERE d.key = ? COLLATE NOCASE AND #{where}"
      binds = [ key, *binds ]
      if kind
        sql << " AND d.kind = ?"
        binds << kind
      end
      sql << (anchor ? " AND d.anchor = ?" : "")
      binds << anchor if anchor
      sql << " ORDER BY #{KEY_ORDER}, (d.anchor IS NOT NULL), d.id LIMIT 1"
      row = select(sql, binds).first
      row && hit(row.merge("score" => 0.0), :key)
    end

    # The embedding of the question starts at once, beside the lexical queries: the service takes about 0.17 s. nil when the scope
    # never uses vectors (the student's) or there is no service.
    def start_embedding(query)
      return nil unless scope.semantic?

      Thread.new do
        Embedder.query_vector(query)
      rescue StandardError => e
        Rails.logger.warn("search: embedding the question failed (#{e.class})")
        nil
      end
    end

    # The ordered lists the ranker merges: {key: [Hit], lexical: [Hit], (staff and agents, service answering) semantic: [Hit]}, and the
    # corrections the typo fallback used.
    def candidates(query, terms, filters, embedding: nil)
      content = Text.content_terms(terms)
      lexical = run(match_for(content, :and), filters, 100, :lexical, content)
      lexical += run(match_for(content, :or), filters, 100, :lexical, content) if lexical.size < MIN_HITS && content.size > 1
      variants = {}
      if lexical.size < MIN_HITS
        variants = variants_for(content, filters)
        lexical += run(match_for(content, :and, variants), filters, 100, :typo, content) if variants.any?
        lexical += run(match_for(content, :or, variants), filters, 100, :typo, content + variants.values.flatten) if lexical.size < MIN_HITS && variants.any? && content.size > 1
      end
      lists = { key: key_hits(query, filters), lexical: lexical.uniq(&:id) }
      # The staff's and the agents' scopes answer semantic? with true when an embedder is configured; the student's never does.
      semantic = scope.semantic? ? semantic_list(embedding, filters) : nil
      lists[:semantic] = semantic if semantic
      [ lists, variants ]
    end

    # The cosine list for a question embedded by +embedding+ (a Thread, see start_embedding): nil (the search stays lexical, the
    # result says semantic false) when the service did not answer or nothing has a vector yet.
    def semantic_list(embedding, filters)
      vector = embedding&.value or return nil
      embedder = Embedder.current or return nil
      hits = Semantic.nearest(self, vector, model: embedder.model, filters: filters, limit: SEMANTIC_LIMIT, min: Embedder.min_similarity)
      hits.empty? && !Vectors.any?(embedder) ? nil : hits
    end

    # ---- queries ----------------------------------------------------------------------------------

    def where(filters)
      sql, binds = scope.clause
      sql = +sql
      binds = binds.dup
      if filters[:subject]
        sql << " AND d.subject = ?"
        binds << filters[:subject]
      end
      if filters[:kinds]
        sql << " AND d.kind IN (#{filters[:kinds].map { '?' }.join(', ')})"
        binds.concat(filters[:kinds])
      end
      if filters[:status]
        sql << " AND d.status = ?"
        binds << filters[:status]
      end
      [ sql, binds ]
    end

    # The statement carries the person's words: it is run under the name SCHEMA, which Rails's log subscriber does not print, so the
    # words are not in the log at any log level (the student's search is never recorded).
    def select(sql, binds) = Record.connection.select_all(Record.sanitize_sql_array([ sql, *binds ]), "SCHEMA").to_a

    def run(match, filters, limit, kind, terms = [])
      where, binds = where(filters)
      rows = select(<<~SQL, [ match, *binds, limit ])
        SELECT #{COLUMNS}, -bm25(search_fts, #{TITLE_WEIGHT}, #{BODY_WEIGHT}, #{STEMS_WEIGHT}) AS score
        FROM search_fts JOIN search_documents d ON d.id = search_fts.rowid
        WHERE search_fts MATCH ? AND #{where}
        ORDER BY bm25(search_fts, #{TITLE_WEIGHT}, #{BODY_WEIGHT}, #{STEMS_WEIGHT}) LIMIT ?
      SQL
      rerank(rows.map { |r| hit(r, kind) }, terms)
    end

    # The same hits, a title that holds the words first among equals of the bm25 order.
    def rerank(hits, terms)
      return hits if terms.empty?

      hits.each_with_index.sort_by { |h, i| [ -(h.score + TITLE_BONUS * title_share(h.title, terms)), i ] }.map(&:first)
    end

    def title_share(title, terms)
      words = Text.tokens(title)
      return 0.0 if words.empty?

      stems = words.flat_map { |w| Text.stems(w) }.to_set
      held = terms.count do |term|
        folded = Text.fold(term)
        words.any? { |w| Text.fold(w) == folded } || Text.stems(term).any? { |s| stems.include?(s) }
      end
      held.to_f / terms.size
    end

    # A document whose key is the question (case does not matter): the object the person named.
    def key_hits(query, filters)
      key = query.strip
      return [] unless key.match?(/\A[A-Za-z0-9][A-Za-z0-9._:\-]*\z/) && key.length >= 3

      where, binds = where(filters)
      rows = select(<<~SQL, [ key, *binds ])
        SELECT #{COLUMNS}, 1000.0 AS score FROM search_documents d
        WHERE d.key = ? COLLATE NOCASE AND #{where}
        ORDER BY #{KEY_ORDER},
                 (d.anchor IS NOT NULL), d.id LIMIT 20
      SQL
      rows.map { |r| hit(r, :key) }
    end

    def hit(row, match)
      fields = (Hit.members - %i[score match]).to_h { |m| [ m, row[m.to_s] ] }
      Hit.new(**fields, score: row["score"].to_f, match: match)
    end

    # The FTS5 expression of the words: each word is its text in the title or the body, or one of its Snowball stems (any of the
    # three languages) in the stems column, or one of its corrections; the last word also as a prefix, for a question being typed.
    def match_for(terms, mode, variants = {})
      parts = terms.each_with_index.map do |term, i|
        last = i == terms.size - 1
        words = [ term ] + Array(variants[term])
        alternatives = words.flat_map do |w|
          star = last && w == term ? "*" : ""
          [ "{title body} : \"#{w}\"#{star}" ] + Text.stems(w).map { |s| "stems : \"#{s}\"#{star}" }
        end
        "(#{alternatives.uniq.join(' OR ')})"
      end
      parts.join(mode == :and ? " AND " : " OR ")
    end

    # {term => [corrected words]}: the words of the documents this scope may see that are within the term's typo tolerance of it.
    def variants_for(terms, filters)
      terms.each_with_object({}) do |term, out|
        limit = Text.tolerance(term)
        next if limit.zero?

        folded = Text.fold(term)
        grams = folded.chars.each_cons(3).map(&:join).uniq
        next if grams.empty?

        where, binds = where(filters)
        rows = select(<<~SQL, [ grams.map { |g| "\"#{g}\"" }.join(" OR "), *binds ])
          SELECT d.title, d.body FROM search_trigram t JOIN search_documents d ON d.id = t.rowid
          WHERE search_trigram MATCH ? AND #{where} ORDER BY bm25(search_trigram) LIMIT 60
        SQL
        tokens = rows.flat_map { |r| Text.tokens(Text.fold("#{r['title']} #{r['body']}")) }.tally
        found = tokens.keys.select { |t| t != folded && t.length >= 3 && (d = Text.distance(folded, t, limit)) >= 1 && d <= limit }
        out[term] = found.sort_by { |t| [ Text.distance(folded, t, limit), -tokens[t] ] }.first(MAX_VARIANTS) if found.any?
      end
    end
  end
end
