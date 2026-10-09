# frozen_string_literal: true

module Lessons
  module Blocks
    # The blocks whose semantic checks are short (A4): callout, math, procedure, cases, legend, mistake, summary,
    # table, more.
    module Simple
      module_function

      def check(block, ctx)
        case block["type"]
        when "callout" then callout(block, ctx)
        when "math" then math(block, ctx)
        when "procedure" then procedure(block, ctx)
        when "cases" then cases(block, ctx)
        when "legend" then legend(block, ctx)
        when "mistake" then ctx.catalogue_code("code", block["code"])
        when "summary" then summary(block, ctx)
        when "table" then table(block, ctx)
        end
      end

      def callout(block, ctx)
        max = Validation::Rules.get(:lesson2, :callout_words)
        n = Blocks.words(block["text_it"])
        ctx.add("E-CARD-WORDS", "text_it", "a callout has #{n} words (at most #{max})") if n > max
      end

      def math(block, ctx)
        formulas = block["tex"] ? [ [ "tex", block["tex"] ] ] : block["lines"].to_a.each_with_index.map { |l, i| [ "lines/#{i}/tex", l["tex"] ] }
        formulas.each do |sub, tex|
          Markup.check_tex(tex, ctx.line.to_i)
          ctx.error(sub, "the formula is not balanced (braces, \\left and \\right)", rule: "tex-#{sub}") unless Diagrams::EquationParts.balanced?(tex)
          Markup.roles_used("$#{tex}$", line_offset: ctx.line.to_i).each { |name, _| ctx.role(sub, name) }
        rescue Markup::Refused => e
          ctx.add("E-LESSON-MARKUP", sub, e.construct, rule: "tex-#{sub}")
        end
      end

      def procedure(block, ctx)
        block["steps"].to_a.each_with_index do |s, i|
          ctx.tag("steps/#{i}/tag", s["tag"])
          next unless s["example_tex"]

          begin
            Markup.check_tex(s["example_tex"], ctx.line.to_i)
            ctx.error("steps/#{i}/example_tex", "the formula is not balanced", rule: "tex-#{i}") unless Diagrams::EquationParts.balanced?(s["example_tex"])
          rescue Markup::Refused => e
            ctx.add("E-LESSON-MARKUP", "steps/#{i}/example_tex", e.construct, rule: "tex-#{i}")
          end
        end
      end

      def cases(block, ctx)
        block["cases"].to_a.each_with_index do |c, i|
          ctx.icon("cases/#{i}/icon", c["icon"]) if c["icon"]
          ctx.role("cases/#{i}/tone", c["tone"]) if c["tone"]
        end
      end

      def legend(block, ctx)
        names = block["roles"].to_a.map { |r| r["role"] }
        names.each_with_index { |name, i| ctx.role("roles/#{i}/role", name) }
        ctx.error("roles", "a role is listed once", rule: "legend-dup") if names.uniq.size != names.size
      end

      def summary(block, ctx)
        lo, hi = Validation::Rules.get(:lesson2, :summary_points)
        pts = block["points_it"].to_a
        ctx.add("E-LESSON-SUMMARY", "points_it", "the summary has #{pts.size} points (#{lo} to #{hi})", rule: "count", line: ctx.line + [ pts.size, 1 ].max) unless (lo..hi).cover?(pts.size)
        max = Validation::Rules.get(:lesson2, :summary_point_words)
        pts.each_with_index { |t, i| ctx.add("E-LESSON-SUMMARY", "points_it/#{i}", "a summary point has #{Blocks.words(t)} words (at most #{max})", rule: "point-#{i}", line: ctx.line + 1 + i) if Blocks.words(t) > max }
      end

      def table(block, ctx)
        width = block["header"].to_a.size
        block["rows"].to_a.each_with_index { |r, i| ctx.error("rows/#{i}", "every row has as many cells as the header (#{width}), here #{r.size}", rule: "ragged-#{i}") unless r.size == width }
      end
    end
  end
end
