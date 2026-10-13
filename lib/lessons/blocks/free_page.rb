# frozen_string_literal: true

module Lessons
  module Blocks
    # The `page` block (release 2, D-281, SPEC B4): a pin of a free page revision. The pinned revision must exist, belong to the
    # lesson's subject and have passed validation (E-LESSON-FREEPAGE); `latest` is resolved to an integer here and stored as it is,
    # like a topic pin. At most lesson2.page.max per lesson, never in a core card in this round, never the only visual of a card
    # (the card also has a still visual, so print, no WebGL and a refusal to click lose nothing essential).
    module FreePage
      module_function

      def check(block, ctx, card:, body:)
        rule = Validation::Rules.get(:page, :max_pages_per_lesson)
        if card["level"] != "extra"
          ctx.add("E-LESSON-FREEPAGE", "", "a free page goes in an extra card in this release, not in a core card", rule: "level-#{ctx.path}")
        end
        total = Pages::Embeds.of(body).size
        ctx.add("E-LESSON-FREEPAGE", "", "the lesson holds #{total} free pages (at most #{rule})", rule: "max") if total > rule && block["n"] && first_beyond?(block, card, body, rule)
        other_visual = card["blocks"].any? { |b| b != block && Blocks.visual?(b) && b["type"] != "page" }
        ctx.add("E-LESSON-FREEPAGE", "", "the card needs a still visual beside the page (a diagram, a schema or a procedure): the page is never the only place an idea is taught", rule: "still-#{ctx.path}") unless other_visual
        found = ctx.page(block["page"], block["revision"])
        return if found.nil? # a server without pages: only the shape is checked

        if found[:problem]
          ctx.add("E-LESSON-FREEPAGE", "revision", found[:problem], rule: "pin-#{ctx.path}")
          return
        end
        block["revision"] = found[:revision_id] if block["revision"] == "latest"
        leak(block, ctx, found[:strings], body)
        repeat(block, ctx, found[:instructions])
      end

      # W-PAGE-REPEAT: the caption and the page's instructions share most of their words (the card would say it twice).
      def repeat(block, ctx, instructions)
        a = words(block["caption_it"])
        b = words(instructions)
        return if a.size < 3 || b.size < 3

        ctx.add("W-PAGE-REPEAT", "caption_it", "the caption and the page's instructions say nearly the same thing: say it once", rule: "repeat-#{ctx.path}") if (a & b).size >= 0.5 * [ a.size, b.size ].min
      end

      def words(text) = text.to_s.downcase.scan(/[[:alpha:]]{3,}/).uniq

      # Only the pages beyond the limit are reported, each once.
      def first_beyond?(block, card, body, limit)
        Pages::Embeds.of(body).drop(limit).any? { |e| e[:card] == card["n"] && e[:block] == block["n"] }
      end

      # W-PAGE-KEY: a string of the page equal to a final of the lesson's try exercises (the page is never a place to find a key).
      def leak(block, ctx, strings, body)
        finals = body["cards"].flat_map { |c| c["blocks"] }.select { |b| b["type"] == "try" }.flat_map { |b| b["exercises"].to_a.filter_map { |e| e["final_it"] } }.map { |t| norm(t) }.reject(&:empty?)
        hit = strings.find { |s| finals.include?(norm(s)) }
        ctx.add("W-PAGE-KEY", "page", "a string of the page (#{hit.to_s.first(30).inspect}) equals the final of a Prova tu exercise", rule: "key-#{ctx.path}") if hit
      end

      def norm(text) = text.to_s.downcase.gsub(/\s+/, "").delete("$")
    end
  end
end
