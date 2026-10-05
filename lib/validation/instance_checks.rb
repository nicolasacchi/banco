# frozen_string_literal: true

module Validation
  # The checks on one instance (one question as the student will see it, with its
  # key): shape, the size rules of choice, ordering and matching, leaks of the key
  # into what the student reads, component fit and the readability of generated
  # text. It returns the findings of this one instance; the caller decides whether
  # the seed is clean and merges what it keeps.
  class InstanceChecks
    CHOICE_RANGE = (3..5)
    ORDERING_RANGE = (3..7)
    MIN_PAIRS = 4
    MIN_CATEGORIES = 3

    # label: where the instance is, in finding fields ("generated" or
    # "/instances/2"); seed is set for generated ones; files: the revision's files,
    # for the asset and SVG text checks.
    def initialize(unit, context:, files: {})
      @unit = unit
      @context = context
      @files = files
    end

    def call(inst, label:, seed: nil, generated: false)
      f = Findings.new
      display = inst["display"]
      answer = inst["answer"]
      unless display.is_a?(Hash) && !answer.nil?
        f.add("E-GEN-SCHEMA", label, "an instance has a display object and an answer", rule: "shape", seed: seed)
        return f
      end

      keys = Answers.display_keys(display)
      keys.each { |path, name| f.add("E-DISPLAY-KEY", "#{label}/display#{path}", "the display carries a field that reveals the answer (#{name})", seed: seed) }
      SchemaCheck.generated(inst, f, seed: seed) if generated && keys.empty?
      size_rules(display, label, seed, f)
      problems = Answers.shape_problems(@unit.component, answer, display)
      problems.each { |p| f.add("E-GEN-SCHEMA", "#{label}/answer", p, rule: "answer_shape", seed: seed) }
      errors(inst, label, seed, f)
      accept_rules(inst, label, seed, f)
      choice_rules(display, answer, inst, label, seed, f) if @unit.component == "choice" && problems.empty?
      leaks(display, answer, inst, label, seed, f) if problems.empty?
      component_fit(answer, inst, label, seed, f)
      steps(inst, label, seed, f) if problems.empty?
      quote_and_figure(display, label, seed, f)
      if generated
        Readability.lint_document({ "display" => display, "solution" => inst["solution"] }, label, f)
      end
      f
    end

    # True when the correct option is the longest of its options (W-LONGEST-CORRECT).
    def longest_correct?(inst)
      options = Array(inst.dig("display", "options"))
      key = options.find { |o| o["id"] == inst["answer"].to_s }
      key && options.all? { |o| o["id"] == key["id"] || o["text"].to_s.length < key["text"].to_s.length }
    end

    private

    # ---- sizes ---------------------------------------------------------------

    def size_rules(display, label, seed, f)
      case @unit.component
      when "choice"
        n = Array(display["options"]).size
        f.add("E-CHOICE-OPTIONS", "#{label}/display/options", "a choice has 3 to 5 options (never 2), not #{n}", count: n, seed: seed) unless CHOICE_RANGE.cover?(n)
      when "ordering"
        n = Array(display["elements"]).size
        f.add("E-CHOICE-OPTIONS", "#{label}/display/elements", "an ordering has 3 to 7 elements, not #{n}", count: n, seed: seed) unless ORDERING_RANGE.cover?(n)
      when "matching"
        l = Array(display["left"]).size
        r = Array(display["right"]).size
        f.add("E-MATCHING-SIZE", "#{label}/display/left", "a matching has at least #{MIN_PAIRS} pairs, not #{l}", count: l, seed: seed) if l < MIN_PAIRS
        if display["reuse_right"] == true
          # A classification (D-092): rows share categories, so the right column is shorter than the left.
          unless r >= MIN_CATEGORIES && r < l
            f.add("E-MATCHING-SIZE", "#{label}/display/right", "a classification has at least #{MIN_CATEGORIES} categories and fewer categories than rows (#{l}), not #{r}", count: r, seed: seed)
          end
        elsif r != l + 1
          f.add("E-MATCHING-SIZE", "#{label}/display/right", "the right column has n+1 entries (#{l + 1}), not #{r}", count: r, seed: seed)
        end
        # The right column is drawn as <option> elements: no markup renders there (D-081).
        Array(display["right"]).each_with_index do |e, i|
          next unless e.is_a?(Hash) && e["text"].to_s.match?(/[$\\]|\*\*/)

          f.add("E-MATCHING-RIGHT-MARKUP", "#{label}/display/right/#{i}/text", "the right column is plain text (no $, no backslash, no **): write x \u2264 -2, not LaTeX", seed: seed)
        end
      end
    end

    # ---- error values -----------------------------------------------------------

    def errors(inst, label, seed, f)
      known = @unit.catalogue_codes
      Array(inst["errors"]).each_with_index do |e, i|
        next if known.include?(e["code"])

        f.add("E-GEN-SCHEMA", "#{label}/errors/#{i}", "the error code #{e['code'].inspect} is not in the item's error_catalogue", rule: "code_not_in_catalogue", seed: seed)
      end
    end

    # An instance's own accept list (D-081) belongs to normalized_text, like the item's.
    def accept_rules(inst, label, seed, f)
      return if inst["accept"].nil?

      if @unit.component != "normalized_text"
        f.add("E-GEN-SCHEMA", "#{label}/accept", "accept on an instance belongs to normalized_text items", rule: "accept_component", seed: seed)
        return
      end
      Array(inst["accept"]).each_with_index do |text, i|
        next unless Answers.punctuation_only?(text)

        f.add("E-SCHEMA", "#{label}/accept/#{i}", "an accepted text that is only punctuation normalizes to nothing: no answer could match it", seed: seed)
      end
    end

    def choice_rules(display, answer, inst, label, seed, f)
      options = Array(display["options"])
      texts = options.map { |o| Answers.plain(o["text"]) }
      if texts.uniq.size != texts.size
        f.add("E-OPTION-DUPLICATE", "#{label}/display/options", "two options have the same text", seed: seed)
      end
      coded = Array(inst["errors"]).to_h { |e| [ e["value"].to_s, e["code"] ] }
      options.each do |o|
        next if o["id"] == answer.to_s
        next if coded[o["id"]] && @unit.catalogue_codes.include?(coded[o["id"]])

        f.add("E-DISTRACTOR-UNCODED", "#{label}/display/options/#{o['id']}", "the distractor #{o['id']} has no error code from the catalogue", option: o["id"], seed: seed)
      end
    end

    # ---- leaks ---------------------------------------------------------------

    # Strings the student reads outside the stem (and outside the options for a
    # choice): table cells, captions, figure text.
    def readable_strings(display, include_stem:, include_options:)
      Canonical.strings(display).reject do |path, _|
        path == "/quote/text" || path == "/quote/ref" ||
          (!include_stem && path == "/stem_it") ||
          (!include_options && path.start_with?("/options/"))
      end + svg_strings(display)
    end

    def svg_strings(display)
      asset = display.dig("figure", "asset")
      text = asset && @files[asset]
      return [] unless text

      text.scan(%r{<(?:text|title|desc)[^>]*>(.*?)</(?:text|title|desc)>}mi).flatten.map { |t| [ "svg:#{asset}", t.gsub(/<[^>]+>/, " ") ] }
    end

    def leaks(display, answer, inst, label, seed, f)
      component = @unit.component
      prompt = @unit.body["prompt"].is_a?(Hash) ? @unit.body["prompt"].slice("stem_it", "table", "quote", "figure") : {}
      if component == "choice"
        key = Array(display["options"]).find { |o| o["id"] == answer.to_s }
        needles = key ? [ key["text"] ] : []
        scope = readable_strings(display, include_stem: true, include_options: false)
        # The item's own prompt is read with every instance (D-081).
        scope += prefixed(readable_strings(prompt, include_stem: true, include_options: false), "prompt")
      else
        needles = Answers.key_texts(component, answer, accept: @unit.accept + Array(inst["accept"]))
        needles += ordering_texts(display, answer) + matching_texts(display, answer)
        scope = readable_strings(display, include_stem: false, include_options: false)
        scope += prefixed(readable_strings(prompt, include_stem: false, include_options: false), "prompt")
        [ [ display["stem_it"], "#{label}/display/stem_it" ], [ prompt["stem_it"], "#{label}/prompt/stem_it" ] ].each do |stem, field|
          text = component == "normalized_text" ? stem.to_s.gsub(/«[^»]*»/, " ") : stem.to_s
          next unless needles.any? { |n| Answers.contains?(text, n) }

          f.add("W-ANSWER-IN-STEM", field, "the expected answer appears in the instruction", seed: seed)
        end
      end
      final = inst.dig("solution", "final").to_s
      needles += [ final ] if Answers.plain(final).length >= Answers::MIN_LEAK_CHARS && component != "choice"
      needles.each do |n|
        hit = scope.find { |_path, text| Answers.contains?(text, n) }
        next unless hit

        where = hit[0].start_with?("prompt:") ? "#{label}/prompt#{hit[0].delete_prefix('prompt:')}" : "#{label}/display#{hit[0]}"
        f.add("E-SOLUTION-IN-DISPLAY", where, "the key or the solution appears where the student reads (#{n.to_s[0, 30].inspect})", seed: seed)
        break
      end
    end

    def prefixed(strings, tag) = strings.map { |path, text| [ "#{tag}:#{path}", text ] }

    # "A, B, C" in key order, with the usual separators.
    def ordering_texts(display, answer)
      return [] unless @unit.component == "ordering" && answer.is_a?(Array)

      by_id = Array(display["elements"]).to_h { |e| [ e["id"], e["text"] ] }
      texts = answer.map { |id| by_id[id.to_s] }
      return [] if texts.any?(&:nil?)

      [ ", ", " - ", " > ", " -> ", " → ", " < ", "; " ].map { |sep| texts.join(sep) }
    end

    # "left - right" for each correct pair.
    def matching_texts(display, answer)
      return [] unless @unit.component == "matching"

      pairs = Answers.matching_raw(answer).first or return []
      left = Array(display["left"]).to_h { |e| [ e["id"], e["text"] ] }
      right = Array(display["right"]).to_h { |e| [ e["id"], e["text"] ] }
      pairs.flat_map do |l, r|
        next [] unless left[l] && right[r]

        [ " - ", " → ", " -> ", ": ", " = ", " / " ].map { |sep| "#{left[l]}#{sep}#{right[r]}" }
      end
    end

    # ---- component fit -------------------------------------------------------

    NUMERIC_LATEX = %r{\A[-+]?\d+([.,]\d+)?(/\d+)?\z}

    def component_fit(answer, inst, label, seed, f)
      return unless @unit.component == "expression"

      values = [ answer ] + Array(inst["errors"]).map { |e| e["value"] }
      latex = (answer.is_a?(Hash) ? answer["latex"] : answer).to_s
      plain = latex.gsub(/\\frac\{(\d+)\}\{(\d+)\}/, '\1/\2').gsub(/\s+/, "")
      if plain.match?(NUMERIC_LATEX)
        f.add("E-COMPONENT-NUMERIC", "#{label}/answer", "a rational with no letters must use the number or fraction component", seed: seed)
      end
      values.each do |v|
        text = (v.is_a?(Hash) ? v["latex"] : v).to_s
        big = text.scan(/\^\s*\{?\s*(\d{2,})/).flatten.any? { |d| d.to_i >= 10 }
        if big
          f.add("E-EXPONENT-MULTIDIGIT", "#{label}/answer", "an exponent of 10 or more cannot be typed: keep exponents to one digit", seed: seed)
          break
        end
      end
    end

    # ---- the solution agrees with the key ---------------------------------------

    NUMBER = %r{[-−]?\d+(?:\s*/\s*\d+|[.,]\d+)?}

    def steps(inst, label, seed, f)
      final = inst.dig("solution", "final").to_s
      case @unit.component
      when "number", "fraction"
        expected = Answers.rational(inst["answer"].is_a?(Hash) ? { "n" => inst["answer"]["n"], "d" => inst["answer"]["d"] } : inst["answer"])
        values = final.delete("$").gsub("{,}", ",").gsub(/\\d?frac\{(\d+)\}\{(\d+)\}/, '\1/\2').scan(NUMBER).filter_map { |t| Answers.rational(t.tr("−", "-").delete(" ")) }
        inconsistent = expected && values.any? && values.none? { |v| v == expected }
      when "choice"
        options = Array(inst.dig("display", "options"))
        key = options.find { |o| o["id"] == inst["answer"].to_s }
        others = options.reject { |o| o.equal?(key) }
        inconsistent = key && !Answers.contains?(final, key["text"]) && others.any? { |o| Answers.contains?(final, o["text"]) }
      end
      return unless inconsistent

      f.add("E-STEP-INCONSISTENT", "#{label}/solution/final", "the solution ends on something other than the key", seed: seed)
    end

    # ---- quotes and figures ---------------------------------------------------------

    def quote_and_figure(display, label, seed, f)
      if (quote = display["quote"]).is_a?(Hash)
        ItemChecks.quote_ref(quote, "#{label}/display/quote", @context, f, seed: seed)
      end
      asset = display.dig("figure", "asset")
      return unless asset && !@files.key?(asset)

      f.add("E-ASSET", "#{label}/display/figure/asset", "the figure #{asset} is not among the submitted assets", seed: seed)
    end
  end
end
