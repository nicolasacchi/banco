# frozen_string_literal: true

module Lessons
  module Blocks
    # The exercises of the try card (A4, A9, A12): easy to hard, each with a check, or a final answer; the solution
    # is served on request, the final is checked against it. An exercise has a text (`text_it`, in a bilingual lesson the target text in that slot), except a
    # typed gap whose `input_before` / `input_after` carry the sentence (D-402): the schema of english and spanish does not ask for the text, this does.
    module Try
      TYPED = %w[number fraction normalized_text].freeze

      # The page draws «a)», «b)» before the checks of an exercise that has several: a prompt that starts with its own label shows it twice (D-402).
      LABEL = /\A\s*\(?[a-h]\)\s|\A\s*[a-h]\.\s/i
      LABEL_MESSAGE = "the prompt starts with its own label: the page already draws a), b) before the checks of an exercise with several"

      module_function

      # [[pointer under the block, prompt]] of the prompts that start with a label, in an exercise with more than one check.
      def labelled_prompts(block)
        block["exercises"].to_a.each_with_index.flat_map do |ex, i|
          checks = ex["checks"]
          next [] unless checks.is_a?(Array) && checks.size > 1

          checks.each_with_index.filter_map { |c, k| [ "exercises/#{i}/checks/#{k}/prompt_it", c["prompt_it"] ] if c.is_a?(Hash) && c["prompt_it"].is_a?(String) && c["prompt_it"].match?(LABEL) }
        end
      end

      def check(block, ctx)
        lo, hi = Validation::Rules.get(:lesson2, :try_exercises)
        n = block["exercises"].to_a.size
        ctx.add("E-LESSON-EXERCISES", "exercises", "Prova tu has #{n} exercises (#{lo} to #{hi})", rule: "range") unless (lo..hi).cover?(n)
        labelled_prompts(block).each { |pointer, _| ctx.add("W-CHECK-LABEL-DOUBLED", pointer, LABEL_MESSAGE, rule: "label-doubled-#{pointer}") }
        per = Validation::Rules.get(:lesson2, :try_checks_per_exercise)
        block["exercises"].to_a.each_with_index do |ex, i|
          checks = ex["checks"] || [ ex["check"] ].compact
          text(ex, i, checks, ctx)
          ctx.add("E-LESSON-CHECKS", "exercises/#{i}", "an exercise has at most #{per} checks (parts a, b, c)", rule: "per-exercise-#{i}") if checks.size > per
          checks.each_with_index do |c, k|
            where = ex["checks"] ? "checks/#{k}" : "check"
            ctx.at("#{ctx.path}/exercises/#{i}/#{where}", ctx.line, base: "exercises/#{i}/#{where}") { Check.check(c, ctx) }
          end
          ex["solution_steps"].to_a.each_with_index { |s, k| ctx.tag("exercises/#{i}/solution_steps/#{k}/tag", s["tag"]) if s["tag"] }
          final(ex, i, checks, ctx)
        end
      end

      # E-LESSON-BLOCK: an exercise with no text, unless each of its checks is a typed gap that holds the sentence around its box.
      def text(ex, i, checks, ctx)
        return if Check::TEXT_KEYS.any? { |k| ex[k].is_a?(String) }
        return if checks.any? && checks.all? { |c| TYPED.include?(c["component"]) && (c["input_before"] || c["input_after"]) }

        name = "text_#{Lang.target(ctx.subject) || 'it'}"
        ctx.add("E-LESSON-BLOCK", "exercises/#{i}/#{name}", "exercise #{i + 1} has no text: write #{name}, or make it a typed gap whose input_before / input_after carry the sentence", rule: "text-#{i}")
      end

      def final(ex, i, checks, ctx)
        final = ex["final_it"]
        if final.nil? && checks.empty?
          ctx.add("W-LESSON-FINAL-MISSING", "exercises/#{i}", "exercise #{i + 1} has neither a check nor a final answer: the teacher cannot see the right result", rule: "neither-#{i}")
          return
        end
        return unless final.is_a?(String)

        norm = ->(t) { t.to_s.delete("$ ").tr("−", "-") }
        needle = norm.call(final)
        return if needle.size < 3

        solution = ex["solution_it"] || ex["solution_steps"].to_a.map { |s| "#{s['do_it']} #{s['why_it']}" }.join(" ")
        ctx.add("W-LESSON-FINAL-MISSING", "exercises/#{i}/final_it", "the final answer of exercise #{i + 1} does not appear in its solution", rule: "final-missing-#{i}") unless norm.call(solution).include?(needle)
        ctx.add("W-LESSON-FINAL-IN-TRY", "exercises/#{i}/text_it", "the final answer of exercise #{i + 1} appears in its own text", rule: "final-in-try-#{i}") if norm.call(ex["text_it"]).include?(needle)
      end
    end
  end
end
