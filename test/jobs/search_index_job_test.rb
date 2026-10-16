require "test_helper"
require "rake"
require_relative "../support/search_world"

# Keeping the index fresh: SearchIndexJob rebuilds named groups, and the rows that change what is searchable enqueue it.
class SearchIndexJobTest < ActiveJob::TestCase
  include SearchWorld

  def with_index_on_write(value = true)
    saved = Rails.configuration.x.search.index_on_write
    Rails.configuration.x.search.index_on_write = value
    yield
  ensure
    Rails.configuration.x.search.index_on_write = saved
  end

  test "the job rebuilds the groups it is given, or all of them" do
    build_search_world
    SearchIndexJob.perform_now([ "references" ])
    assert_equal 1, Search::Document.where(kind: "reference_article").count
    assert_equal 0, Search::Document.where(kind: "topic").count
    SearchIndexJob.perform_now([ "all" ])
    assert_operator Search::Document.where(kind: "topic").count, :>, 0
    SearchIndexJob.perform_now(nil)
    SearchIndexJob.perform_now([ "nonsense" ])
  end

  test "after the lexical index the job embeds what has no vector; a service that is down leaves the index whole" do
    build_search_world
    SearchIndexJob.perform_now([ "all" ])
    assert_equal 0, Search::Vectors.status[:with_vectors], "no embedder is configured in the test environment"
    Search::Embedder.using(Search::Embedder::Stub.new) do
      SearchIndexJob.perform_now([ "all" ])
      status = Search::Vectors.status
      assert_operator status[:eligible], :>, 0
      assert_equal status[:eligible], status[:with_vectors]
    end
    Search::Index.write("DELETE FROM search_vectors")
    down = Search::Embedder::Stub.new
    down.define_singleton_method(:embed_documents) { |_| raise Search::Embedder::Unavailable, "down" }
    Search::Embedder.using(down) do
      assert_nothing_raised { SearchIndexJob.perform_now([ "all" ]) }
      assert_operator Search::Document.count, :>, 0
      assert_equal 0, Search::Vectors.status[:with_vectors]
    end
  end

  test "the rebuild task builds the lexical index first and says how many documents have vectors" do
    build_search_world
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:search:rebuild")
    out, = Search::Embedder.using(Search::Embedder::Stub.new) do
      capture_io { Rake::Task["banco:search:rebuild"].tap(&:reenable).invoke }
    end
    assert_match(/vectors: \d+ embedded/, out)
    out, = Search::Embedder.using(Search::Embedder::Stub.new) do
      capture_io { Rake::Task["banco:search:status"].tap(&:reenable).invoke }
    end
    assert_match(/vectors: (\d+) of \1 documents have a current vector \(0 missing\); model stub-hash/, out)
    out, = Search::Embedder.using(nil) do
      capture_io { Rake::Task["banco:search:rebuild"].tap(&:reenable).invoke }
    end
    assert_match(/no embedder configured/, out)
  end

  test "the tests do not enqueue on write, production does" do
    build_course
    assert_no_enqueued_jobs { make_lesson("ripasso.math.demo") }
    with_index_on_write do
      assert_enqueued_with(job: SearchIndexJob) { make_lesson("ripasso.math.other") }
    end
  end

  test "each model enqueues the groups it touches" do
    with_index_on_write do
      build_course
      clear_enqueued_jobs
      revision = nil
      assert_enqueued_with(job: SearchIndexJob, args: [ %w[lessons topics] ]) { revision = make_lesson("ripasso.math.demo") }
      assert_enqueued_with(job: SearchIndexJob, args: [ %w[items skills findings answers] ]) { make_practice_item("x-1", "math.linear-equation-integer", instances: 1) }
      assert_enqueued_with(job: SearchIndexJob, args: [ %w[references] ]) do
        ReferenceText.create!(key: "r-1", title: "t", source_url: "https://example.org", sha256: "4" * 64, body: "b")
      end
      assert_enqueued_with(job: SearchIndexJob, args: [ %w[lessons topics items skills] ]) do
        Decision.create!(kind: "approve_topic", subject: @subject, payload_json: JSON.generate(topic_revision_id: 1), request_id: "r-a", teacher_login: "t", remote_addr: "127.0.0.1")
      end
      assert_not_nil revision
    end
  end

  test "an event or a decision that changes nothing searchable enqueues nothing" do
    with_index_on_write do
      build_course
      student = practice_student
      clear_enqueued_jobs
      assert_no_enqueued_jobs do
        AppEvent.create!(kind: "warmup_completed", student: student)
        Decision.create!(kind: "consent", subject: @subject, payload_json: "{}", request_id: "r-b", teacher_login: "t", remote_addr: "127.0.0.1")
      end
      assert_enqueued_jobs 1 do
        AppEvent.create!(kind: "invalid_input", student: student, payload_json: JSON.generate(served_event_id: 1, text: "x"))
      end
    end
  end

  test "a failing queue never fails the write" do
    with_index_on_write do
      build_course
      SearchIndexJob.stub(:set, ->(*) { raise "queue down" }) do
        assert_nothing_raised { make_lesson("ripasso.math.demo") }
      end
    end
  end
end
