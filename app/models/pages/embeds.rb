# The page blocks of a lesson/2 body: which page revisions a lesson revision pins (SPEC B4).
module Pages
  module Embeds
    module_function

    # [{card:, block:, key:, revision:, caption_it:, level:}] in card order.
    def of(body)
      Array(body["cards"]).flat_map do |card|
        Array(card["blocks"]).filter_map do |block|
          next unless block["type"] == "page"

          { card: card["n"], block: block["n"], key: block["page"], revision: block["revision"], caption_it: block["caption_it"], level: card["level"] }
        end
      end
    end

    def revision_ids(body) = of(body).filter_map { |e| e[:revision].is_a?(Integer) ? e[:revision] : nil }
  end
end
