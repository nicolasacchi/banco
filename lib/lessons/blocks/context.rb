# frozen_string_literal: true

module Lessons
  module Blocks
    # What the semantic checks of one block need: where it is (the JSON pointer and the lesson line), the subject, the
    # error catalogue of the lesson's skills, and the findings to add to.
    class Context
      attr_reader :subject, :catalogue, :findings
      attr_accessor :path, :line, :base

      # catalogue: the set of error codes of the lesson's skills (nil = unknown: no W-MISTAKE-CODE)
      # resolver: ->(block_line, pointer_in_the_block's_yaml) { the line of that field | nil }
      def initialize(subject:, findings:, catalogue: nil, resolver: nil)
        @subject = subject
        @findings = findings
        @catalogue = catalogue
        @resolver = resolver
        @path = ""
        @line = nil
        @base = ""
      end

      # Inside the block at +path+ (JSON pointer in the body) that opens at +line+; +base+ is where the checked part
      # sits in the block's YAML ("steps/1/blank" for the blank of the second step).
      def at(path, line, base: "")
        saved = [ @path, @line, @base ]
        @path = path
        @line = line
        @base = base
        yield
      ensure
        @path, @line, @base = saved
      end

      def add(code, sub, message, rule: nil, line: nil)
        sub = sub.to_s
        field = "#{@path}#{sub.empty? || sub.start_with?('/') ? sub : "/#{sub}"}"
        detail = { rule: rule || "#{code}#{field}" }
        line ||= @resolver && @line ? @resolver.call(@line, [ @base, sub ].reject(&:empty?).join("/")) : @line
        detail[:line] = line if line
        @findings.add(code, field, message, **detail)
      end

      def error(sub, message, rule: nil) = add("E-LESSON-BLOCK", sub, message, rule: rule)

      def role(sub, name)
        add("E-LESSON-ROLE", sub, "#{name} is not a colour role of #{subject}'s palette (config/banco/lesson_palette.yml)") unless Palette.role?(subject, name)
      end

      def icon(sub, name)
        add("E-LESSON-ICON", sub, "#{name} is not an icon of #{subject} (config/banco/icons.yml)") unless Icons.allowed?(subject, name)
      end

      def tag(sub, name)
        add("E-LESSON-BLOCK", sub, "#{name} is not a step tag of #{subject} (#{Palette.step_tags(subject).keys.join(', ')})") unless Palette.step_tag?(subject, name)
      end

      def catalogue_code(sub, code)
        return if code.nil? || catalogue.nil? || catalogue.include?(code)

        add("W-MISTAKE-CODE", sub, "#{code} is not an error code of the lesson's skills")
      end
    end
  end
end
