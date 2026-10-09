# frozen_string_literal: true

module Lessons
  module Blocks
    # An inline question (A9): the declared answer must be consistent with the component, the typical errors must be
    # wrong answers of the same shape. Used for check blocks, example blanks and try exercise checks.
    module Check
      module_function

      def check(check, ctx)
        case check["component"]
        when "choice" then choice(check, ctx)
        when "number", "fraction" then number(check, ctx)
        when "normalized_text" then text(check, ctx)
        when "matching" then matching(check, ctx)
        when "span_select" then span_select(check, ctx)
        end
        errors_common(check, ctx)
        answer_in_prompt(check, ctx)
      end

      def errors_common(check, ctx)
        check["errors"].to_a.each_with_index do |e, i|
          ctx.catalogue_code("errors/#{i}/code", e["code"])
        end
      end

      def choice(check, ctx)
        ids = check["options"].to_a.map { |o| o["id"] }
        ctx.add("E-LESSON-CHECK", "options", "option ids must be unique") if ids.uniq.size != ids.size
        ctx.add("E-LESSON-CHECK", "answer", "the answer #{check['answer'].inspect} is not among the options (#{ids.join(', ')})") unless ids.include?(check["answer"])
        check["errors"].to_a.each_with_index do |e, i|
          if e["answer"] == check["answer"]
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer")
          elsif !ids.include?(e["answer"])
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "the error answer #{e['answer'].inspect} is not among the options")
          end
        end
      end

      def number(check, ctx)
        plain = check["component"] == "number"
        unless Num.valid?(check["answer"]) && (!plain || check["answer"].match?(/\A-?\d+(,\d+)?\z/))
          ctx.add("E-LESSON-CHECK", "answer", "the answer #{check['answer'].inspect} is not a number the practice rules read (an integer or a decimal with comma 2,5#{'; a fraction 5/2 is for the fraction component' if plain})")
          return
        end
        check["errors"].to_a.each_with_index do |e, i|
          if !e["answer"].is_a?(String) || !Num.valid?(e["answer"])
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "the error answer #{e['answer'].inspect} is not an exact number (comma for decimals)")
          elsif Num.compare(e["answer"], check["answer"]) == 0
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer")
          end
        end
      end

      def text(check, ctx)
        ctx.add("E-LESSON-CHECK", "answer", "the answer is empty") if check["answer"].to_s.strip.empty?
        norm = ->(s) { s.to_s.strip.downcase }
        check["errors"].to_a.each_with_index do |e, i|
          ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer") if norm.call(e["answer"]) == norm.call(check["answer"])
        end
      end

      def matching(check, ctx)
        left = check["left"].to_a.map { |o| o["id"] }
        right = check["right"].to_a.map { |o| o["id"] }
        ctx.add("E-LESSON-CHECK", "left", "ids must be unique in each column") if left.uniq.size != left.size || right.uniq.size != right.size
        answer = check["answer"].to_h
        ctx.add("E-LESSON-CHECK", "answer", "the answer pairs every left id (#{left.join(', ')}) once") unless answer.keys.sort == left.sort
        ctx.add("E-LESSON-CHECK", "answer", "the answer names a right id that does not exist") unless (answer.values - right).empty?
        if !check["reuse_right"] && answer.values.uniq.size != answer.values.size
          ctx.add("E-LESSON-CHECK", "answer", "two left items share a right item: set reuse_right: true for a classification")
        end
        check["errors"].to_a.each_with_index do |e, i|
          if !e["answer"].is_a?(Hash)
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "the error answer of a matching is a mapping left id -> right id")
          elsif e["answer"] == answer
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer")
          end
        end
      end

      def span_select(check, ctx)
        spans = check["spans"].to_a
        ids = spans.map { |s| s["id"] }
        ctx.add("E-LESSON-CHECK", "spans", "span ids must be unique") if ids.uniq.size != ids.size
        cursor = 0
        spans.each_with_index do |s, i|
          found = check["text_it"].to_s.index(s["text_it"], cursor)
          if found
            cursor = found + s["text_it"].size
          else
            ctx.add("E-LESSON-CHECK", "spans/#{i}/text_it", "spans are exact pieces of text_it, in order: #{s['text_it'].inspect}")
          end
        end
        ctx.add("E-LESSON-CHECK", "answer", "the answer names a span that does not exist") unless (check["answer"].to_a - ids).empty?
        check["errors"].to_a.each_with_index do |e, i|
          if !e["answer"].is_a?(Array) || !(e["answer"] - ids).empty?
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "the error answer is a list of span ids")
          elsif e["answer"].sort == check["answer"].to_a.sort
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer")
          end
        end
      end

      # The text of the right answer, for a choice its option, else the answer string (nil when it is not a string).
      def answer_text(check)
        case check["component"]
        when "choice" then check["options"].to_a.find { |o| o["id"] == check["answer"] }&.fetch("text_it", nil)
        when "number", "fraction", "normalized_text" then check["answer"]
        end
      end

      def answer_in_prompt(check, ctx)
        # a choice lists its options and a span_select shows its sentence: the answer is rightly on the page
        return unless %w[number fraction normalized_text].include?(check["component"])

        answer = answer_text(check).to_s
        return if answer.empty?

        squash = ->(s) { s.to_s.delete("$").gsub(/\s+/, " ").strip.downcase }
        prompt = squash.call(check["prompt_it"])
        needle = squash.call(answer)
        return if needle.size < 2 && %w[number fraction].exclude?(check["component"]) && needle.match?(/\A\p{L}\z/)

        hit = prompt.match?(/(?<![\p{L}\p{N},])#{Regexp.escape(needle)}(?![\p{L}\p{N}]|,\d)/)
        ctx.add("W-CHECK-ANSWER-IN-PROMPT", "prompt_it", "the answer #{answer.inspect} appears in its own prompt") if hit
      end
    end
  end
end
