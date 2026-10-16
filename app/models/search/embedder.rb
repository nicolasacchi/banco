module Search
  # The embedding client of the content search (D-300). One place decides whether vectors are used at all:
  #
  #   Search::Embedder.current      # => Http (BANCO_EMBED_URL set), Stub (config.x.search.embedder = :stub) or nil
  #   Search::Embedder.configured?  # => true when there is one
  #
  # nil means the search is lexical only: the doors say `semantic: false` and nothing fails. The student's door never calls this
  # module (firm rule 1): Search::Scope::Student#semantic? is false and the engine asks for a vector only when the scope says so.
  #
  # A client answers `model`, `dimension` (nil until known), `min_similarity`, `embed_query(text)` (one vector, short timeout) and
  # `embed_documents(texts)` (one vector per text, longer timeout, small batches). Vectors are normalized arrays of Floats, so
  # a cosine is a dot product. A client that cannot answer raises Search::Embedder::Unavailable.
  module Embedder
    class Unavailable < StandardError; end

    DEFAULT_MODEL = "BAAI/bge-m3".freeze
    # How long the engine leaves a service alone after it failed, so that a hung service costs one timeout, not one per question.
    COOLDOWN = 30.0

    @forced = false
    @client = nil
    @down_until = 0.0
    @mutex = Mutex.new

    class << self
      def current
        return @client if @forced
        return nil if Rails.configuration.x.search.embedder == :none
        return (@stub ||= Stub.new) if Rails.configuration.x.search.embedder == :stub

        url = ENV["BANCO_EMBED_URL"].to_s.strip
        return nil if url.empty?

        @http = nil if @http && @http.url != url.chomp("/")
        @http ||= Http.new(url: url)
      end

      def configured? = !current.nil?

      # A similarity under this is not "like" the question (the cosines of bge-m3 start high, so the default is not small).
      def min_similarity
        (ENV["BANCO_EMBED_MIN_SIMILARITY"].presence || current&.min_similarity || 0.5).to_f
      end

      # Tests: use +client+ (or none, with nil) inside the block.
      def using(client)
        previous = [ @forced, @client ]
        @forced = true
        @client = client
        reset!
        yield
      ensure
        @forced, @client = previous
        reset!
      end

      # Embeds one question for the engine: nil (and a log line, never the question) when there is no service or it fails. After a
      # failure the service is left alone for COOLDOWN seconds.
      def query_vector(text)
        client = current or return nil
        return nil if now < @down_until

        client.embed_query(text)
      rescue Unavailable => e
        @mutex.synchronize { @down_until = now + COOLDOWN }
        Rails.logger.warn("search: the embedding service did not answer (#{e.message.first(120)}); lexical search only for #{COOLDOWN.to_i} s")
        nil
      end

      def reset!
        @mutex.synchronize { @down_until = 0.0 }
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
