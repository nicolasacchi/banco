require "net/http"

module Search
  module Embedder
    # Hugging Face text-embeddings-inference (production: BAAI/bge-m3, 1024 dimensions, normalized): POST /embed {"inputs": [...]}
    # answers one vector per input. No query/passage prefixes (bge-m3 takes none); the server truncates long inputs (--auto-truncate).
    # The server caps a request at 8 inputs and 4096 tokens, so documents go in batches of BATCH. No retries: a failure raises
    # Unavailable and the caller (the request path, the index job) decides what to do.
    class Http
      BATCH = 8
      QUERY_TIMEOUT = 3.0      # seconds; a question is about 0.17 s on the production service
      DOCUMENT_TIMEOUT = 60.0  # a batch of 8 passages
      MAX_CHARS = 2000         # a passage is cut here before it is sent (the server truncates at its own token limit)

      attr_reader :url, :model, :dimension

      def initialize(url:, model: ENV["BANCO_EMBED_MODEL"].presence || DEFAULT_MODEL)
        @url = url.to_s.chomp("/")
        @model = model
        @dimension = nil # known after the first answer
      end

      def min_similarity = 0.5

      def embed_query(text) = post([ text ], QUERY_TIMEOUT).first

      def embed_documents(texts)
        texts.each_slice(BATCH).flat_map { |batch| post(batch, DOCUMENT_TIMEOUT) }
      end

      private

      def post(texts, timeout)
        uri = URI.parse("#{url}/embed")
        request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
        request.body = JSON.generate(inputs: texts.map { |t| t.to_s.first(MAX_CHARS).presence || " " })
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: [ timeout, 2.0 ].min,
                                   read_timeout: timeout, write_timeout: timeout) { |http| http.request(request) }
        raise Unavailable, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        vectors = JSON.parse(response.body)
        unless vectors.is_a?(Array) && vectors.size == texts.size && vectors.all? { |v| v.is_a?(Array) && v.any? && v.all?(Numeric) }
          raise Unavailable, "unexpected answer"
        end

        vectors.map { |v| Vectors.normalize(v.map(&:to_f)) }.tap { |all| @dimension = all.first.size }
      rescue Timeout::Error, SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, JSON::ParserError, URI::InvalidURIError => e
        raise Unavailable, e.class.name
      end
    end
  end
end
