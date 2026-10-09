# frozen_string_literal: true

module Lessons
  module Blocks
    # The exercises of the try card (A4, A9, A12): easy to hard, each with a check, or a final answer; the solution
    # is served on request, the final is checked against it.
    module Try
      module_function

      def check(block, ctx)
        lo, hi = Validation::Rules.get(:lesson2, :try_exercises)
        n = block["exercises"].to_a.size
        ctx.add("E-LESSON-EXERCISES", "exercises", "Prova tu has #{n} exercises (#{lo} to #{hi})", rule: "range") unless (lo..hi).cover?(n)
        per = Validation::Rules.get(:lesson2, :try_checks_per_exercise)
        block["exercises"].to_a.each_with_index do |ex, i|
          checks = ex["checks"] || [ ex["check"] ].compact
          ctx.add("E-LESSON-CHECKS", "exercises/#{i}", "an exercise has at most #{per} checks (parts a, b, c)", rule: "per-exercise-#{i}") if checks.size > per
          checks.each_with_index do |c, k|
            where = ex["checks"] ? "checks/#{k}" : "check"
            ctx.at("#{ctx.path}/exercises/#{i}/#{where}", ctx.line, base: "exercises/#{i}/#{where}") { Check.check(c, ctx) }
          end
          ex["solution_steps"].to_a.each_with_index { |s, k| ctx.tag("exercises/#{i}/solution_steps/#{k}/tag", s["tag"]) if s["tag"] }
          final(ex, i, checks, ctx)
        end
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
