module Search
  module Embedder
    # A deterministic embedder for tests, development and CI (config.x.search.embedder = :stub): the vector of a text is built from
    # a hash of its normalized words (the Snowball stem of each), so texts that share words are near and a near-duplicate is very
    # near. +synonyms+ maps a word to the word it stands for ("automobile" => "auto"), which lets a test show a paraphrase that
    # shares no word with its original. No network, no state.
    class Stub
      DIMENSION = 1024

      attr_reader :model, :dimension, :synonyms

      def initialize(synonyms: {}, dimension: DIMENSION, model: "stub-hash")
        @synonyms = synonyms.to_h { |k, v| [ Text.fold(k), Text.fold(v) ] }
        @dimension = dimension
        @model = model
      end

      def min_similarity = 0.3

      def embed_query(text) = vector(text)

      def embed_documents(texts) = texts.map { |t| vector(t) }

      def vector(text)
        v = Array.new(dimension, 0.0)
        Text.tokens(text).each do |word|
          next if Text::STOPWORDS.include?(word)

          folded = Text.fold(word)
          concept = synonyms.fetch(folded, folded)
          bucket, sign = Digest::SHA256.digest(Text.stem(concept, "it")).unpack("NN")
          v[bucket % dimension] += sign.odd? ? 1.0 : -1.0
        end
        Vectors.normalize(v)
      end
    end
  end
end
