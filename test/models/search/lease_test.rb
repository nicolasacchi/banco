require "test_helper"

# One embedder at a time (D-315): the lease in search_meta.
class SearchLeaseTest < ActiveSupport::TestCase
  setup { Search::Index.clear! }

  test "one holder at a time; given back, it can be taken again" do
    first = Search::Lease.take(ttl: 60)
    assert first
    assert_nil Search::Lease.take(ttl: 60)
    assert_equal first.token, Search::Lease.holder[:token]
    first.release
    assert_nil Search::Lease.holder
    second = Search::Lease.take(ttl: 60)
    assert second
    refute_equal first.token, second.token
  end

  test "a lease that is not renewed lapses and another takes it; the first then knows it lost it" do
    now = 1_000.0
    clock = -> { now }
    first = Search::Lease.take(ttl: 60, clock: clock)
    now += 30
    assert first.renew(60), "renewed in time"
    now += 59
    assert_nil Search::Lease.take(ttl: 60, clock: clock), "still held: the renewal moved the end"
    now += 2
    second = Search::Lease.take(ttl: 60, clock: clock)
    assert second
    assert_not first.renew(60)
    first.release
    assert_equal second.token, Search::Lease.holder[:token], "the one that lost it cannot give back the other's"
  end

  test "a taker may wait for the holder to finish" do
    now = 0.0
    held = Search::Lease.take(ttl: 3_600, clock: -> { now })
    sleeps = []
    sleeper = lambda do |seconds|
      sleeps << seconds
      held.release if sleeps.size == 3
      now += seconds
    end
    lease = Search::Lease.take(ttl: 60, wait: 600, poll: 5, clock: -> { now }, sleeper: sleeper)
    assert lease
    assert_equal [ 5, 5, 5 ], sleeps
    assert_nil Search::Lease.take(ttl: 60, wait: 12, poll: 5, clock: -> { now }, sleeper: ->(s) { now += s })
  end
end
