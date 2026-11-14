# frozen_string_literal: true

module Lessons
  module Blocks
    # The `code` block (D-329): a whole program for S to copy and try on the Mac, in a monospaced box that keeps every space, with what S types
    # and what the screen shows. The schema (b_code) has made the shape right; these are the limits it cannot hold with a code of their own: the
    # language (only vb), the size of the program and of the output (lines and characters), the length of the typed lines, and no tab (the box and
    # the copy must keep the same layout everywhere). The block is never graded, never prose (Blocks.prose does not list it, so it is outside
    # every word count) and is served whole (StudentBody): it holds no answer. The browser side is lesson/blocks/code.js.
    module Code
      LANGS = %w[vb].freeze

      module_function

      def rule(key) = Validation::Rules.get(:lesson2, :types, :code, key.to_sym)

      # The lines of a program or a screen as the box shows them: split on newlines, the one the last line ends with not counted as a line.
      def lines_of(text)
        lines = text.to_s.split("\n", -1)
        lines.pop if lines.last == ""
        lines
      end

      def check(block, ctx)
        ctx.add("E-LESSON-CODE-LANG", "lang", "#{block['lang'].inspect} is not a language of the code block (#{LANGS.join(', ')})", rule: "lang") unless LANGS.include?(block["lang"])
        listing(block["text"], "text", "program", rule(:lines), ctx)
        listing(block["output"], "output", "output", rule(:output_lines), ctx) if block.key?("output")
        input(block["input_it"], ctx) if block.key?("input_it")
      end

      # A program or a screen: not empty, a tab nowhere, at most +max+ lines of at most line_chars characters.
      def listing(text, field, label, max, ctx)
        return unless text.is_a?(String)

        lines = lines_of(text)
        ctx.add("E-LESSON-CODE-SIZE", field, "the #{label} is empty", rule: "#{field}-empty") if text.strip.empty?
        ctx.add("E-LESSON-CODE-SIZE", field, "the #{label} has #{lines.size} lines (at most #{max})", rule: "#{field}-lines") if lines.size > max
        tab = lines.index { |l| l.include?("\t") }
        ctx.add("E-LESSON-CODE-TAB", field, "line #{tab + 1} of the #{label} holds a tab: use four spaces", rule: "#{field}-tab") if tab
        wide = lines.index { |l| l.length > rule(:line_chars) }
        ctx.add("E-LESSON-CODE-SIZE", field, "line #{wide + 1} of the #{label} has #{lines[wide].length} characters (at most #{rule(:line_chars)})", rule: "#{field}-width") if wide
      end

      # What S types: at most input_lines entries of at most input_chars characters, none with a tab or a newline.
      def input(list, ctx)
        return unless list.is_a?(Array)

        ctx.add("E-LESSON-CODE-SIZE", "input_it", "S types #{list.size} lines (at most #{rule(:input_lines)})", rule: "input-lines") if list.size > rule(:input_lines)
        list.each_with_index do |entry, i|
          next unless entry.is_a?(String)

          ctx.add("E-LESSON-CODE-SIZE", "input_it/#{i}", "a typed line has #{entry.length} characters (at most #{rule(:input_chars)})", rule: "input-width-#{i}") if entry.length > rule(:input_chars)
          ctx.add("E-LESSON-CODE-TAB", "input_it/#{i}", "a typed line holds a tab or a newline: one line, plain characters", rule: "input-tab-#{i}") if entry.match?(/[\t\n]/)
        end
      end
    end
  end
end
