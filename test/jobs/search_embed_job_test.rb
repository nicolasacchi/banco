require "test_helper"

# The vectors of new documents (D-315): SearchEmbedJob embeds the newest first, a bounded share a run, goes on by itself while some are
# left, never runs beside another embedder, and asks a service that is down again later, a bounded number of times.
class SearchEmbedJobTest < ActiveJob::TestCase
  setup do
    @saved = Rails.configuration.x.search.index_on_write
    Rails.configuration.x.search.index_on_write = true
    Search::Index.replace_group("skills", Array.new(20) { |i| doc(i) })
    @stub = Search::Embedder::Stub.new
  end

  teardown do
    Rails.configuration.x.search.index_on_write = @saved
  end

  def doc(i, body: "testo numero #{i}") = Search::Doc.build(kind: "skill", key: "math.skill-#{i}", title: "Abilità #{i}", body: body, subject: "math", unique: i)

  def ids_with_vectors = Search::Index.rows("SELECT doc_id FROM search_vectors ORDER BY doc_id").flatten

  def all_ids = Search::Index.rows("SELECT id FROM search_documents ORDER BY id").flatten

  test "a run embeds a bounded share, the newest documents first, and enqueues the next one while some are left" do
    stub_const(SearchEmbedJob, :DOCUMENTS, 8) do
      Search::Embedder.using(@stub) do
        assert_enqueued_with(job: SearchEmbedJob) { SearchEmbedJob.perform_now }
        assert_equal all_ids.last(8), ids_with_vectors, "the newest eight"
        clear_enqueued_jobs
        SearchEmbedJob.perform_now
        SearchEmbedJob.perform_now
        assert_equal all_ids, ids_with_vectors
        assert_no_enqueued_jobs(only: SearchEmbedJob) { SearchEmbedJob.perform_now }
      end
    end
  end

  test "work written while a run embeds is picked up by the next run, which the run enqueues" do
    writer = Search::Embedder::Stub.new
    added = false
    writer.define_singleton_method(:embed_documents) do |texts|
      unless added
        added = true
        Search::Index.replace_group("references", [ Search::Doc.build(kind: "reference_article", key: "nuovo", title: "Nuovo", body: "scritto mentre", status: "imported") ])
      end
      super(texts)
    end
    Search::Embedder.using(writer) do
      assert_enqueued_with(job: SearchEmbedJob) { SearchEmbedJob.perform_now }
      perform_enqueued_jobs(only: SearchEmbedJob)
      assert_equal all_ids, ids_with_vectors
      assert_not Search::Vectors.pending?(writer)
    end
  end

  test "one embedder at a time: a run that finds the lease held returns at once, the holder goes on" do
    Search::Embedder.using(@stub) do
      lease = Search::Lease.take(ttl: 60)
      assert lease
      assert_no_enqueued_jobs { SearchEmbedJob.perform_now }
      assert_empty ids_with_vectors
      assert Search::Indexer.embed![:busy]
      lease.release
      SearchEmbedJob.perform_now
      assert_equal all_ids, ids_with_vectors
      assert_nil Search::Lease.holder, "the run gave the lease back"
    end
  end

  test "a lease left by a run that died lapses: the next run takes it" do
    Search::Embedder.using(@stub) do
      Search::Index.set_meta(Search::Lease::KEY, Search::Lease.stamp(Time.now.to_f - 1, "dead"))
      SearchEmbedJob.perform_now
      assert_equal all_ids, ids_with_vectors
    end
  end

  test "a service that is down is asked again later, a bounded number of times" do
    down = Search::Embedder::Stub.new
    down.define_singleton_method(:embed_documents) { |_| raise Search::Embedder::Unavailable, "down" }
    Search::Embedder.using(down) do
      assert_enqueued_with(job: SearchEmbedJob, args: [ 2 ]) { SearchEmbedJob.perform_now }
      assert_in_delta SearchEmbedJob::DOWN_WAIT.from_now.to_f, enqueued_jobs.last[:at].to_f, 5
      clear_enqueued_jobs
      assert_enqueued_with(job: SearchEmbedJob, args: [ 1 ]) { SearchEmbedJob.perform_now(2) }
      clear_enqueued_jobs
      assert_no_enqueued_jobs { SearchEmbedJob.perform_now(1) }
    end
    assert_nil Search::Lease.holder
  end

  test "a run that took documents and embedded none does not go round again; no embedder, no job" do
    Search::Embedder.using(@stub) do
      stuck = { embedded: 0, pending: 8, down: false, seconds: 0.0, configured: true, skipped: 0, lost: false }
      Search::Indexer.stub(:embed!, stuck) do
        assert_no_enqueued_jobs { SearchEmbedJob.perform_now }
      end
    end
    Search::Embedder.using(nil) do
      assert_no_enqueued_jobs { SearchEmbedJob.later }
      assert_no_enqueued_jobs { SearchEmbedJob.perform_now }
    end
    Rails.configuration.x.search.index_on_write = false
    Search::Embedder.using(@stub) { assert_no_enqueued_jobs { SearchEmbedJob.later } }
  end

  test "a run stops at its deadline and leaves the rest for the next" do
    slow = Search::Embedder::Stub.new
    clock = 0.0
    slow.define_singleton_method(:embed_documents) do |texts|
      clock += 100
      super(texts)
    end
    Process.stub(:clock_gettime, ->(*) { clock }) do
      Search::Embedder.using(slow) do
        assert_enqueued_with(job: SearchEmbedJob) { SearchEmbedJob.perform_now }
      end
    end
    assert_equal 16, ids_with_vectors.size, "two batches of eight: the third would start after #{SearchEmbedJob::SECONDS} s"
  end

  test "the job's queue comes after the ordinary jobs in the worker, which runs them in order" do
    assert_equal "search", SearchEmbedJob.new.queue_name
    workers = YAML.safe_load_file(Rails.root.join("config/queue.yml"), aliases: true).dig("production", "workers")
    assert_equal [ %w[default search] ], workers.map { |w| Array(w["queues"]) }.select { |q| q.include?("search") }
  end
end
