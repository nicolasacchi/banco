module Search
  # The one place where the lists of candidates become the order of the answer. S1 has two lists: the exact key hits (always
  # first) and the lexical hits, which Search::Engine already orders in tiers (every word, then any word, then the corrected
  # words), each by bm25 with the title weighted over the body.
  #
  # S2 extends this step, not the doors: a `semantic` list (cosine over the vectors of the staff's and agents' doors) is fused
  # with the lexical one by reciprocal rank fusion (k = 60) between the key hits and the rest; the student's door never has a
  # semantic list, so it never reaches that code.
  module Ranker
    module_function

    # lists: {key: [Hit], lexical: [Hit], (S2) semantic: [Hit]}; returns at most +limit+ hits, one per document.
    def fuse(lists, limit:)
      ordered = lists.fetch(:key, []) + body(lists)
      ordered.uniq(&:id).first(limit)
    end

    def body(lists) = lists.fetch(:lexical, [])
  end
end
