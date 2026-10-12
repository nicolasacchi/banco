# frozen_string_literal: true

module Lessons
  module Blocks
    # The truth rules of the checks (WAVE2 1.1, 1.4): `verify` (L9, E-LESSON-VERIFY), the select figure's neutrality (L3:
    # E-CHECK-ANSWER-IN-ALT, E-SELECT-MARKED), what a figure of the card prints (L4: W-CHECK-ANSWER-IN-DIAGRAM) and what its
    # controls can show (L5: E-CHECK-ANSWER-BY-SIMULATION, E-DIAGRAM-REACHABLE-CAP).
    #
    # The figure types give the facts through the hooks of Lessons::Diagrams::Contract: printed(data, state), reachable(data),
    # targets(data, set) and two optional ones this module reads when the type has them:
    #   target_names(data, set)       -> {stored id => name}   the words that name a target (what alt_it must not say, what the teacher reads)
    #   select_signatures(data, set)  -> {stored id => any}    the drawn style of each candidate; they must all be equal (L3)
    # A type that does not have a hook is skipped, never guessed.
    module Truth
      TEXT_ANSWER = %w[number fraction normalized_text amount_words].freeze

      module_function

      # ---- one check ----------------------------------------------------------------------------------

      def check(check, ctx)
        Verify.problems(check).each { |p| ctx.add("E-LESSON-VERIFY", p.path, p.message) }
      end

      # The select check's own figure: its alt text and caption must not name an answer target (L3), and the candidates must all be
      # drawn alike.
      def select_figure(check, ids, ctx)
        diagram = check["diagram"]
        mod = SelectTargets.module_of(check)
        answer = check["answer"].to_a.map(&:to_s)
        names = SelectTargets.names(check, answer)
        said = [ diagram["alt_it"], diagram["caption_it"] ].compact.join(" ")
        hit = names.find { |n| (f = fold(n)).size >= 3 && (f.include?(" ") ? fold(said).include?(f) : words(said).include?(f)) }
        ctx.add("E-CHECK-ANSWER-IN-ALT", "diagram/alt_it", "the alt text or caption of the figure names #{hit.inspect}, which is the answer") if hit
        return unless mod.is_a?(Diagrams::Contract) && mod.respond_to?(:select_signatures)

        signatures = mod.select_signatures(diagram, check["targets"]).values_at(*ids)
        ctx.add("E-SELECT-MARKED", "diagram", "the candidates are not drawn alike: #{signatures.uniq.size} different styles among #{ids.size} targets") if signatures.compact.uniq.size > 1
      rescue NotImplementedError
        nil
      end

      def fold(text) = text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[^\p{L}\p{N}]+/, " ").strip

      def words(text) = fold(text).split

      # ---- one card -----------------------------------------------------------------------------------

      # Every text-answer check of the card against every figure of the card. +path+: the card's JSON pointer.
      def card(card, path, ctx)
        figures = card_figures(card)
        return if figures.empty?

        printed = figures.flat_map { |f| printed_strings(f) }.map { |s| squash(s) }.reject(&:empty?).to_set
        reach = figures.map { |f| [ f, reachable(f) ] }
        card["blocks"].each_with_index do |block, i|
          located_checks(block, "#{path}/blocks/#{i}").each do |c, at, base|
            ctx.at(at, block["line"], base: base) do
              figure_rules(c, printed, reach, ctx)
            end
          end
        end
      end

      def figure_rules(check, printed, reach, ctx)
        answers = answers_of(check)
        return if answers.empty?

        if (hit = answers.find { |a| printed.any? { |p| same?(p, a) } })
          ctx.add("W-CHECK-ANSWER-IN-DIAGRAM", "answer", "the answer #{hit.inspect} is printed by a figure of the same card, in one of its states")
        end
        reach.each do |figure, values|
          if values == :over_cap
            ctx.add("E-DIAGRAM-REACHABLE-CAP", "answer", "the #{figure['type']} figure on this card can show more than #{Diagrams::Contract::REACHABLE_CAP} values: narrow its ranges or move the check")
          elsif check["reachable_ok_it"].blank? && (hit = answers.find { |a| values.any? { |v| same?(squash(v), a) } })
            ctx.add("E-CHECK-ANSWER-BY-SIMULATION", "answer", "the answer #{hit.inspect} is a value the #{figure['type']} figure's controls can show; change the check, or say why in reachable_ok_it")
          end
        end
      end

      # The figures of a card the student sees with the lesson (not a select check's own neutral figure).
      def card_figures(card)
        card["blocks"].flat_map do |b|
          list = Blocks.diagrams(b)
          list += b["exercises"].to_a.filter_map { |e| e["diagram"] } if b["type"] == "try"
          list
        end.select { |d| d.is_a?(Hash) }
      end

      def printed_strings(figure)
        mod = Diagrams.module_for(figure["type"])
        return [] unless mod.is_a?(Diagrams::Contract)

        # the second argument is the index of the state (the types read Diagrams.effective_states(data)[state] themselves)
        count = [ Array(figure["states"]).size, 1 ].max
        (0...count).flat_map { |i| Array(mod.printed(figure, i)).map(&:to_s) }
      rescue NotImplementedError, StandardError
        [] # not built, or a figure whose data is wrong (its own findings say so)
      end

      def reachable(figure)
        mod = Diagrams.module_for(figure["type"])
        mod.is_a?(Diagrams::Contract) ? mod.reachable(figure).then { |r| r == :over_cap ? r : Array(r).map(&:to_s) } : []
      rescue NotImplementedError, StandardError
        []
      end

      # [[check, json pointer, base in the block's yaml]] of a block.
      def located_checks(block, path)
        case block["type"]
        when "check" then [ [ block, path, "" ] ]
        when "example" then block["steps"].to_a.each_with_index.filter_map { |s, i| [ s["blank"], path, "steps/#{i}/blank" ] if s["blank"] }
        when "try"
          block["exercises"].to_a.each_with_index.flat_map do |e, i|
            list = e["checks"] ? e["checks"].each_with_index.map { |c, k| [ c, "checks/#{k}" ] } : [ e["check"] ].compact.map { |c| [ c, "check" ] }
            list.map { |c, where| [ c, "#{path}/exercises/#{i}/#{where}", "exercises/#{i}/#{where}" ] }
          end
        else []
        end
      end

      # The strings a text-answer check accepts.
      def answers_of(check)
        return [] unless TEXT_ANSWER.include?(check["component"])

        ([ check["answer"] ] + check["accept"].to_a).filter_map { |a| squash(a) if a.is_a?(String) }
      end

      def squash(text) = text.to_s.delete("$").gsub(/[[:space:]]/, "").tr("\u2212", "-").downcase # "0010 1101" and "00101101", "-5" and "−5" are one answer to the eye

      def same?(a, b)
        a == b || (Num.valid?(a) && Num.valid?(b) && Num.compare(a, b)&.zero?)
      end
    end
  end
end
