module Search
  # The one place where the lists of candidates become the order of the answer:
  #
  #   key       the documents whose key is the question: always first
  #   lexical   Search::Engine's tiers (every word, then any word, then the corrected words), each by bm25 with the title weighted
  #   semantic  (staff and agents only, service answering) the cosine list
  #
  # With a semantic list the lexical and the semantic lists are fused by reciprocal rank fusion, score = sum of 1 / (K + rank) over
  # the lists a document is in (K = 60, ranks from 1), after the key hits. The student's door never has a semantic list, so it never
  # reaches that code.
  module Ranker
    K = 60

    module_function

    # lists: {key: [Hit], lexical: [Hit], semantic: [Hit] (optional)}; returns at most +limit+ hits, one per document.
    def fuse(lists, limit:)
      ordered = lists.fetch(:key, []) + body(lists)
      ordered.uniq(&:id).first(limit)
    end

    def body(lists)
      lexical = lists.fetch(:lexical, [])
      semantic = lists[:semantic]
      semantic ? rrf(lexical, semantic) : lexical
    end

    # Reciprocal rank fusion. A document found by both lists keeps its lexical hit (and its snippet words); ties keep the lexical order.
    def rrf(*lists)
      scores = Hash.new(0.0)
      first = {}
      lists.each do |list|
        list.uniq(&:id).each_with_index do |hit, i|
          scores[hit.id] += 1.0 / (K + i + 1)
          first[hit.id] ||= [ first.size, hit ]
        end
      end
      first.values.sort_by { |position, hit| [ -scores[hit.id], position ] }.map(&:last)
    end
  end
end
