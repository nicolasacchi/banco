require "lingua/stemmer"

module Search
  # Text for the index and for the query: plain reading of the agents' markup, tokens, Snowball stems (Italian,
  # Spanish, English: the ruby-stemmer gem, libstemmer's own code) and the snippet with the words that matched.
  # Pure: no database.
  module Text
    LANGS = %w[it es en].freeze
    TOKEN = /[\p{L}\p{N}]+/
    # Italian function words, dropped from a long question ("come si calcola la potenza di un numero") before the
    # query is widened; never dropped from a single word.
    STOPWORDS = %w[a ad al alla alle allo agli ai che chi ci come con col da dal dalla dalle dallo dei del della delle dello degli di
                   e ed è era gli ha hanno ho i il in io la le lo lui lei ma mi ne nel nella nelle nello negli non o per più
                   quale quali quando quanto quella quello questa queste questi questo se si sono su sul sulla sulle sullo
                   sui un una uno tra fra tu vi cosa cos].to_set.freeze
    MUTEX = Mutex.new

    module_function

    # NFKC, lowercase.
    def normalize(text) = text.to_s.unicode_normalize(:nfkc).downcase

    # Without accents (è -> e), like the index's unicode61 remove_diacritics.
    def fold(text) = normalize(text).unicode_normalize(:nfd).gsub(/\p{Mn}/, "")

    def tokens(text) = normalize(text).scan(TOKEN)

    # The Snowball stem of a (lowercase) word in +lang+; numbers are left as they are.
    def stem(word, lang)
      return word if word.match?(/\A\p{N}+\z/) || word.length < 3

      MUTEX.synchronize { ((@stemmers ||= {})[lang] ||= Lingua::Stemmer.new(language: lang)).stem(word) }
    end

    # The distinct stems of a word over +langs+ (a lesson of English holds Italian and English words).
    def stems(word, langs = LANGS) = langs.map { |l| stem(word, l) }.uniq

    # The text column of the stems: every token's stems over +langs+, space-joined (repeats kept for the ranking).
    def stem_column(text, langs)
      tokens(text).flat_map { |t| stems(t, langs) }.join(" ")
    end

    # Agents' markup as plain words: spans [[g:term]] [[en:words]] [[role|it:words]], links [text](scheda:slug), bold, math dropped.
    def plain(text)
      s = text.to_s.gsub("\r\n", "\n")
      s = s.gsub(/\$\$.*?\$\$/m, " ").gsub(/\$[^$\n]*\$/, " ")
      s = s.gsub(/\[\[[a-z]+(?:[_-][a-z]+)*(?:\|it)?:(.*?)\]\](?!\])/m, '\1')
      s = s.gsub(/\[([^\[\]]*)\]\((?:scheda|argomento):[^()]*\)/, '\1')
      s.gsub(/\*\*|^\s*[-*]\s+|^\s*\d+\.\s+/, " ").gsub(/\s+/, " ").gsub(/\s+([.,;:!?])/, '\\1').strip
    end

    # Every string worth reading in a structure of hashes and arrays: the values under keys that carry words.
    SKIP_KEYS = %w[n id type icon tone role level kind tex key ref src component input accents answer accept view schema schema_version diagram schema_name
                   hero part targets pick listen mixed scientific reuse_right sha256 revision page].to_set.freeze

    def strings(node, out = [])
      case node
      when String then out << plain(node)
      when Array then node.each { |e| strings(e, out) }
      when Hash then node.each { |k, v| strings(v, out) unless SKIP_KEYS.include?(k.to_s) }
      end
      out.reject(&:empty?)
    end

    def join(*parts) = parts.flatten.compact.map { |p| p.to_s.strip }.reject(&:empty?).join(" \n ")

    # The words of a query, folded: ["equazioni", "primo", "grado"]. Characters outside letters and digits only separate.
    def query_terms(query) = tokens(query).first(12)

    def content_terms(terms)
      kept = terms.reject { |t| STOPWORDS.include?(t) || t.length < 2 }
      kept.empty? ? terms : kept
    end

    # Levenshtein distance, with an early exit above +limit+.
    def distance(a, b, limit = 3)
      return limit + 1 if (a.length - b.length).abs > limit

      prev = (0..b.length).to_a
      a.each_char.with_index(1) do |ca, i|
        cur = [ i ]
        b.each_char.with_index(1) { |cb, j| cur << [ prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca == cb ? 0 : 1) ].min }
        return limit + 1 if cur.min > limit

        prev = cur
      end
      prev.last
    end

    # How many typos a word of this length forgives.
    def tolerance(word) = word.length >= 8 ? 2 : (word.length >= 4 ? 1 : 0)

    # The segments of a snippet: [[text, matched], ...]. +terms+ are query words (folded) and +variants+ their typo
    # corrections; a word matches when it equals a term, shares its stem or (the last term) starts with it.
    def snippet(body, terms, variants: [], width: 160)
      text = body.to_s.gsub(/\s+/, " ").strip
      return [] if text.empty?

      wanted = (terms + variants).to_set { |t| fold(t) }
      stems = wanted.flat_map { |t| stems(t) }.to_set
      prefix = terms.last
      spans = []
      text.scan(TOKEN) { spans << [ Regexp.last_match.begin(0), Regexp.last_match.end(0), matches?(Regexp.last_match[0], wanted, stems, prefix) ] }
      first = spans.find { |s| s[2] }
      start = first ? [ first[0] - width / 3, 0 ].max : 0
      start = text.rindex(/\s/, start) + 1 if start.positive? && text.rindex(/\s/, start)
      stop = [ start + width, text.length ].min
      stop = (text.index(/\s/, stop) || text.length) if stop < text.length && text[stop] =~ /\p{L}/
      out = []
      pos = start
      spans.each do |from, to, hit|
        next if to <= start || from >= stop

        out << [ text[pos...from], false ] if from > pos
        out << [ text[from...to], hit ]
        pos = to
      end
      out << [ text[pos...stop], false ] if pos < stop
      out.unshift([ "… ", false ]) if start.positive?
      out << [ " …", false ] if stop < text.length
      out.chunk_while { |a, b| a[1] == b[1] }.map { |run| [ run.map(&:first).join, run.first[1] ] }
    end

    def matches?(word, wanted, stems, prefix)
      folded = fold(word)
      return true if wanted.include?(folded)
      return true if prefix && prefix.length >= 2 && folded.start_with?(fold(prefix))

      stems(normalize(word)).any? { |s| stems.include?(s) }
    end
  end
end
