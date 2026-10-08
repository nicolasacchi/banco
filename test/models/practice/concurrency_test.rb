require "test_helper"
require "tmpdir"
require_relative "../../support/practice_world"

# Serve creation and answers under real concurrency (A8.4). The ledger tables refuse DELETE, so these
# tests run against a scratch database file loaded from db/structure.sql and drop it afterwards.
class PracticeConcurrencyTest < ActiveSupport::TestCase
  include PracticeWorld

  self.use_transactional_tests = false

  THREADS = 6

  setup do
    @original_config = ActiveRecord::Base.connection_db_config
    @dir = Dir.mktmpdir("banco-practice")
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: File.join(@dir, "scratch.sqlite3"), timeout: 10_000, max_connections: THREADS + 4)
    ActiveRecord::Base.connection.raw_connection.execute_batch(Rails.root.join("db/structure.sql").read)
    build_practice_world(items: 2, instances: 12)
  end

  teardown do
    ActiveRecord::Base.connection_pool.disconnect!
    ActiveRecord::Base.establish_connection(@original_config)
    FileUtils.remove_entry(@dir)
  end

  # Runs the block in THREADS threads released at the same moment; returns their results.
  def together(count = THREADS)
    ready = Queue.new
    go = Queue.new
    threads = Array.new(count) do |n|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop
          yield n
        end
      end
    end
    count.times { ready.pop }
    count.times { go << true }
    threads.map(&:value)
  end

  test "the scratch database has the triggers of the ledger" do
    c = serve!
    assert_raises(ActiveRecord::StatementInvalid) { PracticeServe.where(id: c.serve.id).delete_all }
  end

  test "concurrent requests for a serve get the same open serve and burn one instance" do
    results = together { |_| serve! }
    assert_equal 1, results.map { |r| r.serve.id }.uniq.size
    assert_equal 1, PracticeServe.count
    assert_equal 1, results.count(&:created)
  end

  test "the same under repeated rounds: after each answer exactly one new serve" do
    4.times do |round|
      serves = together { |_| serve! }.map { |r| r.serve.id }.uniq
      assert_equal 1, serves.size, "round #{round}"
      c = PracticeServe.find(serves.first)
      answer!(c, JSON.parse(c.item_instance.answer_json).to_s)
    end
    assert_equal 4, PracticeServe.count
    assert_equal 4, PracticeServe.distinct.count(:item_instance_id)
  end

  test "concurrent Prova questo requests create one serve" do
    first = serve!
    answer!(first, slip_raw(first))
    results = together { |_| serve!(follow: { serve_id: first.serve.id, kind: "prova_questo" }) }
    assert_equal 1, results.map { |r| r.serve.id }.uniq.size
    assert_equal 2, PracticeServe.count
    assert_equal "prova_questo", results.first.reason
  end

  test "concurrent duplicates of one answer write one attempt and all get the answer" do
    c = serve!
    raw = JSON.parse(c.instance.answer_json).to_s
    results = together { |_| recorder.call(serve_id: c.serve.id, client_attempt_id: "same-client-id-1", raw: raw, source: "text") }
    assert_equal 1, PracticeAttempt.count
    assert_equal 1, PracticeGrading.count
    assert(results.all? { |r| r.http == 200 && r.body[:outcome] == "correct" }, results.map(&:body).inspect)
    assert_equal 1, PracticeEvent.where(kind: "solution_shown").count
  end

  test "concurrent different answers to one serve: at most three tries, unique numbers, the rest are 409" do
    c = serve!
    results = together { |n| recorder.call(serve_id: c.serve.id, client_attempt_id: "client-#{n}-xxxxxx", raw: "9999#{n}", source: "text") }
    tries = PracticeAttempt.where(practice_serve_id: c.serve.id).order(:try_number).pluck(:try_number)
    assert_operator tries.size, :<=, 3
    assert_equal (1..tries.size).to_a, tries
    assert_equal tries.size, results.count { |r| r.http == 200 }
    assert_equal THREADS - tries.size, results.count { |r| r.http == 409 }
    status = Practice::Loader.status_of(c.serve.reload, now: @clock.now)
    assert_equal :closed, status.state if tries.size > 1
  end

  test "an answer and a solution request at once never leave a try after the solution" do
    c = serve!
    ready = together(2) do |n|
      n.zero? ? recorder.call(serve_id: c.serve.id, client_attempt_id: "race-answer-01", raw: JSON.parse(c.instance.answer_json).to_s, source: "text")
              : actions.solution(serve_id: c.serve.id)
    end
    assert(ready.all? { |r| [ 200, 409 ].include?(r.http) })
    serve = PracticeServe.find(c.serve.id)
    status = Practice::Loader.status_of(serve, now: @clock.now)
    assert_equal :closed, status.state
    assert_operator serve.attempts.count, :<=, 1
  end
end
