# frozen_string_literal: true

module Lessons
  module Blocks
    # A worked example (A4): steps with a reason each, an optional faded step (blank) and a diagram whose states
    # match the steps one to one.
    module Example
      module_function

      def check(block, ctx)
        steps = block["steps"].to_a
        max = Validation::Rules.get(:lesson2, :example_step_words)
        steps.each_with_index do |s, i|
          ctx.tag("steps/#{i}/tag", s["tag"]) if s["tag"]
          n = Blocks.words(s["do_it"]) + Blocks.words(s["why_it"])
          ctx.error("steps/#{i}", "a step has #{n} words in do_it and why_it (at most #{max})", rule: "step-words-#{i}") if n > max
          next unless s["blank"]

          ctx.at("#{ctx.path}/steps/#{i}/blank", ctx.line, base: "steps/#{i}/blank") { Check.check(s["blank"], ctx) }
        end
        diagram = block["diagram"]
        return unless diagram && diagram["states"]

        ctx.add("E-LESSON-DIAGRAM", "diagram/states", "the diagram has #{diagram['states'].size} states and the example #{steps.size} steps: one state for each step") if diagram["states"].size != steps.size
      end
    end
  end
end
