# frozen_string_literal: true

module Lessons
  module Blocks
    # The semantic checks of the blocks of the docs family (WAVE2 2.7, 2.10; track T8): `source` (the legal half), `reveal` and `oral`.
    # The schema (b_source, b_reveal, b_oral) has made the shape right; these are the rules it cannot hold: quotations that are exact
    # substrings of an imported reference text (E-QUOTE-REF), a plain version beside every legal part on a core card, word counts, exactly
    # one real option, an outline whose key is a permutation of its ids.
    module Docs
      # Fields of a written source (the historical half, W2-2) that a legal source does not have.
      HISTORICAL_ONLY = %w[author_it year about_year for_whom_it where_it translation original compare].freeze

      module_function

      def check(block, ctx)
        case block["type"]
        when "source" then source(block, ctx)
        when "reveal" then reveal(block, ctx)
        when "oral" then oral(block, ctx)
        end
      end

      def rule(type, key) = Validation::Rules.get(:lesson2, :types, type.to_sym, key.to_sym)

      def words(text) = Blocks.words(text)

      def squish(text) = text.to_s.gsub(/\s+/, " ").strip

      # ---- source (legal) ---------------------------------------------------------------------------------

      def source(block, ctx)
        return unless block["kind"] == "legal" # the other kinds are the historical half (W2-2, draft): the reserved dry run checks the schema only

        HISTORICAL_ONLY.each do |key|
          ctx.error(key, "#{key} belongs to a written source: a legal source has the law's own words and a plain version") if block.key?(key)
        end
        quotations(block, ctx)
        plain_versions(block, ctx)
        parts = block["parts"].to_a
        max = rule(:source, :part_words)
        parts.each_with_index do |part, i|
          n = words(part["text_it"])
          ctx.error("parts/#{i}/text_it", "a part quotes #{n} words (at most #{max}): quote less, or split the article over two cards", rule: "part-words-#{i}") if n > max
          marks(part, i, ctx)
        end
        guide(block, parts, ctx)
      end

      # Every part's text is an exact substring of the imported reference text (E-QUOTE-REF).
      def quotations(block, ctx)
        ref = block["ref"]
        if ref.nil?
          ctx.error("ref", "a legal source names the imported reference text it quotes (ref)", rule: "ref-missing")
          return
        end
        body = ctx.reference_body(ref)
        if body.nil?
          ctx.add("E-QUOTE-REF", "ref", "#{ref.inspect} is not an imported reference text", rule: "ref")
          return
        end
        haystack = squish(body)
        block["parts"].to_a.each_with_index do |part, i|
          ctx.add("E-QUOTE-REF", "parts/#{i}/text_it", "the quotation is not an exact substring of the reference text", rule: "quote-#{i}") unless haystack.include?(squish(part["text_it"]))
        end
      end

      # On a core card every part has its plain version, in at most the words of the part's cap; a source without any is a quotation alone.
      def plain_versions(block, ctx)
        parts = block["parts"].to_a
        have = parts.map { |p| p["plain_it"] }
        max = rule(:source, :part_words)
        if ctx.card_level == "core" && have.any?(&:nil?)
          at = have.index(nil)
          ctx.error("parts/#{at}/plain_it", "on a core card every part has its plain version (plain_it): the plain words come first, the law's words behind them", rule: "plain-missing")
        elsif have.any? && have.any?(&:nil?)
          ctx.error("parts/#{have.index(nil)}/plain_it", "either every part has a plain version or none", rule: "plain-partial")
        end
        have.each_with_index do |t, i|
          next unless t

          n = words(t)
          ctx.error("parts/#{i}/plain_it", "a plain version has #{n} words (at most #{max})", rule: "plain-words-#{i}") if n > max
        end
      end

      def marks(part, i, ctx)
        seen = {}
        part["marks"].to_a.each_with_index do |m, k|
          ctx.role("parts/#{i}/marks/#{k}/role", m["role"])
          ctx.error("parts/#{i}/marks/#{k}/text_it", "a mark is an exact piece of the part's text: #{m['text_it'].inspect}", rule: "mark-#{i}-#{k}") unless part["text_it"].include?(m["text_it"])
          ctx.error("parts/#{i}/marks/#{k}/text_it", "the same words are marked twice in this part", rule: "mark-twice-#{i}-#{k}") if seen[m["text_it"]]
          seen[m["text_it"]] = true
        end
      end

      def guide(block, parts, ctx)
        block["guide"].to_a.each_with_index do |g, i|
          next if parts.any? { |p| p["text_it"].include?(g["span_it"]) }

          ctx.error("guide/#{i}/span_it", "a guided span is an exact piece of one part's text: #{g['span_it'].inspect}", rule: "guide-#{i}")
        end
      end

      # ---- reveal -----------------------------------------------------------------------------------------

      def reveal(block, ctx)
        options = block["options"]
        answer_max = rule(:reveal, :answer_words)
        if options
          crossroads(block, options, ctx, answer_max)
        else
          %w[year who_it situation_it real_it].each { |k| ctx.error(k, "#{k} belongs to a reveal with options", rule: "plain-#{k}") if block.key?(k) }
          n = words(block["answer_it"])
          ctx.error("answer_it", "the answer has #{n} words (at most #{answer_max})", rule: "answer-words") if n > answer_max
        end
      end

      def crossroads(block, options, ctx, answer_max)
        %w[prompt_it answer_it].each { |k| ctx.error(k, "a reveal with options has situation_it and real_it, not #{k}", rule: "mixed-#{k}") if block.key?(k) }
        ids = options.map { |o| o["id"] }
        ctx.error("options", "option ids must be unique", rule: "option-ids") if ids.uniq.size != ids.size
        real = options.count { |o| o["real"] }
        ctx.error("options", "exactly one option is the real one (real: true), here #{real}", rule: "real-count") unless real == 1
        then_max = rule(:reveal, :option_then_words)
        options.each_with_index do |o, i|
          n = words(o["then_it"])
          ctx.error("options/#{i}/then_it", "what comes next has #{n} words (at most #{then_max})", rule: "then-words-#{i}") if n > then_max
        end
        n = words(block["real_it"])
        ctx.error("real_it", "what really happened has #{n} words (at most #{answer_max})", rule: "real-words") if n > answer_max
      end

      # ---- oral -------------------------------------------------------------------------------------------

      def oral(block, ctx)
        ids = block["outline"].to_a.map { |o| o["id"] }
        ctx.error("outline", "outline ids must be unique", rule: "outline-ids") if ids.uniq.size != ids.size
        answer = block["answer"].to_a
        unless answer.sort == ids.sort
          ctx.error("answer", "the answer is the outline ids in order: every outline element once (#{ids.join(', ')}), here #{answer.join(', ')}", rule: "answer-permutation")
        end
        block["errors"].to_a.each_with_index do |e, i|
          value = e["answer"]
          if !value.is_a?(Array) || value.sort != ids.sort
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer is a different order of the same outline elements")
          elsif value == answer
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer")
          end
          ctx.catalogue_code("errors/#{i}/code", e["code"])
        end
        max = rule(:oral, :model_words)
        n = words(block["model_it"])
        ctx.error("model_it", "the model answer has #{n} words (at most #{max})", rule: "model-words") if n > max
      end
    end
  end
end
