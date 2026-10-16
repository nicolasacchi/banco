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
      MAX_CHARS = 2000         # nothing longer than this is ever sent (the server truncates at its own token limit)
      DOCUMENT_CHARS = 1500    # a document is embedded by its title and the start of its body: BANCO_EMBED_MAX_CHARS (D-303)

      attr_reader :url, :base_model, :dimension, :max_chars
      attr_writer :document_timeout

      def initialize(url:, model: ENV["BANCO_EMBED_MODEL"].presence || DEFAULT_MODEL, max_chars: nil, document_timeout: nil)
        @url = url.to_s.chomp("/")
        @base_model = model
        @max_chars = Integer(max_chars || ENV["BANCO_EMBED_MAX_CHARS"].presence || DOCUMENT_CHARS).clamp(50, MAX_CHARS)
        @document_timeout = document_timeout
        @dimension = nil # known after the first answer
      end

      # What is recorded with a vector: the model and the cap, so a change of either makes the vectors stale (D-303).
      def model = "#{base_model} cap#{max_chars}"

      def document_timeout = @document_timeout || DOCUMENT_TIMEOUT

      # The text cut to +max_chars+ on a word boundary.
      def cap(text)
        text = text.to_s
        return text if text.size <= max_chars

        cut = text.first(max_chars)
        cut = cut.sub(/\s+\S*\z/, "") unless text[max_chars].match?(/\s/) || !cut.match?(/\s/)
        cut
      end

      def min_similarity = 0.5

      def embed_query(text) = post([ text ], QUERY_TIMEOUT).first

      def embed_documents(texts)
        texts.map { |t| cap(t) }.each_slice(BATCH).flat_map { |batch| post(batch, document_timeout) }
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
