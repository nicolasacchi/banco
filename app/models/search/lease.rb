module Search
  # One embedder at a time (D-315): the embed jobs, the rebuild task, a second worker process. A row of search_meta holds
  # "EXPIRES TOKEN"; taking it is one statement (SQLite writes one at a time), so two takers can never both hold it. The holder
  # renews it before each batch and gives it back at the end; one that died leaves it for +ttl+ seconds at most.
  #
  #   lease = Search::Lease.take(ttl: 120)   # => a Lease, or nil when another embedder holds it
  #   lease.renew(120)                       # => false when it was lost (expired and taken by another)
  #   lease.release
  class Lease
    KEY = "embed_lease".freeze

    # +wait+: seconds to keep trying (the rebuild task waits for a job to finish its share; a job never waits).
    def self.take(ttl:, wait: 0, poll: 5, clock: -> { Time.now.to_f }, sleeper: Kernel.method(:sleep))
      Schema.ensure!
      token = SecureRandom.hex(8)
      give_up = clock.call + wait
      loop do
        now = clock.call
        value = stamp(now + ttl, token)
        Index.write("INSERT INTO search_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value " \
                    "WHERE CAST(search_meta.value AS REAL) < ?", KEY, value, now)
        return new(token, value, clock) if Index.meta(KEY) == value
        return nil if clock.call + poll > give_up

        sleeper.call(poll)
      end
    end

    # Who holds it and until when: {expires_at:, token:} or nil.
    def self.holder
      value = Index.meta(KEY) or return nil
      expires, token = value.split(" ", 2)
      { expires_at: Time.at(expires.to_f), token: token }
    end

    def self.stamp(expires, token) = format("%.3f %s", expires, token)

    attr_reader :token

    def initialize(token, value, clock)
      @token = token
      @value = value
      @clock = clock
    end

    def renew(ttl)
      value = self.class.stamp(@clock.call + ttl, token)
      Index.write("UPDATE search_meta SET value = ? WHERE key = ? AND value = ?", value, KEY, @value)
      held = Index.meta(KEY) == value
      @value = value if held
      held
    end

    def release
      Index.write("DELETE FROM search_meta WHERE key = ? AND value = ?", KEY, @value)
    end
  end
end
