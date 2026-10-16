require "test_helper"
require_relative "../support/search_world"

# The agents' search over the API (D-299): content and references, drafts included; never anything a student typed.
class SearchApiTest < ActionDispatch::IntegrationTest
  include SearchWorld

  ROW_KEYS = %w[kind subject key revision_id status title snippet score ref].freeze

  setup do
    build_search_world
    add_draft_revision!
    add_orphan_lesson!
    add_answers!(@official, ANSWER_WORD, refused: REFUSED_WORD)
    add_answers!(@trial_student, TRIAL_ANSWER_WORD)
    add_diagnosis_answer!(@official, DIAGNOSIS_ANSWER_WORD)
    rebuild_search!
    @token = ApiToken.issue!(role: "agent_claude", label: "search test")
  end

  def api(query, extra = {})
    on(:api, "/api/v1/search?#{{ q: query }.merge(extra).to_query}", headers: { "Authorization" => "Bearer #{@token}" })
    response
  end

  def json = response.parsed_body

  test "the answer has the documented shape" do
    api("equazione")
    assert_response :success
    assert_equal %w[indexed query results semantic], json.keys.sort
    assert_equal false, json["semantic"]
    assert_equal "equazione", json["query"]
    assert_predicate json["results"], :any?
    json["results"].each { |row| assert_equal ROW_KEYS.sort, row.keys.sort }
    assert_equal "topic:#{TOPIC}", json["results"].find { |r| r["kind"] == "topic" }["ref"]
    ContractExamples.record(self, "search", "results", request: request, response: response)
  end

  test "drafts, orphans, entry-test items and hints are found" do
    [ DRAFT_WORD, ORPHAN_WORD, DIAGNOSIS_WORD, LEAKS[:hint] ].each do |word|
      api(word)
      assert_predicate json["results"], :any?, word
    end
  end

  test "nothing a student typed is a result, by any word or kind" do
    [ ANSWER_WORD, TRIAL_ANSWER_WORD, REFUSED_WORD, DIAGNOSIS_ANSWER_WORD ].each do |word|
      api(word)
      assert_response :success
      assert_empty json["results"], word
      assert_not_includes response.body, "student_answer"
    end
  end

  test "the kind student_answer does not exist for agents" do
    api(ANSWER_WORD, kind: "student_answer")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    assert_equal "kind", json["field"]
    api(ANSWER_WORD, kind: "lesson_card,student_answer")
    assert_response :not_found
    api(ANSWER_WORD, student: "student", tab: "answers")
    assert_empty json["results"]
  end

  test "no answer key and no solution is a result, and no row carries a body" do
    [ LEAKS[:key], LEAKS[:solution], "27182", "31415" ].each do |word|
      api(word)
      assert_empty json["results"], word
    end
    api("radice quadrata")
    assert_not_includes response.body, LEAKS[:key]
    json["results"].each { |row| assert_not row.key?("body") }
  end

  test "filters and limits, a missing query and an unknown subject" do
    api("equazione", kind: "topic")
    assert_equal [ "topic" ], json["results"].map { |r| r["kind"] }.uniq
    api("equazione", limit: 2)
    assert_operator json["results"].size, :<=, 2
    api("equazione", subject: "math")
    assert_predicate json["results"], :any?
    api("equazione", subject: "nonsense")
    assert_response :not_found
    api("")
    assert_response :unprocessable_entity
    assert_equal "E-FILES", json["code"]
  end

  test "the exact key comes first" do
    api(SKILL)
    assert_equal "skill", json["results"].first["kind"]
    api("leaky-item-1")
    assert_equal "item", json["results"].first["kind"]
  end

  test "reference texts are found by article for citing" do
    ReferenceText.create!(key: "costituzione-test", title: "Costituzione", source_url: "https://example.org/c", sha256: "9" * 64,
                          body: "Art. 1\nL'Italia è una Repubblica democratica, fondata sul lavoro.\n\nArt. 2\nLa Repubblica riconosce e garantisce i diritti inviolabili.\n")
    Search::Indexer.reindex(%w[references])
    api("repubblica democratica", kind: "reference_article")
    assert_equal "reference_article:costituzione-test#art-1", json["results"].first["ref"]
    api("diritti inviolabili", kind: "reference_article")
    assert_equal "reference_article:costituzione-test#art-2", json["results"].first["ref"]
  end

  test "a token is needed and the search is in the contract" do
    on(:api, "/api/v1/search?q=equazione")
    assert_response :unauthorized
    on(:api, "/api/v1/schema", headers: { "Authorization" => "Bearer #{@token}" })
    assert_includes response.parsed_body["commands"].map { |c| c["name"] }, "search"
  end

  test "the web listener has no api search" do
    on(:web, "/api/v1/search?q=equazione", headers: { "Authorization" => "Bearer #{@token}" })
    assert_response :not_found
  end

  # ---- semantic ranking and "Simili" (D-300) ----------------------------------------------------

  def with_stub(&block)
    Search::Embedder.using(Search::Embedder::Stub.new) do
      Search::Indexer.embed!
      block.call
    end
  end

  test "with an embedder the answer says semantic true; the answers of students are in no vector" do
    with_stub do
      api("equazione")
      assert_response :success
      assert_equal true, json["semantic"]
      assert_equal 0, Search::Index.rows("SELECT COUNT(*) FROM search_vectors v JOIN search_documents d ON d.id = v.doc_id WHERE d.kind = 'student_answer' OR d.audience = 'teacher'").dig(0, 0)
      assert_operator Search::Vectors.status[:missing], :==, 0
      [ ANSWER_WORD, TRIAL_ANSWER_WORD, REFUSED_WORD, DIAGNOSIS_ANSWER_WORD ].each do |word|
        api(word)
        assert_empty json["results"], word
        api("risposta #{word}")
        assert_not_includes response.body, "student_answer"
        assert_not_includes json["results"].to_json, word
      end
    end
  end

  test "without an embedder, or with the service down, the same question is answered lexically" do
    with_stub do
      api("equazione")
      assert_equal true, json["semantic"]
    end
    api("equazione")
    assert_equal false, json["semantic"]
    assert_predicate json["results"], :any?
    down = Search::Embedder::Stub.new
    down.define_singleton_method(:embed_query) { |_| raise Search::Embedder::Unavailable, "down" }
    Search::Embedder.using(down) do
      api("equazione")
      assert_response :success
      assert_equal false, json["semantic"]
      assert_predicate json["results"], :any?
    end
  end

  test "like gives the neighbours of an item, without the item, and labels its other documents" do
    with_stub do
      api_like("demo-item-1")
      assert_response :success
      assert_equal %w[indexed like query results semantic], json.keys.sort
      assert_equal true, json["semantic"]
      assert_equal "item:demo-item-1", json["like"]
      assert_predicate json["results"], :any?
      assert_not_includes json["results"].map { |r| r["ref"] }, "item:demo-item-1"
      json["results"].each { |row| assert_equal (ROW_KEYS + %w[same_object]).sort, row.keys.sort }
      assert(json["results"].any? { |r| r["same_object"] }, "the instances of the item itself are shown, and labelled")
      assert(json["results"].any? { |r| r["key"] == "demo-item-2" && !r["same_object"] }, "the other item is a neighbour, not the same object")
      api_like("demo-item-1", limit: 1)
      assert_equal [ "demo-item-2" ], json["results"].map { |r| r["key"] }
      ContractExamples.record(self, "search", "like", request: request, response: response)
    end
  end

  test "like takes a ref, a kind and a subject, and refuses what it cannot answer" do
    with_stub do
      api_like("practice_item:demo-item-1")
      assert_response :success
      api_like("demo-item-1", kind: "item")
      assert_equal [ "item" ], json["results"].map { |r| r["kind"] }.uniq
      api_like("demo-item-1", subject: "nosuchsubject")
      assert_response :not_found
      api_like("demo-item-1", subject: "math")
      assert_predicate json["results"], :any?
      api_like("no-such-key")
      assert_response :not_found
      assert_equal "like", json["field"]
      api_like("demo-item-1", kind: "student_answer")
      assert_response :not_found
      assert_equal "kind", json["field"]
      api_like(ANSWER_WORD)
      assert_response :not_found
    end
    api_like("demo-item-1")
    assert_response :not_found
    assert_equal "E-NOT-FOUND", json["code"]
    assert_equal "like", json["field"]
  end

  test "like says so when the object has no vector yet" do
    Search::Embedder.using(Search::Embedder::Stub.new) do
      api_like("demo-item-1")
      assert_response :success
      assert_equal false, json["semantic"]
      assert_empty json["results"]
      assert_match(/no vectors/, json["note"])
    end
  end

  def api_like(ref, extra = {})
    on(:api, "/api/v1/search?#{{ like: ref }.merge(extra).to_query}", headers: { "Authorization" => "Bearer #{@token}" })
    response
  end
end
