require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/search_world"

# The student's search (D-299), written as attacks: through the student's door try to reach an entry-test item, an answer key, a
# solution, a hint, an error catalogue, a draft, another course and anybody's answers. Every sentinel word below lives in the
# primary database; the index is rebuilt once and the door still must not return it.
class SearchStudentDoorTest < ActionDispatch::IntegrationTest
  include MultiUser
  include SearchWorld

  NEVER = (SearchWorld::LEAKS.values + [ SearchWorld::DIAGNOSIS_WORD, SearchWorld::ORPHAN_WORD, SearchWorld::ANSWER_WORD, SearchWorld::TRIAL_ANSWER_WORD,
                                          SearchWorld::REFUSED_WORD, SearchWorld::DIAGNOSIS_ANSWER_WORD, "27182", "31415" ]).freeze

  setup do
    build_search_world
    add_draft_revision!
    add_orphan_lesson!
    add_other_course!
    add_answers!(@official, ANSWER_WORD, refused: REFUSED_WORD)
    add_answers!(@trial_student, TRIAL_ANSWER_WORD)
    rebuild_search!
  end

  def search(headers, query, extra = "")
    on(:web, "/search?q=#{CGI.escape(query)}#{extra}", headers: headers, remote_addr: EDGE)
    response
  end

  def hits = css_select(".search-hit")

  def hit_kinds = hits.map { |h| h.ancestors(".search-group").first["data-kind"] }.uniq

  test "the student finds topics, lesson sections, exercises and their lines" do
    search(OFFICIAL, "equazione")
    assert_response :success
    assert_includes hit_kinds, "topic"
    assert_includes hit_kinds, "lesson_card"
    assert_includes css_select("a.search-title").map { |a| a["href"] }, "/topics/#{TOPIC}"
    search(OFFICIAL, "radice quadrata")
    assert_equal [ "practice_item" ], hit_kinds
    assert_equal [ "/topics/#{TOPIC}/practice/#{SKILL}" ], css_select("a.search-title").map { |a| a["href"] }.uniq, "an exercise leads to the practice page, never to an instance"
  end

  test "an exercise shows its stem and nothing else of it" do
    search(OFFICIAL, "radice quadrata")
    text = response.body
    LEAKS.each_value { |word| assert_not_includes text, word }
  end

  test "no entry-test item, key, solution, hint, error catalogue, answer or other student's text can be reached" do
    NEVER.each do |word|
      [ OFFICIAL, TRIAL ].each do |login|
        search(login, word)
        assert_response :success
        assert_empty hits, "#{word} reached #{login['Remote-User']}"
        assert_select "#search-empty"
      end
    end
  end

  test "the kinds and students of the url are not options of this door" do
    [ "kind=student_answer", "kind=item", "student=prova-1", "subject=italian", "tab=answers" ].each do |extra|
      search(OFFICIAL, ANSWER_WORD, "&#{extra}")
      assert_empty hits, extra
    end
  end

  test "an entry-test item pinned by mistake in an approved topic is still not an exercise" do
    topic = Course::StudentView.new(@official).find_topic(TOPIC).last.topic_revision
    assert_includes topic.body["practice"].flat_map { |p| p["items"].map { |i| i["revision"] } }, @pinned_diagnosis.id
    assert_not_includes Search::Scope::Student.for(@official).practice_targets.keys, @pinned_diagnosis.id
    assert_equal 0, Search::Document.where(kind: "practice_item", key: @pinned_diagnosis.item.key).count
    search(OFFICIAL, "diag")
    assert_empty hits
  end

  test "a draft is the trial student's, not the official student's" do
    search(OFFICIAL, DRAFT_WORD)
    assert_empty hits
    search(TRIAL, DRAFT_WORD)
    assert_includes hit_kinds, "lesson_card"
  end

  test "what the official student sees is the approved revision, not the newest one" do
    search(OFFICIAL, "bilancia")
    assert_includes hit_kinds, "lesson_card"
    search(TRIAL, "bilancia")
    assert_empty hits, "the trial student's lesson is the newest revision of the topic, which has no scale"
  end

  test "a lesson in no topic and a course that is not open are not found" do
    search(OFFICIAL, ORPHAN_WORD)
    assert_empty hits
    search(TRIAL, ORPHAN_WORD)
    assert_empty hits
    search(OFFICIAL, OTHER_WORD)
    assert_empty hits
  end

  test "the trial student's catalog follows the same rule as the pages: the other course is theirs" do
    assert Course::StudentView.new(@trial_student).find_topic("lezione.italian.altro")
    search(TRIAL, OTHER_WORD)
    assert_includes hit_kinds, "lesson_card"
  end

  test "withdrawing the release closes the door at once, with no new index" do
    search(OFFICIAL, "equazione")
    assert_predicate hits, :any?
    release_course!(@course, open: false)
    search(OFFICIAL, "equazione")
    assert_empty hits
  end

  test "the teacher, a guest and an unconfigured student are refused" do
    [ TEACHER, GUEST, UNMAPPED ].each do |login|
      search(login, "equazione")
      assert_response :forbidden, login["Remote-User"]
    end
    on(:web, "/search?q=equazione", headers: OFFICIAL, remote_addr: "127.0.0.1")
    assert_response :forbidden, "only the trusted edge can say who is asking"
  end

  test "the search never reaches an embedding client" do
    raising = Object.new
    %i[embed_query embed_documents model dimension min_similarity].each { |m| raising.define_singleton_method(m) { |*| raise "the student's door asked the embedding client" } }
    Search::Embedder.using(raising) do
      search(OFFICIAL, "equazione")
      assert_response :success
      assert_predicate hits, :any?
      assert_not Search::Scope::Student.for(@official).semantic?
      assert_not Search::Scope::Student.new(@official).semantic?
      assert_equal false, Search::Engine.new(scope: Search::Scope::Student.for(@official)).call("equazione").semantic
    end
  end

  test "the search makes no HTTP call at all when the embedding service is set up" do
    calls = []
    trap = ->(*args, **) { calls << args.first(2) && raise("no network for the student") }
    previous = ENV["BANCO_EMBED_URL"]
    ENV["BANCO_EMBED_URL"] = "http://banco-embed:80"
    Net::HTTP.stub(:start, trap) do
      Net::HTTP.stub(:new, trap) do
        assert Search::Embedder.configured?, "the service is configured, so the trap below is armed for the staff"
        search(OFFICIAL, "equazione")
        assert_response :success
        assert_predicate hits, :any?
        search(OFFICIAL, "equazone")
        assert_predicate hits, :any?
        assert_empty calls, "the student's door touched the network"
        assert_equal false, Search::Engine.new(scope: Search::Scope::Student.for(@official)).call("equazione").semantic
        assert_empty calls
        Search::Engine.new(scope: Search::Scope::Agent.new).call("equazione")
        assert_equal 1, calls.size, "the agents' door would have called the service: the trap works"
      end
    end
  ensure
    previous ? ENV["BANCO_EMBED_URL"] = previous : ENV.delete("BANCO_EMBED_URL")
    Search::Embedder.reset!
  end

  test "the words are not in the request log" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(logger)
    search(OFFICIAL, "qzxwvutsrq")
    Rails.logger.stop_broadcasting_to(logger)
    assert_includes io.string, "/search"
    assert_not_includes io.string, "qzxwvutsrq"
    assert_includes io.string, "[FILTERED]"
  end

  test "the words are not stored in any table, event or cache" do
    events = [ AppEvent.count, PracticeEvent.count, StudentQuestion.count, DiagnosisEvent.count ]
    search(OFFICIAL, "qzxwvutsrq")
    search(TRIAL, "qzxwvutsrq")
    assert_equal events, [ AppEvent.count, PracticeEvent.count, StudentQuestion.count, DiagnosisEvent.count ]
    [ ActiveRecord::Base.connection, Search::Record.connection ].each do |connection|
      tables = connection.select_values("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
      tables.each do |table|
        connection.select_rows("SELECT * FROM #{connection.quote_table_name(table)}").flatten.each do |cell|
          assert_not cell.to_s.b.include?("qzxwvutsrq".b), "the words are in #{table}"
        end
      end
    end
    assert_nil Rails.cache.read("search:qzxwvutsrq")
    assert_empty response.headers["Set-Cookie"].to_s.scan("qzxwvutsrq")
  end

  test "the page is not kept by the browser and does not tell where the words came from" do
    search(OFFICIAL, "equazione")
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "the menu has Cerca, and the sitting and the teacher's preview do not" do
    on(:web, "/subjects", headers: OFFICIAL, remote_addr: EDGE)
    assert_select "#menu-search[href='/search']", text: "Cerca"
    on(:web, "/search", headers: OFFICIAL, remote_addr: EDGE)
    assert_select "#menu-search[aria-current='page']"
    on(:web, "/teacher/preview", headers: TEACHER, remote_addr: EDGE)
    assert_select "#menu-search", count: 0
    assert_select "#student-menu", count: 0
  end

  test "an empty box and a word nothing matches say so kindly" do
    search(OFFICIAL, "")
    assert_select "#search-hint"
    search(OFFICIAL, "qzxwvutsrq")
    assert_select "#search-empty", text: /Non ho trovato niente/
  end

  test "typing a word wrongly, without the accent or in the plural still finds it" do
    search(OFFICIAL, "equazone")
    assert_predicate hits, :any?
    search(OFFICIAL, "equazioni")
    assert_predicate hits, :any?
    assert_select "#search-did-you-mean", count: 0
    search(OFFICIAL, "perche")
    assert_predicate hits, :any?
  end

  test "when only the corrected words found something, the page says what it understood, with links that run the search" do
    search(OFFICIAL, "equazone")
    assert_select "#search-did-you-mean", text: /Non ho trovato «equazone»\. Forse cercavi «equazione»/
    assert_includes css_select("#search-did-you-mean a").map { |a| a["href"] }, "/search?q=equazione"
    search(OFFICIAL, "equazione")
    assert_select "#search-did-you-mean", count: 0
  end
end
