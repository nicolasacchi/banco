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
    # Two categories (physical or chemical, systematic or random) are allowed from 6 rows: 2^6 = 64 blind guesses (D-093).
    MIN_ROWS_TWO_CATEGORIES = 6
    # A judge matching (two right options) has at least this many rows of each option in every instance (D-314).
    JUDGE_MIN_ROWS = 2

    # label: where the instance is, in finding fields ("generated" or
    # "/instances/2"); seed is set for generated ones; files: the revision's files,
    # for the asset and SVG text checks.
    # A key option this long (plain characters) must not appear in the passage of a testlet (D-094).
    PASSAGE_LEAK_MIN_CHARS = 20
    # answer_format_it and steps_it have their own check (E-SUPPORT-LEAK, D-216).
    SUPPORT_PATH = %r{\A/(?:answer_format_it|steps_it(?:/|\z))}

    # bilingual: the revision is a bilingual one (D-402): +unit+ and every instance are read on two layers, the target text under its legacy
    # `_it` key (what every check below was written for) and the Italian translation, scanned for the leaks of the key; +subject+ names the
    # language (a testlet's sub item has no subject of its own).
    def initialize(unit, context:, files: {}, passage: nil, bilingual: false, subject: nil)
      @passage = passage
      @unit = unit
      @context = context
      @files = files
      @subject = subject || unit.body["subject"]
      @lang = bilingual ? Lessons::Lang.target(@subject) : nil
      layer_unit if @lang
    end

    def call(inst, label:, seed: nil, generated: false)
      return run(inst, label: label, seed: seed, generated: generated) unless @lang && inst["display"].is_a?(Hash) && !inst["answer"].nil?

      renamed = @renamed.dup
      found = run(Bilingual.target_layer(inst, @lang, "", renamed), label: label, seed: seed, generated: generated, layered: true)
      f = Findings.new
      found.each { |x| f.add(x.code, Bilingual.author_pointer(x.field, @lang, renamed), x.message, **x.detail.except(:seeds), seed: x.detail[:seeds]&.first) }
      generated_layers(inst, label, seed, f) if generated
      italian = Findings.new
      @italian.scan_italian(Lessons::Bilingual.italian_layer(inst), target_key(inst), label, seed, italian)
      italian.each { |x| f.add(x.code, x.field, "in the Italian translation: #{x.message}", **x.detail.except(:seeds), rule: "it-#{x.detail[:rule]}", seed: x.detail[:seeds]&.first) }
      f
    end

    # The Italian layer of one instance: what the student reads with the translation open must not hold the key either (§4.2 rule 5). The key is
    # looked for in the Italian text of the key option (a choice) and in the target key; the supports, the hints and the stored-order phrases
    # are read as the Italian they are.
    def scan_italian(layer, target_text, label, seed, f)
      display = layer["display"]
      answer = layer["answer"]
      return unless display.is_a?(Hash) && !answer.nil?

      @target_key = target_text
      return unless Answers.shape_problems(@unit.component, answer, display).empty?

      leaks(display, answer, layer, label, seed, f)
      support_leaks(display, answer, layer, label, seed, f)
      ItemChecks.method_words(display, "#{label}/display", @unit.skill, f, seed: seed)
      stored_order(display, layer, label, seed, f) if STORED_ORDER_COMPONENTS.include?(@unit.component)
      hint_leaks(display, answer, layer, label, seed, f) if @unit.body["kind"] == "practice_item"
    end

    def run(inst, label:, seed:, generated:, layered: false)
      f = Findings.new
      display = inst["display"]
      answer = inst["answer"]
      unless display.is_a?(Hash) && !answer.nil?
        f.add("E-GEN-SCHEMA", label, "an instance has a display object and an answer", rule: "shape", seed: seed)
        return f
      end

      keys = Answers.display_keys(display)
      keys.each { |path, name| f.add("E-DISPLAY-KEY", "#{label}/display#{path}", "the display carries a field that reveals the answer (#{name})", seed: seed) }
      SchemaCheck.generated(inst, f, seed: seed, subject: @subject) if generated && keys.empty? && !layered
      size_rules(display, label, seed, f)
      problems = Answers.shape_problems(@unit.component, answer, display)
      problems.each { |p| f.add("E-GEN-SCHEMA", "#{label}/answer", p, rule: "answer_shape", seed: seed) }
      errors(inst, label, seed, f)
      accept_rules(inst, label, seed, f)
      accept_is_error(inst, label, seed, f)
      accent_direction_rules(display, answer, inst, label, seed, f) if problems.empty?
      choice_rules(display, answer, inst, label, seed, f) if @unit.component == "choice" && problems.empty?
      judge_rows(display, answer, label, seed, f) if @unit.component == "matching" && problems.empty?
      leaks(display, answer, inst, label, seed, f) if problems.empty?
      support_leaks(display, answer, inst, label, seed, f) if problems.empty?
      ItemChecks.method_words(display, "#{label}/display", @unit.skill, f, seed: seed)
      component_fit(answer, inst, label, seed, f)
      steps(inst, label, seed, f) if problems.empty?
      stored_order(display, inst, label, seed, f) if problems.empty? && STORED_ORDER_COMPONENTS.include?(@unit.component)
      formula_space(display, inst, label, seed, f)
      sentence_commas(inst, label, seed, f) if problems.empty? && @unit.component == "normalized_text"
      hint_rules(display, answer, inst, label, seed, f) if problems.empty?
      quote_and_figure(display, label, seed, f)
      if generated && !layered
        Readability.lint_document({ "display" => display, "solution" => inst["solution"], "hints_it" => inst["hints_it"] }.compact, label, f)
      end
      f
    end
    private :run

    # True when the correct option is the longest of its options (W-LONGEST-CORRECT).
    def longest_correct?(inst)
      options = Array(inst.dig("display", "options"))
      key = options.find { |o| o["id"] == inst["answer"].to_s }
      key && options.all? { |o| o["id"] == key["id"] || o["text"].to_s.length < key["text"].to_s.length }
    end

    private
    # ---- the two layers of a bilingual revision (D-402) ------------------------------------------------------

    # @unit becomes the unit as the checks read it (the target text under its legacy `_it` keys, no translation), @italian a twin that reads the
    # Italian layer. The instances of the body stay out: they are layered one by one.
    def layer_unit
      body = @unit.body.except("instances")
      @renamed = Set.new
      target = Units::Unit.new(**@unit.to_h.merge(body: Bilingual.target_layer(body, @lang, "", @renamed)))
      italian = Units::Unit.new(**@unit.to_h.merge(body: Lessons::Bilingual.italian_layer(body)))
      @italian = self.class.new(italian, context: @context, files: @files, subject: @subject)
      @unit = target
    end

    # The target text of the key option of a choice (its R2 `text`), nil for the other components.
    def target_key(inst)
      return unless @unit.component == "choice"

      Array(inst.dig("display", "options")).find { |o| o.is_a?(Hash) && o["id"] == inst["answer"].to_s }&.dig("text")
    end

    # A generated instance is not in item.json: its own pairs, the lint of its Italian texts and of its target-language texts.
    def generated_layers(inst, label, seed, f)
      Bilingual.check(f, inst, lang: @lang, prefix: label, conflicts: false)
      Bilingual.lint_target(f, inst, @lang, known: Bilingual.names(@lang), prefix: label)
      Readability.lint_document({ "display" => inst["display"], "solution" => inst["solution"], "hints_it" => inst["hints_it"] }.compact, label, f)
    end

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
          judge_rows = judge_min_rows
          unless (r >= MIN_CATEGORIES || (r == 2 && l >= judge_rows)) && r < l
            f.add("E-MATCHING-SIZE", "#{label}/display/right", "a classification has 3 or more categories (2 from #{judge_rows} rows) and fewer categories than rows (#{l}), not #{r}", count: r, seed: seed)
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

    # Two categories (a judge) are allowed from MIN_ROWS_TWO_CATEGORIES rows in a diagnosis item and, in a practice item, from
    # practice.judge_min_rows (D-370: a practice matching has at most 4 rows, judges included).
    def judge_min_rows = @unit.body["kind"] == "practice_item" ? Rules.get(:practice, :judge_min_rows) : MIN_ROWS_TWO_CATEGORIES

    # W-MATCHING-JUDGE-ROWS (D-314): with two right options (right or wrong, true or false) an instance with a single
    # odd row lets one option for every row get all rows right but one. The grader no longer calls that nearly
    # correct; the instance should not offer it either.
    def judge_rows(display, answer, label, seed, f)
      right = Array(display["right"]).select { |o| o.is_a?(Hash) }
      return unless right.size == 2

      key = Answers.matching_raw(answer).first or return
      right.each_with_index do |option, i|
        n = key.values.count(option["id"].to_s)
        next if n >= JUDGE_MIN_ROWS

        f.add("W-MATCHING-JUDGE-ROWS", "#{label}/display/right/#{i}",
              "a judge matching has #{n} row#{'s' unless n == 1} of #{option['text'].to_s[0, 30].inspect} in this instance: give every instance at least #{JUDGE_MIN_ROWS} rows of each option, so one option for every row is not all right but one",
              rows: n, seed: seed)
      end
    end

    # ---- error values -----------------------------------------------------------

    def errors(inst, label, seed, f)
      known = @unit.catalogue_codes
      Array(inst["errors"]).each_with_index do |e, i|
        round_to_rules(e, inst, "#{label}/errors/#{i}", seed, f) if e.key?("round_to")
        unreachable_matching_value(e, inst, "#{label}/errors/#{i}", seed, f)
        next if known.include?(e["code"])

        f.add("E-GEN-SCHEMA", "#{label}/errors/#{i}", "the error code #{e['code'].inspect} is not in the item's error_catalogue", rule: "code_not_in_catalogue", seed: seed)
      end
    end

    # A matching widget lets each right entry be picked once (a classification, reuse_right,
    # lets rows share one). An error value that uses one right id twice can never be
    # submitted, so its code never fires (D-145).
    def unreachable_matching_value(error, inst, field, seed, f)
      return unless @unit.component == "matching"
      return if inst.dig("display", "reuse_right") == true

      pairs = Answers.matching_raw(error["value"]).first or return
      rights = pairs.values
      return if rights.uniq.size == rights.size

      f.add("W-ERROR-UNREACHABLE", "#{field}/value", "the error value uses one right-hand id more than once; the widget allows each once, so this value can never fire", seed: seed)
    end

    # round_to (D-135) belongs to number items and must not swallow the key: a rounded
    # correct answer would be graded as the error.
    def round_to_rules(error, inst, field, seed, f)
      if @unit.component != "number"
        f.add("E-GEN-SCHEMA", "#{field}/round_to", "round_to on an error belongs to number items", rule: "round_to_component", seed: seed)
        return
      end
      n = error["round_to"]
      key = Grading::Closed::Numbers.expected_value(inst["answer"])
      declared = Grading::Closed::Numbers.expected_value(error["value"])
      if key.round(n, half: :up) == declared.round(n, half: :up)
        f.add("E-GEN-SCHEMA", "#{field}/round_to", "the key rounds to the same value at #{n} decimals: the error would match a correct rounded answer", rule: "round_to_key", seed: seed)
      end
    rescue ArgumentError, TypeError, ZeroDivisionError
      nil
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

    # The grader tries the key and the accept lists (the item's and the instance's) before the errors: an accepted text that is also a
    # declared error value is graded right, so the error never fires. Compared as the grader reads them (Grading::Closed::Text.same_answer?).
    def accept_is_error(inst, label, seed, f)
      return unless @unit.component == "normalized_text"

      case_sensitive = @unit.body["case_sensitive"] == true
      contractions = Grading::Closed::Contractions.option(@unit.body["subject"], @unit.body["contractions"])
      (Array(@unit.accept) + Array(inst["accept"])).uniq.each do |text|
        Array(inst["errors"]).each_with_index do |e, i|
          next unless e.is_a?(Hash) && e["value"].is_a?(String) && text.is_a?(String)
          next unless Grading::Closed::Text.same_answer?(text, e["value"], case_sensitive: case_sensitive, contractions: contractions)

          f.add("E-ACCEPT-IS-ERROR", "#{label}/errors/#{i}/value", "the error value #{e['value'].inspect} is also an accepted text: the grader checks accept first, so this wrong answer would be graded right", seed: seed)
        end
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

    # The direction of an accent is never tested (D-296): no two options that differ only by it, and no declared
    # error value that is the key up to it (the grader would call the answer correct, so the code could never fire).
    def accent_direction_rules(display, answer, inst, label, seed, f)
      fold = ->(t) { Grading::Closed::Text.fold_direction(Grading::Closed::Text.normalize(Answers.plain(t).to_s)) }
      case @unit.component
      when "choice"
        options = Array(display["options"])
        options.combination(2).each do |a, b|
          next if Answers.plain(a["text"]) == Answers.plain(b["text"]) || fold.(a["text"]) != fold.(b["text"])

          f.add("E-ACCENT-DIRECTION", "#{label}/display/options", "options #{a['id']} and #{b['id']} differ only in the direction of an accent", seed: seed)
        end
      when "normalized_text"
        return unless answer.is_a?(String)

        keys = ([ answer ] + Array(inst["accept"])).map { |k| fold.(k) }
        Array(inst["errors"]).each_with_index do |e, i|
          next unless e["value"].is_a?(String) && keys.include?(fold.(e["value"]))

          f.add("E-ACCENT-DIRECTION", "#{label}/errors/#{i}/value", "the error value is the key up to the direction of an accent, so it can never be hit", seed: seed)
        end
      end
    end

    # ---- leaks ---------------------------------------------------------------

    # Strings the student reads outside the stem (and outside the options for a
    # choice): table cells, captions, figure text.
    def readable_strings(display, include_stem:, include_options:)
      Canonical.strings(display).reject do |path, _|
        path == "/quote/text" || path == "/quote/ref" || SUPPORT_PATH.match?(path) ||
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
        needles = key ? [ key["text"], @target_key ].compact : []
        scope = readable_strings(display, include_stem: true, include_options: false)
        # The item's own prompt is read with every instance (D-081).
        scope += prefixed(readable_strings(prompt, include_stem: true, include_options: false), "prompt")
      else
        needles = Answers.key_texts(component, answer, accept: @unit.accept + Array(inst["accept"]))
        needles += ordering_texts(display, answer) + matching_texts(display, answer)
        scope = readable_strings(display, include_stem: false, include_options: false)
        scope += prefixed(readable_strings(prompt, include_stem: false, include_options: false), "prompt")
        [ [ display["stem_it"], "#{label}/display/stem_it" ], [ prompt["stem_it"], "#{label}/prompt/stem_it" ] ].each do |stem, field|
          # A cloze's bracketed cue right after the gap, "___ (swim)", is the material, not a leak (D-110).
          text = component == "normalized_text" ? stem.to_s.gsub(/«[^»]*»/, " ").gsub(/_{2,}\s*\([^)]*\)/, " ___ ") : stem.to_s
          next unless needles.any? { |n| Answers.contains?(text, n) }

          f.add("W-ANSWER-IN-STEM", field, "the expected answer appears in the instruction", seed: seed)
        end
      end
      passage_leak(needles, label, seed, f) if component == "choice"
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

    # A long key option stated word for word in the testlet passage (D-094). Short keys (a name
    # in the story) are too common in a passage to be an error.
    def passage_leak(needles, label, seed, f)
      return if @passage.to_s.empty?

      needle = needles.find { |n| Answers.plain(n).length >= PASSAGE_LEAK_MIN_CHARS && Answers.contains?(@passage, n) }
      return unless needle

      f.add("E-SOLUTION-IN-DISPLAY", "#{label}/passage_it", "the key option appears word for word in the passage (#{needle.to_s[0, 30].inspect})", seed: seed)
    end

    # ---- the supports: answer format and steps (D-216) -----------------------------

    # The student reads answer_format_it and steps_it with every instance (the item's own, and
    # the instance's in its display). Neither may state the key or a declared error value: a
    # format example that is the answer, or the answer of a typical error, gives the item away.
    def support_leaks(display, answer, inst, label, seed, f)
      texts = support_texts(@unit.body, "#{@unit.path}") + support_texts(display, "#{label}/display")
      return if texts.empty?

      needles = support_needles(display, answer, inst)
      texts.each do |field, text|
        needle = needles.find { |n| Answers.contains?(text, n, min: support_min) }
        next unless needle

        f.add("E-SUPPORT-LEAK", field, "the answer format or the steps state the key or a declared error value (#{needle.to_s[0, 30].inspect})", seed: seed)
      end
    end

    # A short numeric key or error value (12, 5) is exactly what a format example states, so
    # numbers have no length floor here (whole-token match: 12 is not found in 123).
    def support_min = %w[number fraction].include?(@unit.component) ? 1 : Answers::MIN_LEAK_CHARS

    def support_texts(hash, base)
      out = []
      out << [ "#{base}/answer_format_it", hash["answer_format_it"] ] if hash["answer_format_it"].is_a?(String)
      Array(hash["steps_it"]).each_with_index { |t, i| out << [ "#{base}/steps_it/#{i}", t ] if t.is_a?(String) }
      out
    end

    # The key and every error value of the instance, as the leak scan reads them.
    def support_needles(display, answer, inst)
      values = [ [ answer, true ] ] + Array(inst["errors"]).map { |e| [ e["value"], false ] }
      values.flat_map do |value, key|
        if @unit.component == "choice"
          option = Array(display["options"]).find { |o| o["id"] == value.to_s }
          [ option && option["text"].to_s, (@target_key if key) ].compact
        else
          accept = key ? @unit.accept + Array(inst["accept"]) : []
          Answers.key_texts(@unit.component, value, accept: accept, min: support_min) + ordering_texts(display, value) + matching_texts(display, value)
        end
      end.uniq
    rescue ArgumentError, TypeError
      []
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

    THOUSANDS = /(?<![\d.,])[1-9]\d{0,2}(?:\.\d{3})+(?!\d)/
    NUMBER = %r{[-−]?\d+(?:\s*/\s*\d+|[.,]\d+)?}

    def steps(inst, label, seed, f)
      final = inst.dig("solution", "final").to_s
      case @unit.component
      when "number", "fraction"
        expected = Answers.rational(inst["answer"].is_a?(Hash) ? { "n" => inst["answer"]["n"], "d" => inst["answer"]["d"] } : inst["answer"])
        text = final.delete("$").gsub("{,}", ",").gsub(/\\d?frac\{(\d+)\}\{(\d+)\}/, '\1/\2')
        # "5.300,00 €": read the dot as the thousands separator as well as a decimal point.
        grouped = text.gsub(THOUSANDS) { |g| g.delete(".") }
        values = [ text, grouped ].uniq.flat_map { |t| t.scan(NUMBER) }.filter_map { |t| Answers.rational(t.tr("−", "-").delete(" ")) }
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

    # ---- the solution points at the stored order (W-SOLUTION-STORED-ORDER) ----------------

    # The options of a choice, the rows of a matching and the steps of an ordering are shuffled for every student
    # (Diagnosis::Rekey, practice instances, items/matching.js): a solution, final or hint that says «dall'alto»,
    # «la prima frase», «l'opzione b» or names l1, r2, e3 reads a list that is not on the student's screen.
    STORED_ORDER_COMPONENTS = %w[choice matching ordering].freeze
    ORDINAL = "prima|seconda|terza|quarta|quinta|penultima|ultima"
    ROW_NOUN = "frase|opzione|riga|risposta|alternativa"
    # A place word counts only near a word for a row of the list (never «a destra» of a figure or a column).
    LIST_NOUN = "rig(?:a|he)|elenco|lista|opzion[ei]|frasi?|voci?|risposta|risposte|elementi|elemento|passi|passo"
    PLACE = "in alto|in basso|a sinistra|a destra"
    # «la prima guerra mondiale» is quiet: only «prima» followed by a word for a row, and not of a passage («la prima frase del testo»).
    STORED_ORDER_POSITION = Regexp.union(
      /\bdall'alto\b/, /\bdal basso\b/,
      /\bnell'ordine\s+(?:delle\s+(?:righe|opzioni|frasi|risposte)|dell'elenco)\b/,
      /\bnell'ordine\s+in\s+cui\s+(?:ti\s+)?(?:sono\s+)?(?:elencat|mostrat|presentat|scritt)\w*/,
      /\b(?:#{ORDINAL})\s+(?:#{ROW_NOUN})\b(?!\s+(?:del|dello|della|dei|nel|nella)\s+(?:testo|brano|passo|paragrafo|citazione|poesia|lettera|versi?|strofa|canto|periodo))/,
      /\b(?:#{LIST_NOUN})\b[^.;:!?]{0,25}\b(?:#{PLACE})\b/, /\b(?:#{PLACE})\b[^.;:!?]{0,25}\b(?:#{LIST_NOUN})\b/,
      /\b(?:opzione|risposta|alternativa|scelta|lettera)\s+[a-e](?=\s*[).,;:!?»"']|\s*\z)/
    )

    def stored_order(display, inst, label, seed, f)
      solution = inst["solution"].is_a?(Hash) ? inst["solution"] : {}
      ids = stored_order_ids(display)
      texts = Array(solution["steps"]).each_with_index.filter_map { |s, i| [ "#{label}/solution/steps/#{i}/text_it", s["text_it"] ] if s.is_a?(Hash) }
      texts << [ "#{label}/solution/final", solution["final"] ]
      hints = inst["hints_it"] ? [ label, inst["hints_it"] ] : [ @unit.path, @unit.body["hints_it"] ]
      Array(hints.last).each_with_index { |h, i| texts << [ "#{hints.first}/hints_it/#{i}", h ] }
      texts.each do |field, text|
        next unless text.is_a?(String)

        found = stored_order_phrase(text, ids) or next
        f.add("W-SOLUTION-STORED-ORDER", field,
              "the text points at the stored order (#{found.inspect}): the options, rows and steps are shuffled for every student, so name the option by its text, never by its place, letter or id",
              seed: seed)
      end
    end

    def stored_order_ids(display)
      %w[options left right elements].flat_map { |k| Array(display[k]).filter_map { |o| o["id"].to_s if o.is_a?(Hash) } }
    end

    def stored_order_phrase(text, ids)
      plain = text.gsub(/\$[^$]*\$/, " ")
      lower = plain.unicode_normalize(:nfkc).downcase.tr("\u2019", "'")
      return lower[STORED_ORDER_POSITION] if lower.match?(STORED_ORDER_POSITION)

      # An id with a digit (o1, l1, r2, e3) is a token of its own, written as it is stored; a lone letter only as «a)».
      ids.each do |id|
        pattern = id.match?(/\d/) ? /(?<![[:alnum:]_])#{Regexp.escape(id)}(?![[:alnum:]_])/ : (/(?:\A|\s)#{Regexp.escape(id)}\)/ if id.size == 1)
        hit = pattern && plain[pattern]
        return hit.strip if hit
      end
      nil
    end

    # ---- a mark after a formula, commas of a sentence key (W-MATH-SPACE-PUNCT, W-SENTENCE-COMMA-VARIANTS) -------------------

    # The texts of the display, the solution and the instance's hints, each with its path: a formula there that ends in a spacing command
    # right before a mark shows a gap before the mark (the page glues the mark itself).
    def formula_space(display, inst, label, seed, f)
      texts = Canonical.strings(display, "#{label}/display") + Canonical.strings(inst["solution"], "#{label}/solution") + Canonical.strings(inst["hints_it"], "#{label}/hints_it")
      texts.each do |field, text|
        FormulaSpace.spaced(text).each do |tex|
          f.add("W-MATH-SPACE-PUNCT", field, FormulaSpace.message(tex, field), seed: seed)
        end
      end
    end

    # The grader keeps commas and semicolons inside a text (only the trailing marks are stripped, Grading::Closed::Text.normalize), so the
    # key «No salimos, ya que llovía.» marks «No salimos ya que llovía.» wrong. A sentence key with one needs an accept entry that is the
    # same sentence with fewer of them (the instance's accept or the item's), or the student who writes it as it reads is graded wrong.
    SENTENCE_END = /[.!?]\z/
    COMMA_MARKS = /[,;]/

    def sentence_commas(inst, label, seed, f)
      key = inst["answer"]
      return unless key.is_a?(String) && key.strip.match?(SENTENCE_END) && key.strip.include?(" ") && key.match?(COMMA_MARKS)

      case_sensitive = @unit.body["case_sensitive"] == true
      read = ->(t) { Grading::Closed::Text.normalize(t.to_s, case_sensitive: case_sensitive) }
      bare = ->(t) { read.(read.(t).gsub(COMMA_MARKS, "")) }
      marks = ->(t) { read.(t).scan(COMMA_MARKS).size }
      return if (Array(@unit.accept) + Array(inst["accept"])).any? { |a| a.is_a?(String) && bare.(a) == bare.(key) && marks.(a) < marks.(key) }

      f.add("W-SENTENCE-COMMA-VARIANTS", "#{label}/answer",
            "#{label}: the key #{key.strip[0, 60].inspect} has a comma or semicolon and the grader compares them, so the same sentence with the comma left out or elsewhere is graded wrong: add the sentence without it to accept (the instance's or the item's)",
            seed: seed)
    end

    # ---- hints of a practice instance (A2.4) ---------------------------------------

    # Effective hints: the instance's own, else the item's. E-HINTS when a practice instance has
    # none, or when hints sit on an instance of another kind. E-HINT-KEY (number, fraction,
    # expression, normalized_text): a hint holds a key text that the display does not already
    # show, so numbers taken from the display are allowed. W-HINT-OPTION (choice): a hint names
    # the key option. Ordering and matching have no scan (reviewer point 12).
    def hint_rules(display, answer, inst, label, seed, f)
      if @unit.body["kind"] != "practice_item"
        f.add("E-HINTS", "#{label}/hints_it", "hints belong to practice items only", seed: seed) unless inst["hints_it"].nil?
        return
      end
      hints = Array(inst["hints_it"] || @unit.body["hints_it"]).select { |h| h.is_a?(String) }
      return f.add("E-HINTS", "#{label}/hints_it", "a practice instance has hints: its own hints_it or the item's", seed: seed) if hints.empty?

      hint_leaks(display, answer, inst, label, seed, f, hints: hints)
    end

    # The hints that state the key (E-HINT-KEY) or name the key option (W-HINT-OPTION); the Italian layer of a bilingual item is scanned too.
    def hint_leaks(display, answer, inst, label, seed, f, hints: nil)
      hints ||= Array(inst["hints_it"] || @unit.body["hints_it"]).select { |h| h.is_a?(String) }
      return if hints.empty?

      case @unit.component
      when "choice" then option_hints(display, answer, hints, label, seed, f)
      when "number", "fraction", "expression", "normalized_text" then key_hints(display, answer, inst, hints, label, seed, f)
      end
    end

    def key_hints(display, answer, inst, hints, label, seed, f)
      shown = Canonical.strings(display).map(&:last).join(" ") + " " + @unit.body["prompt"].to_h.slice("stem_it", "table", "quote").to_json
      needles = Answers.key_texts(@unit.component, answer, accept: @unit.accept + Array(inst["accept"]), min: support_min)
                       .reject { |n| Answers.contains?(shown, n, min: support_min) }
      hints.each_with_index do |hint, i|
        needle = needles.find { |n| Answers.contains?(hint, n, min: support_min) }
        next unless needle

        f.add("E-HINT-KEY", "#{label}/hints_it/#{i}", "the hint states the key (#{needle.to_s[0, 30].inspect}): a hint points at the next step, never at the answer", seed: seed)
      end
    rescue ArgumentError, TypeError
      nil
    end

    def option_hints(display, answer, hints, label, seed, f)
      key = Array(display["options"]).find { |o| o["id"] == answer.to_s } or return
      texts = [ key["text"].to_s, @target_key ].compact
      hints.each_with_index do |hint, i|
        next unless texts.any? { |t| Answers.contains?(hint, t) }

        f.add("W-HINT-OPTION", "#{label}/hints_it/#{i}", "the hint names the correct option (#{key['text'].to_s[0, 30].inspect}); the reviewer judges", seed: seed)
      end
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
