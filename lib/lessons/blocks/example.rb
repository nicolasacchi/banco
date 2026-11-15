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

      CELL_REF = /(?<![\p{L}\p{N}])[A-Z]{1,2}\d{1,3}(?![\p{L}\p{N}])/
      # An Italian number as written: grouped thousands (150.000, 1.115,50), or plain with a decimal comma or point (2,5, 2.5, 150000).
      NUMBER = /(?<![\p{L}\p{N}.,])(?:\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:[.,]\d+)?)(?![\p{L}\p{N}])/
      GROUPED = /\A\d{1,3}(?:\.\d{3})+(?:,\d+)?\z/
      # Fields of a block the page never serves before an answer (or that are not text the student reads).
      FORMULA = /\$[^$]*\$|\[\[.*?\]\]/
      UNSEEN_KEYS = %w[n line type level answer accept errors explain_it model_it verify result_it].freeze

      # W-BLANK-STEP-DATUM. The page withholds the do_it of a blank step (it usually holds the answer) and shows only its reason and the
      # question. A number or a cell reference (B3, 8, 2,5) that the do_it gives and nothing visible before the question shows is a datum
      # the student cannot know: "Scrivi 8 in B3." hidden, "Che numero compare in C3?" asked. Visible before the question: the card's
      # title and earlier blocks, the problem, the do_it and why_it of the earlier steps, the step's own why_it and its question. The
      # blank's own answer is exempt (it is meant to stay hidden), and so is what sits in a formula ($x = 5$) or a span ([[code:#DIV/0!]]):
      # that is working, the result of the steps before, not a datum given in words. +path+: the card's JSON pointer. Numbers and cell references only.
      def blank_data(card, path, ctx)
        before = [ card["title_it"] ]
        card["blocks"].each_with_index do |block, j|
          if block["type"] == "example"
            ctx.at("#{path}/blocks/#{j}", block["line"]) { example_data(block, before, ctx) }
            before << block["problem_it"] << block["steps"].to_a.flat_map { |s| [ s["do_it"], s["why_it"] ] }
          else
            before << visible_strings(block)
          end
        end
      end

      def example_data(block, before, ctx)
        seen = data_tokens(before)
        seen.merge(data_tokens(block["problem_it"]))
        block["steps"].to_a.each_with_index do |step, i|
          blank = step["blank"]
          if blank
            seen.merge(data_tokens([ step["why_it"], visible_strings(blank) ]))
            answers = data_tokens(all_strings([ blank["answer"], blank["accept"] ]))
            missing = data_pairs(step["do_it"].to_s.gsub(FORMULA, " ")).reject { |key, _shown| seen.include?(key) || answers.include?(key) }.map(&:last).uniq
            unless missing.empty?
              ctx.add("W-BLANK-STEP-DATUM", "steps/#{i}/do_it", "the do_it of this blank step is not shown before the question, but it gives #{missing.join(', ')}, which nothing before the question shows: put it in an earlier step or in the question (prompt_it)", rule: "blank-datum-#{ctx.path}/steps/#{i}")
            end
          end
          seen.merge(data_tokens([ step["do_it"], step["why_it"] ]))
        end
      end

      # The numbers and cell references of a text (or a nested list of texts), as a set of values: a cell reference as written ("B3"), a number
      # as the grader reads it (a Rational: "150.000", "150000" and "150000,00" are one value, "2,5" and "2.5" are one value).
      def data_tokens(text) = data_pairs(text).map(&:first).to_set

      # [value, as written] for each number and cell reference of the text(s), in order.
      def data_pairs(text)
        Array(text).flatten.flat_map do |t|
          next [] unless t.is_a?(String)

          t.scan(CELL_REF).map { |c| [ c, c ] } + t.gsub(CELL_REF, " ").scan(NUMBER).map { |n| [ number_value(n), n ] }
        end
      end

      # The grader's reading of an Italian number (Grading::Closed::Numbers.parse): a dot that groups exactly three digits is a thousands
      # separator, a comma is the decimal mark, a lone dot with other than three digits is a decimal point.
      def number_value(token)
        plain = token.match?(GROUPED) ? token.delete(".") : token
        Rational(plain.tr(",", "."))
      end

      # Every string anywhere in a value (an answer, its accepted forms), whatever the nesting.
      def all_strings(node)
        case node
        when Hash then node.values.flat_map { |v| all_strings(v) }
        when Array then node.flat_map { |v| all_strings(v) }
        when String then [ node ]
        when Numeric then [ node.to_s ]
        else []
        end
      end

      # Every string and number of a block that the page serves (what the student can read), keys it never serves left out.
      def visible_strings(node)
        case node
        when Hash then node.except(*UNSEEN_KEYS).values.flat_map { |v| visible_strings(v) }
        when Array then node.flat_map { |v| visible_strings(v) }
        when String then [ node ]
        when Numeric then [ node.to_s ]
        else []
        end
      end
    end
  end
end
