# frozen_string_literal: true

module Lessons
  module Blocks
    # An inline question (A9): the declared answer must be consistent with the component, the typical errors must be
    # wrong answers of the same shape. Used for check blocks, example blanks and try exercise checks.
    module Check
      TEXT_KEYS = %w[text_it text_en text_es].freeze

      module_function

      def check(check, ctx)
        case check["component"]
        when "choice" then choice(check, ctx)
        when "number", "fraction" then number(check, ctx)
        when "normalized_text" then text(check, ctx)
        when "matching" then matching(check, ctx)
        when "span_select" then span_select(check, ctx)
        when "tiles" then tiles(check, ctx)
        when "ordering" then ordering(check, ctx)
        when "select" then select(check, ctx)
        end
        Truth.check(check, ctx)
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
        bits(check, ctx) if check["input"] == "bits"
        norm = ->(s) { s.to_s.strip.downcase }
        check["errors"].to_a.each_with_index do |e, i|
          ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer") if norm.call(e["answer"]) == norm.call(check["answer"])
        end
      end

      # input: bits (T9): the switches of a register. They need the binary profile with its width; the right answer is exactly that many bits;
      # and with switches every error answer is that many bits too (a shorter one cannot be given), unless an error under test is
      # padding_missing, which keeps the typed input (Lessons::Checks.bits_switches?).
      def bits(check, ctx)
        profile = check["profile"]
        unless profile.is_a?(Hash) && profile["name"] == "binary" && profile["width"]
          ctx.add("E-LESSON-CHECK", "input", "input: bits needs profile: {name: binary, width: N}")
          return
        end
        width = profile["width"]
        binary = ->(s) { s.is_a?(String) && s.match?(/\A[01]+\z/) }
        ctx.add("E-LESSON-CHECK", "answer", "the answer of input: bits is #{width} bits, written as 0 and 1") unless binary.call(check["answer"]) && check["answer"].size == width
        return unless Checks.bits_switches?(check)

        check["errors"].to_a.each_with_index do |e, i|
          next if binary.call(e["answer"]) && e["answer"].size == width

          ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "with switches an error answer is #{width} bits; a shorter one can only be typed: use the code padding_missing")
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

      # tiles (WAVE2 2.11): a sentence built from tiles; distractors are the tiles outside the answer.
      def tiles(check, ctx)
        tiles = check["tiles"].to_a
        ids = tiles.map { |t| t["id"] }
        ctx.add("E-LESSON-CHECK", "tiles", "tile ids must be unique") if ids.uniq.size != ids.size
        tiles.each_with_index do |t, i|
          n = t.keys.count { |k| TEXT_KEYS.include?(k) }
          ctx.add("E-LESSON-CHECK", "tiles/#{i}", "a tile has exactly one of text_it, text_en, text_es (it has #{n})") unless n == 1
        end
        langs = tiles.flat_map { |t| t.keys & TEXT_KEYS }.uniq
        ctx.add("E-LESSON-LANG", "tiles", "the tiles of a check are in one language (#{langs.join(', ')})") if langs.size > 1
        sequence(check["answer"], ids, "answer", ctx, min: 2)
        ctx.add("E-LESSON-CHECK", "tiles", "a tiles check needs at least one tile outside the answer (a distractor)") if (ids - check["answer"].to_a).empty?
        check["accept"].to_a.each_with_index do |seq, i|
          sequence(seq, ids, "accept/#{i}", ctx, min: 2)
          ctx.add("E-LESSON-CHECK", "accept/#{i}", "an accepted sequence equals the answer") if seq == check["answer"]
        end
        error_sequences(check, ids, ctx)
        built = Array(check["answer"]).filter_map { |id| tiles.find { |t| t["id"] == id }&.values_at(*TEXT_KEYS)&.compact&.first }.join(" ")
        squash = ->(s) { s.to_s.delete("$").gsub(/\s+/, " ").strip.downcase }
        if built.size >= 6 && squash.call(check["prompt_it"]).include?(squash.call(built))
          ctx.add("W-CHECK-ANSWER-IN-PROMPT", "prompt_it", "the sentence to build appears in its own prompt")
        end
      end

      # ordering: put the items in order; the answer is the right order of all of them.
      def ordering(check, ctx)
        ids = check["items"].to_a.map { |o| o["id"] }
        ctx.add("E-LESSON-CHECK", "items", "item ids must be unique") if ids.uniq.size != ids.size
        answer = check["answer"].to_a
        ctx.add("E-LESSON-CHECK", "answer", "the answer puts every item once, in order (#{ids.join(', ')})") unless answer.sort == ids.sort
        error_sequences(check, ids, ctx)
        check["errors"].to_a.each_with_index do |e, i|
          ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "the error answer of an ordering puts every item once") if e["answer"].is_a?(Array) && e["answer"].sort != ids.sort
        end
      end

      def sequence(seq, ids, path, ctx, min:)
        list = Array(seq)
        ctx.add("E-LESSON-CHECK", path, "#{list.inspect} is not a list of at least #{min} distinct tile ids") if list.size < min || list.uniq.size != list.size
        ctx.add("E-LESSON-CHECK", path, "#{(list - ids).inspect} are not ids of the tiles") unless (list - ids).empty?
      end

      def error_sequences(check, ids, ctx)
        check["errors"].to_a.each_with_index do |e, i|
          if !e["answer"].is_a?(Array) || !(e["answer"] - ids).empty? || e["answer"].uniq.size != e["answer"].size
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "the error answer is a list of distinct ids of this check")
          elsif e["answer"] == check["answer"]
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer")
          end
        end
      end

      # select (WAVE2 2.11): the figure's type must declare the target set; answers name stored ids of that set.
      def select(check, ctx)
        diagram = check["diagram"]
        set = check["targets"]
        declared = SelectTargets.declared_sets(check)
        unless declared.include?(set)
          ctx.add("E-LESSON-CHECK", "targets", "the #{diagram['type']} figure has no target set #{set.inspect}#{declared.empty? ? ' (it declares none)' : " (it declares #{declared.join(', ')})"}")
          return
        end
        ids = begin
          SelectTargets.ids(check)
        rescue NotImplementedError
          ctx.add("E-LESSON-CHECK", "targets", "#{diagram['type']} does not offer select targets yet")
          return
        end
        ctx.add("E-LESSON-CHECK", "targets", "the figure offers #{ids.size} targets in #{set} (a select check needs 3 to 40)") unless (3..40).cover?(ids.size)
        answer = check["answer"].to_a.map(&:to_s)
        ctx.add("E-LESSON-CHECK", "answer", "the answer #{(answer - ids).inspect} names targets the figure does not offer in #{set}") unless (answer - ids).empty?
        ctx.add("E-LESSON-CHECK", "answer", "the answer names a target twice") if answer.uniq.size != answer.size
        ctx.add("E-LESSON-CHECK", "answer", "all targets are the answer") if answer.sort == ids.sort
        check["errors"].to_a.each_with_index do |e, i|
          if !e["answer"].is_a?(Array) || !(e["answer"].map(&:to_s) - ids).empty?
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "the error answer is a list of targets of #{set}")
          elsif e["answer"].map(&:to_s).sort == answer.sort
            ctx.add("E-LESSON-CHECK", "errors/#{i}/answer", "an error answer equals the right answer")
          end
        end
        Truth.select_figure(check, ids, ctx)
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
        # a cloze's bracketed cue right after the gap, "When I ___ (get) home", is the material, not a leak (D-110, D-266)
        cue = ->(s) { check["component"] == "normalized_text" ? s.to_s.gsub(/_{2,}\s*\([^)]*\)/, " ___ ") : s }
        prompt = squash.call(cue.call(check["prompt_it"]))
        needle = squash.call(answer)
        return if needle.size < 2 && %w[number fraction].exclude?(check["component"]) && needle.match?(/\A\p{L}\z/)

        hit = prompt.match?(/(?<![\p{L}\p{N},])#{Regexp.escape(needle)}(?![\p{L}\p{N}]|,\d)/)
        ctx.add("W-CHECK-ANSWER-IN-PROMPT", "prompt_it", "the answer #{answer.inspect} appears in its own prompt") if hit
      end
    end
  end
end
