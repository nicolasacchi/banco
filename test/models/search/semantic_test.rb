require "test_helper"
require "socket"

# The semantic half of the content search (D-300) on a small invented corpus, with the stub embedder (no network).
class SearchSemanticTest < ActiveSupport::TestCase
  SYNONYMS = { "automobile" => "auto", "macchina" => "auto", "elettrica" => "elettrico", "vettura" => "auto" }.freeze
  DOCS = [
    [ "lesson_card", "lezione.sci.auto", "Le auto elettriche", "Un'auto elettrica ha un motore alimentato da una batteria.", "chemistry" ],
    [ "lesson_card", "lezione.math.potenze", "Le potenze", "Una potenza è una moltiplicazione ripetuta: tre alla seconda fa nove.", "math" ],
    [ "item", "math-frazioni-1", "Calcola la somma di due frazioni", "Frazioni con denominatore diverso: denominatore comune.", "math" ],
    [ "item_instance", "math-frazioni-1", "Calcola la somma di due frazioni: un quarto e un terzo", "Frazioni con denominatore diverso.", "math", "seed-a" ],
    [ "item_instance", "math-frazioni-1", "Calcola la somma di due frazioni: due quinti e un sesto", "Frazioni con denominatore diverso.", "math", "seed-b" ],
    [ "item", "math-frazioni-2", "Somma tra due frazioni con denominatori diversi", "Calcola la somma: denominatore comune.", "math" ],
    [ "item", "math-potenze-1", "Calcola una potenza", "Tre alla quarta.", "math" ],
    [ "skill", "math.powers-properties", "Proprietà delle potenze", "Moltiplicare e dividere potenze della stessa base.", "math" ]
  ].freeze

  setup do
    Search::Index.replace_group("lessons", DOCS.each_with_index.map do |(kind, key, title, body, subject, anchor), i|
      Search::Doc.build(kind: kind, key: key, title: title, body: body, subject: subject, status: "draft", anchor: anchor, unique: i)
    end)
    Search::Index.replace_group("answers", [ Search::Doc.build(kind: "student_answer", key: "math-frazioni-1", title: "Risposta", body: "automobile zzrispostazz",
                                                              subject: "math", student_key: "student", unique: "a1") ])
    @stub = Search::Embedder::Stub.new(synonyms: SYNONYMS)
  end

  def using(client = @stub, &block) = Search::Embedder.using(client, &block)

  def build! = Search::Vectors.build!(@stub)

  def staff = Search::Engine.new(scope: Search::Scope::Staff.new)

  def vector_count = Search::Index.rows("SELECT COUNT(*) FROM search_vectors").dig(0, 0)

  # ---- the HTTP client against a local server ---------------------------------------------------

  def serve(status: 200, body: nil, close: false)
    server = TCPServer.new("127.0.0.1", 0)
    requests = []
    thread = Thread.new do
      loop do
        socket = server.accept
        request_line = socket.gets
        headers = {}
        while (line = socket.gets) && line != "\r\n"
          k, v = line.split(": ", 2)
          headers[k.downcase] = v.strip
        end
        payload = JSON.parse(socket.read(headers["content-length"].to_i))
        requests << [ request_line.strip, payload ]
        unless close
          answer = body ? body.call(payload) : JSON.generate(payload["inputs"].map { |t| [ 3.0, 4.0, t.to_s.size.to_f ] })
          socket.write("HTTP/1.1 #{status} X\r\nContent-Type: application/json\r\nContent-Length: #{answer.bytesize}\r\nConnection: close\r\n\r\n#{answer}")
        end
        socket.close
      end
    rescue IOError, Errno::EBADF
      nil
    end
    yield "http://127.0.0.1:#{server.addr[1]}", requests
  ensure
    server&.close
    thread&.kill
  end

  test "the HTTP client posts the inputs to /embed and returns normalized vectors" do
    serve do |url, requests|
      http = Search::Embedder::Http.new(url: url, model: "m")
      vectors = http.embed_query("ciao")
      assert_equal [ "POST /embed HTTP/1.1", { "inputs" => [ "ciao" ] } ], requests.first
      assert_in_delta 1.0, Math.sqrt(vectors.sum { |x| x * x }), 1e-9
      assert_equal 3, http.dimension
    end
  end

  test "documents go in batches of at most 8 inputs" do
    serve do |url, requests|
      vectors = Search::Embedder::Http.new(url: url).embed_documents(Array.new(19) { |i| "testo #{i}" })
      assert_equal 19, vectors.size
      assert_equal [ 8, 8, 3 ], requests.map { |_, payload| payload["inputs"].size }
    end
  end

  test "a service that is down, answers badly or hangs up is Unavailable, never another error" do
    http = Search::Embedder::Http.new(url: "http://127.0.0.1:1")
    assert_raises(Search::Embedder::Unavailable) { http.embed_query("x") }
    serve(status: 500, body: ->(_) { "no" }) { |url, _| assert_raises(Search::Embedder::Unavailable) { Search::Embedder::Http.new(url: url).embed_query("x") } }
    serve(body: ->(_) { "not json" }) { |url, _| assert_raises(Search::Embedder::Unavailable) { Search::Embedder::Http.new(url: url).embed_query("x") } }
    serve(body: ->(_) { "[[1.0]]" }) { |url, _| assert_raises(Search::Embedder::Unavailable) { Search::Embedder::Http.new(url: url).embed_documents(%w[a b]) } }
    serve(close: true) { |url, _| assert_raises(Search::Embedder::Unavailable) { Search::Embedder::Http.new(url: url).embed_query("x") } }
  end

  test "the embedder is chosen by configuration: no URL, no embedder, whatever the network" do
    ENV.delete("BANCO_EMBED_URL")
    assert_nil Search::Embedder.current
    assert_not Search::Embedder.configured?
    assert_not Search::Scope::Staff.new.semantic?
    ENV["BANCO_EMBED_URL"] = "http://127.0.0.1:1"
    assert_kind_of Search::Embedder::Http, Search::Embedder.current
    assert_predicate Search::Scope::Agent.new, :semantic?
  ensure
    ENV.delete("BANCO_EMBED_URL")
  end

  # ---- the vectors --------------------------------------------------------------------------------

  test "every content document gets a vector, a student's answer never" do
    result = build!
    assert_equal DOCS.size, result[:embedded]
    assert_equal 0, result[:pending]
    assert_equal DOCS.size, vector_count
    assert_equal 0, Search::Index.rows("SELECT COUNT(*) FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id WHERE d.kind = 'student_answer'").dig(0, 0)
    assert_equal [ [ "stub-hash", 1024 ] ], Search::Index.rows("SELECT DISTINCT model, dim FROM search_vectors")
    assert_equal({ eligible: DOCS.size, with_vectors: DOCS.size, current: DOCS.size, missing: 0, models: [ "stub-hash" ], dimension: 1024, embedder: "stub-hash" },
                 Search::Vectors.status(@stub))
  end

  test "the text sent to the model holds no student word" do
    seen = []
    spy = Search::Embedder::Stub.new
    spy.define_singleton_method(:embed_documents) { |texts| seen.concat(texts) && super(texts) }
    Search::Vectors.build!(spy)
    assert_equal DOCS.size, seen.size
    assert seen.none? { |t| t.include?("zzrispostazz") }
  end

  test "a second build embeds nothing; a changed document is embedded again, alone" do
    build!
    assert_equal 0, build![:embedded]
    changed = DOCS.each_with_index.map do |(kind, key, title, body, subject, anchor), i|
      Search::Doc.build(kind: kind, key: key, title: title, body: i.zero? ? "#{body} Cambia." : body, subject: subject, status: "draft", anchor: anchor, unique: i)
    end
    Search::Index.replace_group("lessons", changed)
    assert_equal DOCS.size - 1, vector_count
    assert_equal 1, build![:embedded]
    assert_equal DOCS.size, vector_count
  end

  test "another model or another dimension makes every vector stale" do
    build!
    assert_equal DOCS.size, Search::Vectors.build!(Search::Embedder::Stub.new(model: "stub-2"))[:embedded]
    assert_equal [ "stub-2" ], Search::Index.rows("SELECT DISTINCT model FROM search_vectors").flatten
    assert_equal DOCS.size, Search::Vectors.build!(Search::Embedder::Stub.new(model: "stub-2", dimension: 64))[:embedded]
    assert_equal [ 64 ], Search::Index.rows("SELECT DISTINCT dim FROM search_vectors").flatten
  end

  test "a service that goes down leaves the lexical index whole and the vectors for the next run" do
    Search::Index.replace_group("filler", Array.new(10) { |i| Search::Doc.build(kind: "skill", key: "filler.#{i}", title: "Riempitivo #{i}", body: "testo #{i}", subject: "math", unique: i) })
    total = DOCS.size + 10
    flaky = Search::Embedder::Stub.new
    calls = 0
    flaky.define_singleton_method(:embed_documents) do |texts|
      calls += 1
      raise Search::Embedder::Unavailable, "down" if calls > 1

      super(texts)
    end
    result = Search::Vectors.build!(flaky)
    assert_equal 8, result[:embedded]
    assert_equal total - 8, result[:pending]
    assert result[:down]
    assert_equal 8, vector_count
    assert_includes using(nil) { staff.call("potenze") }.hits.map(&:title), "Le potenze"
    assert_equal 0, Search::Vectors.build!(nil)[:embedded]
    assert_equal total - 8, Search::Vectors.build!(@stub)[:embedded]
  end

  # ---- the ranking --------------------------------------------------------------------------------

  test "a paraphrase that shares no word finds the document the words miss" do
    build!
    lexical = using(nil) { staff.call("automobile") }
    assert_empty lexical.hits
    assert_equal false, lexical.semantic
    hybrid = using { staff.call("automobile") }
    assert hybrid.semantic
    assert_equal "Le auto elettriche", hybrid.hits.first.title
    assert_equal :semantic, hybrid.hits.first.match
  end

  test "without vectors, or with a service that is down, the answer is lexical and says so" do
    result = using { staff.call("potenze") }
    assert_equal false, result.semantic, "no vector has been built yet"
    assert_includes result.hits.map(&:title), "Le potenze"
    build!
    down = Search::Embedder::Stub.new
    down.define_singleton_method(:embed_query) { |_| raise Search::Embedder::Unavailable, "down" }
    Search::Embedder.using(down) do
      result = staff.call("potenze")
      assert_equal false, result.semantic
      assert_includes result.hits.map(&:title), "Le potenze"
      assert_equal false, staff.call("potenze").semantic, "left alone for the cooldown"
    end
  end

  test "an exact key stays first, and fusion lets both lists speak" do
    build!
    result = using { staff.call("math.powers-properties") }
    assert_equal "math.powers-properties", result.hits.first.key
    assert_equal :key, result.hits.first.match
    fused = Search::Ranker.fuse({ key: [], lexical: [ hit(1), hit(2), hit(3) ], semantic: [ hit(3), hit(4), hit(1) ] }, limit: 10)
    assert_equal [ 1, 3, 2, 4 ], fused.map(&:id)
    assert_equal [ 9, 1 ], Search::Ranker.fuse({ key: [ hit(9) ], lexical: [ hit(1) ], semantic: [ hit(9), hit(1) ] }, limit: 10).map(&:id)
  end

  test "the teacher's answers tab and the student's door never use a model" do
    build!
    spy = Search::Embedder::Stub.new
    spy.define_singleton_method(:embed_query) { |_| raise "a model was asked" }
    Search::Embedder.using(spy) do
      assert_not Search::Scope::Staff.new(answers_for: "student").semantic?
      assert_not Search::Scope::Student.new(Object.new).semantic?
      assert_equal false, Search::Engine.new(scope: Search::Scope::Staff.new(answers_for: "student")).call("zzrispostazz", kind: "student_answer").semantic
      assert_equal [ "Risposta" ], Search::Engine.new(scope: Search::Scope::Staff.new(answers_for: "student")).call("zzrispostazz", kind: "student_answer").hits.map(&:title)
    end
  end

  def hit(id)
    Search::Engine::Hit.new(id: id, kind: "item", subject: nil, key: "k#{id}", revision_table: nil, revision_id: nil, status: nil, title: "t", body: "b", anchor: nil,
                            lang: "it", topic_key: nil, skill: nil, student_key: nil, occurred_at: nil, score: 0.0, match: :lexical)
  end

  # ---- Simili -------------------------------------------------------------------------------------

  test "like finds the near-duplicates of an item and labels the other documents of the same key" do
    build!
    result = using { staff.like("item:math-frazioni-1") }
    assert result.semantic
    assert_equal "math-frazioni-1", result.source.key
    assert_equal "item", result.source.kind
    keys = result.hits.map(&:key)
    assert_not_includes result.hits.map(&:id), result.source.id
    assert_includes keys, "math-frazioni-2", "the near-duplicate item is found"
    assert_operator keys.index("math-frazioni-2"), :<, keys.index("math-potenze-1")
    assert_equal %w[item item_instance], result.hits.map(&:kind).uniq.sort, "questions are compared with questions"
  end

  test "like of one instance shows the other instances of the same item" do
    build!
    result = using { staff.like("item_instance:math-frazioni-1#seed-a") }
    assert_equal "seed-a", result.source.anchor
    other = result.hits.find { |h| h.anchor == "seed-b" }
    assert other
    assert_equal "math-frazioni-1", other.key
  end

  test "like needs a scope that may use vectors, and tells nothing for an unknown object" do
    build!
    assert_raises(Search::Engine::SemanticOff) { using(nil) { staff.like("math-frazioni-1") } }
    assert_raises(Search::Engine::SemanticOff) { using { Search::Engine.new(scope: Search::Scope::Student.new(Object.new)).like("math-frazioni-1") } }
    result = using { staff.like("no-such-key") }
    assert_nil result.source
    assert_empty result.hits
  end

  test "like can be narrowed by kind and subject" do
    build!
    result = using { staff.like("math-frazioni-1", kind: "skill", subject: "math") }
    assert_equal [ "math.powers-properties" ], result.hits.map(&:key)
  end

  # ---- the cost -----------------------------------------------------------------------------------

  test "the coarse form keeps the order of the cosines well enough to pick candidates" do
    random = Random.new(7)
    base = Search::Vectors.normalize(Array.new(1024) { random.rand - 0.5 })
    near = Search::Vectors.normalize(base.map { |x| x + (random.rand - 0.5) * 0.2 })
    far = Array.new(40) { Search::Vectors.normalize(Array.new(1024) { random.rand - 0.5 }) }
    q = Search::Vectors.coarse(base)
    assert_operator Search::Semantic.dot(q, Search::Vectors.coarse(near)), :>, far.map { |v| Search::Semantic.dot(q, Search::Vectors.coarse(v)) }.max
  end
end
