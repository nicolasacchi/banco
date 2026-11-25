# frozen_string_literal: true

module Validation
  # The synchronous checks of a banco.lesson/2 revision (A12 step 1): the parse (Lessons::Parser2), the front matter, the
  # budgets of A3, readability per paragraph and per card, the colour roles and icons, the diagrams and schemas, the
  # inline checks, the leaks. Nothing is written. Thresholds: config/banco/validation_rules.yml, block lesson2.
  # The render check in the server's Chrome (A12 step 2) is R4's.
  module Lesson2Checks
    Outcome = Struct.new(:findings, :parsed, keyword_init: true) do
      def body = parsed&.body
    end

    SKIP_IN_LINT = %w[W-GULPEASE].freeze
    SECTION_RANK = { "idea" => 0, "example" => 0, "mistakes" => 1, "try" => 2, "summary" => 3 }.freeze

    module_function

    def rule(*path) = Rules.get(:lesson2, *path)

    # +md+: the text of lesson.md; +subject+: the subject key of the submit.
    def call(md, subject:, context:, allow_reserved: false)
      findings = Findings.new
      source = Lessons::Parser.normalize(md)
      if source.bytesize > rule(:max_bytes)
        findings.add("E-LESSON-SIZE", "/lesson.md", "lesson.md is #{source.bytesize / 1024} KB (at most #{rule(:max_bytes) / 1024} KB)", bytes: source.bytesize)
        return Outcome.new(findings: findings, parsed: nil)
      end
      parsed = Lessons::Parser2.call(source, findings, allow_reserved: allow_reserved)
      return Outcome.new(findings: findings, parsed: nil) unless parsed

      front = parsed.front_matter
      front_checks(front, subject, context, findings)
      Run.new(parsed, subject, context, findings).call if parsed.body
      front_lines(parsed, findings)
      Outcome.new(findings: findings, parsed: parsed)
    end

    def front_checks(fm, subject, context, findings)
      if fm["subject"].is_a?(String) && fm["subject"] != subject
        findings.add("E-SCHEMA", "/front_matter/subject", "the lesson is for #{fm['subject']}, submitted for #{subject}", rule: "subject")
      end
      if fm["skills"].is_a?(Array) && fm["uses"].is_a?(Array) && (both = fm["skills"] & fm["uses"]).any?
        findings.add("E-SCHEMA", "/front_matter/uses", "#{both.join(', ')} is in skills: uses names other skills", rule: "uses_in_skills")
      end
      LessonChecks.skills_known(fm, subject, context, findings)
      LessonChecks.refs(fm, subject, context, findings)
      if (target = Lessons::Lang.target(subject)) # D-402: the pairs of the front matter need the flag, and the subject's own language
        flag_pairs(fm, "/front_matter", fm["bilingual"] == true ? target : nil, target) { |field, why| findings.add("E-LANG-BILINGUAL-FLAG", field, why, rule: "flag-#{field}") }
      end
      required = begin
        Array(Rules.get(:lang, :bilingual_required))
      rescue KeyError
        []
      end
      return unless required.include?(subject) && fm["bilingual"] != true

      findings.add("E-LANG-BILINGUAL-REQUIRED", "/front_matter/bilingual", "a new #{subject} lesson is written in the target language with its Italian translation: bilingual: true", rule: "bilingual-required")
    end

    # Every pair `foo_en|es` + `foo_it` under +node+ that the flag does not allow: any pair in a lesson that is not bilingual (+lang+ nil), a pair in another
    # language than the subject's +target+ in one that is. Yields (field, why). Fragments and the figures' own pairs (dialogue, mirror) are not pairs.
    def flag_pairs(node, pointer, lang, target, sentence = false, &emit)
      case node
      when Hash
        sentence = Lessons::Bilingual.in_sentence?(node, sentence)
        node.each_key do |key|
          if (s = key.is_a?(String) && node.key?("component") && key.match(/\A#{Lessons::Bilingual::SENTENCE}_(en|es)\z/)) # a check's own sentence: a target text with no `_it` beside it
            names = { "en" => "English", "es" => "Spanish" }
            emit.call("#{pointer}/#{key}", lang ? "#{key} is in #{names[s[1]]} and the subject teaches #{names[target]}" : "#{key} belongs to a bilingual lesson (bilingual: true in the front matter)") if lang.nil? || s[1] != lang
            next
          end
          m = key.is_a?(String) && key.match(/\A(.+)_(en|es)\z/) or next
          base = m[1]
          next if !node.key?("#{base}_it") || Lessons::Bilingual::EXEMPT.include?(base) || Lessons::Bilingual::FIELDS[:native].include?(base)
          next if base == "text" && (sentence || node["component"] == "span_select" || Lessons::Bilingual::FIELDS[:fragments].match?(pointer))
          next if lang && m[2] == lang

          names = { "en" => "English", "es" => "Spanish" }
          why = lang ? "#{key} is in #{names[m[2]]} and the subject teaches #{names[target]}" : "#{key} and #{base}_it are a pair, and the lesson is not bilingual (bilingual: true in the front matter)"
          emit.call("#{pointer}/#{key}", why)
        end
        node.each { |k, v| flag_pairs(v, "#{pointer}/#{k}", lang, target, sentence, &emit) if v.is_a?(Hash) || v.is_a?(Array) }
      when Array then node.each_with_index { |v, i| flag_pairs(v, "#{pointer}/#{i}", lang, target, sentence, &emit) if v.is_a?(Hash) || v.is_a?(Array) }
      end
    end

    # A finding about a front matter member names the line of that member.
    def front_lines(parsed, findings)
      findings.each do |f|
        next if f.detail[:line]

        key = f.field[%r{\A/front_matter/([a-z_]+)}, 1] or next
        line = Lessons::Parser2.front_line(parsed.lines, key) or next
        f.detail[:line] = line
      end
    end

    # One pass over a parsed body.
    class Run
      # D-402: a bilingual lesson (`bilingual: true`, english or spanish) is checked as two layers. The budgets, the block checks and the target-language lint read
      # the TARGET layer through the `_it` slots they have always read (@body: Parser2.target_view, the pairs folded as the student is served them); the
      # Italian lint reads the Italian layer (@italian: Bilingual.italian_layer); and the pairs themselves (completeness, shape, language) are
      # Validation::Bilingual's. A legacy lesson has one layer, @body, and is checked exactly as before.
      def initialize(parsed, subject, context, findings)
        @parsed = parsed
        @raw = parsed.body
        @lang = Lessons::Parser2.bilingual_lang(parsed.front_matter)
        @body = @lang ? (target_layer || @raw) : @raw
        @italian = @lang ? Lessons::Bilingual.italian_layer(@raw) : nil
        @subject = subject
        @context = context
        @findings = findings
        @cards = @body["cards"]
        @ids = @cards.to_h { |c| [ c["id"], c ] }
        @catalogue = catalogue
        @ctx = Lessons::Blocks::Context.new(subject: subject, findings: findings, catalogue: @catalogue, resolver: method(:field_line), references: context.method(:reference_body), pages: context.method(:page))
        @ctx.lang = @lang
        @plain = [] # every markup text, for the whole-lesson budgets: [[text, line]]
        @target = Lessons::Lang.target(subject)
        @glossary = Array(@body["glossary"]).to_h { |g| [ g["term_it"].to_s.downcase, g ] }
        @glossary_it = Array(@italian && @italian["glossary"]).to_h { |g| [ g["term_it"].to_s.downcase, g ] }
        @known_words = known_words
        # The target fields that have only their Italian (a lone `_it` of a bilingual lesson: E-LANG-PAIR-ORPHAN says it all) and the target fields that are form
        # material (no level lint): the pointers are the body's.
        @orphans = @lang ? Lessons::Bilingual.pairs(@raw, @lang).select { |_p, _b, target, italian| target.nil? && !italian.nil? }.map(&:first).to_set : Set.new
        @forms = @lang ? Lessons::Bilingual.material_pointers(@raw, @lang) : Set.new
      end

      def rule(*path) = Rules.get(:lesson2, *path)

      def call
        return unless body_schema

        flag_checks
        front_matter_texts
        hero
        structure
        @cards.each_with_index { |card, i| card_checks(card, i) }
        target_keys
        bilingual_checks if @lang
        lesson_counts
        whole_text
      end

      # A lone `_it` is read in the target layer as if it were the target text (its field is the `_en|_es` pointer): everything said about it there (E-READ, W-LANG-LEVEL,
      # W-LANG-SPAN-REDUNDANT, ...) is a repeat of E-LANG-PAIR-ORPHAN, which is reported by the pairs and not here.
      def add(code, field, message, line: nil, **detail)
        return if @lang && !@italian_pass && orphan?(field)

        detail[:line] = line if line
        detail[:rule] ||= "#{code}#{field}"
        @findings.add(code, field, message, **detail)
      end

      def orphan?(field)
        return false if @orphans.empty?

        at = field.to_s.sub(%r{\A/front_matter}, "")
        @orphans.any? { |o| at == o || at.start_with?("#{o}/") }
      end

      # The error codes of the lesson's skills (nil when none of them is known).
      def catalogue
        skills = Array(@body["skills"]) + Array(@body["uses"])
        found = skills.filter_map { |k| @context.skill(k) }
        return nil if found.empty?

        found.flat_map { |s| Array(s["errors"]).map { |e| e["code"] } }.compact.to_set
      end

      # The line of a field of a block: the key's own line in the block's YAML, else the block's body or its opening line.
      def field_line(block_line, pointer)
        return block_line if pointer.to_s.empty?

        index = @parsed.field_lines[block_line]
        return block_line + 1 if index.nil? || index.empty?

        parts = "/#{pointer}".split("/").reject(&:empty?)
        until parts.empty?
          at = "/#{parts.join('/')}"
          hit = (@lang && !@italian_pass && index[at.gsub(/_it(?=\/|\z)/, "_#{@lang}")]) || index[at] # a bilingual finding is about the target text, the line above its Italian
          return hit if hit

          parts.pop
        end
        block_line
      end

      # ---- schema -------------------------------------------------------------------------------

      def body_schema
        shape = Lessons::Parser2.body_errors(@raw, @subject, @lang)
        shape.first(12).each do |e|
          add("E-SCHEMA", "/body#{e['data_pointer']}", Validation::SchemaCheck.message(e), rule: e["type"].to_s)
        end
        shape.empty?
      end

      # ---- bilingual (D-402) ----------------------------------------------------------------------

      # The target layer of the body. A target text whose Italian is missing is given itself as its Italian first, so that the checks that read the
      # `_it` slot never meet a hole (the missing translation is E-LANG-PAIR-MISSING's).
      def target_layer
        Lessons::Parser2.target_view(Lessons::Parser2.pad_pairs(@raw, @lang), @lang)
      rescue StandardError
        nil
      end

      # The pairs of a language lesson that the flag does not allow: a sibling in a revision without the flag, or in another language than the subject's.
      def flag_checks
        return unless @target

        Validation::Lesson2Checks.flag_pairs(@raw.slice("cards", "parts"), "", @lang, @target) do |field, why|
          add("E-LANG-BILINGUAL-FLAG", field, why, line: pair_line(field), rule: "flag-#{field}")
        end
        return if @lang

        Validation::Bilingual.marker_pointers(@raw.slice("cards")).each do |field|
          add("E-LANG-BILINGUAL-FLAG", field, "#{Lessons::Bilingual::MARKER} is for a bilingual lesson (it says that the form material has no translation): add bilingual: true", line: pair_line(field), rule: "flag-material-#{field}")
        end
      end

      # The line of a pointer into the body's pairs: a front matter key, a part, a card heading, a block, a field of a block's YAML.
      def pair_line(pointer)
        segs = pointer.split("/").reject(&:empty?)
        if segs.first == "cards" && (card = @raw["cards"][segs[1].to_i])
          node = card
          line = card["line"]
          at = 2
          while segs[at] == "blocks" && (inner = node["blocks"]&.[](segs[at + 1].to_i))
            node = inner
            line = inner["line"]
            at += 2
          end
          rest = segs.drop(at)
          return line if rest.empty? || node.equal?(card)

          case node["type"]
          when "text" then line
          when "callout" then rest.first.to_s.start_with?("title") ? line : line + 1
          when "summary" then line + 1 + rest.last.to_i
          else field_line(line, "/#{rest.join('/')}")
          end
        elsif segs.first == "parts" then @parsed.parts[segs[1].to_i]&.fetch(:line, nil)
        elsif segs.first
          Lessons::Parser2.front_line(@parsed.lines, segs.first) || Lessons::Parser2.front_line(@parsed.lines, segs.first.sub(/_(en|es)\z/, "_it"))
        end
      end

      # The pairs: Validation::Bilingual walks them (completeness, shape, language, conflicts, one scope at a time: the front matter, the parts, a card's own
      # texts, each block), the colour roles are mine. A scope is passed at its true place in the body (`wrap`), so that the pointers and R2 fields are the body's.
      def bilingual_checks
        front = @raw.slice(*%w[title_it title_en title_es goals_it goals_en goals_es why_it why_en why_es glossary])
        pairs_check(front, "/front_matter")
        pairs_check({ "parts" => @raw["parts"] }, "") if @raw["parts"]
        @raw["cards"].each_with_index do |card, i|
          pairs_check(wrap([ "cards", i ], card.except("blocks")), "")
          card["blocks"].each_with_index { |block, j| block_pairs(block, [ "cards", i, "blocks", j ]) }
        end
        role_parity
        italian_pass
      end

      def block_pairs(block, path)
        pairs_check(wrap(path, block.except("blocks")), "")
        Array(block["blocks"]).each_with_index { |inner, k| block_pairs(inner, path + [ "blocks", k ]) } if block["type"] == "more"
      end

      # +node+ at +path+ (["cards", 1, "blocks", 0]) inside an otherwise empty body: an index is padded with nils, so pointers are the body's.
      def wrap(path, node) = path.reverse.reduce(node) { |inner, seg| seg.is_a?(Integer) ? Array.new(seg) + [ inner ] : { seg => inner } }

      def pairs_check(doc, prefix)
        line = ->(pointer) { pair_line(pointer) }
        if defined?(Validation::Bilingual) && Validation::Bilingual.respond_to?(:check)
          Validation::Bilingual.check(@findings, doc, lang: @lang, prefix: prefix, line: line, known: @known_words.fetch(@lang, []))
        else # until Validation::Bilingual lands (slice 2): completeness only
          Lessons::Bilingual.pairs(doc, @lang).each do |pointer, base, target, italian|
            next if target && italian

            code = target ? "E-LANG-PAIR-MISSING" : "E-LANG-PAIR-ORPHAN"
            add(code, "#{prefix}#{pointer}", "#{target ? 'the Italian translation of' : 'the target-language text of'} #{base} is missing", line: line.call(pointer), rule: "#{code}-#{prefix}#{pointer}")
          end
        end
      end

      # The same colour roles in a text and in its translation, so that the student maps the colours across the two languages (§2.3).
      def role_parity
        Lessons::Bilingual.pairs(@raw, @lang).each do |pointer, _base, target, italian|
          next unless target.is_a?(String) && italian.is_a?(String) && (target.include?("[[") || italian.include?("[[") || target.include?("\\role") || italian.include?("\\role"))

          roles = ->(text) { Lessons::Markup.roles_used(text).map(&:first).sort }
          mine = roles.call(target)
          theirs = roles.call(italian)
          next if mine == theirs

          add("E-LANG-PAIR-SHAPE", pointer, "the colour roles of the text (#{mine.join(', ').presence || 'none'}) and of its Italian (#{theirs.join(', ').presence || 'none'}) differ: mark the same roles in both", line: pair_line(pointer), rule: "pair-roles-#{pointer}")
        rescue Lessons::Markup::Refused
          next # the markup checks name it
        end
      end

      # The Italian layer: the markup, the colour roles, the links, the language spans and the Italian lint of the translations (the target layer's own lint ran
      # with the blocks). Its lines are the lines of the Italian keys.
      def italian_pass
        @italian_pass = true
        lines = @parsed.lines
        line_of = ->(key) { Lessons::Parser2.front_line(lines, key) || 1 }
        Array(@italian["goals_it"]).each_with_index { |g, i| markup_field("/front_matter/goals_it/#{i}", g, line_of.call("goals_it"), false, layer: :italian) }
        markup_field("/front_matter/why_it", @italian["why_it"], line_of.call("why_it"), false, layer: :italian) if @italian["why_it"]
        Array(@italian["glossary"]).each_with_index do |g, i|
          %w[def_it example_it].each { |k| markup_field("/front_matter/glossary/#{i}/#{k}", g[k], line_of.call("glossary"), false, layer: :italian) if g[k] }
        end
        @italian["cards"].each_with_index { |card, i| card["blocks"].each_with_index { |b, j| italian_block(b, "/cards/#{i}/blocks/#{j}") } }
      ensure
        @italian_pass = false
      end

      def italian_block(block, path)
        markup_block(block, path, layer: :italian)
        block_diagrams(block, path, plain_only: true) # the Italian text of a figure's alt, notes and questions is plain text too
        Lessons::Blocks::Try.labelled_prompts(block).each do |pointer, _|
          add("W-CHECK-LABEL-DOUBLED", "#{path}/#{pointer}", Lessons::Blocks::Try::LABEL_MESSAGE, line: field_line(block["line"], pointer), rule: "label-doubled-#{path}/#{pointer}-it")
        end
        Array(block["blocks"]).each_with_index { |inner, k| italian_block(inner, "#{path}/blocks/#{k}") } if block["type"] == "more"
      end

      # The common given names that are no W-LANG-LEVEL (Validation::Bilingual.names, config/banco/lexicon/{en,es}_names.txt), none until that lands.
      def common_names(lang)
        return [] unless @lang

        @names ||= {}
        @names[lang] ||= defined?(Validation::Bilingual) && Validation::Bilingual.respond_to?(:names) ? Validation::Bilingual.names(lang).to_a : []
      end

      # ---- front matter ---------------------------------------------------------------------------

      def front_matter_texts
        fm = @parsed.front_matter
        lines = @parsed.lines
        line_of = ->(key) { (@lang && Lessons::Parser2.front_line(lines, key.sub(/_it\z/, "_#{@lang}"))) || Lessons::Parser2.front_line(lines, key) }
        max = rule(:goals_words_max)
        Array(@body["goals_it"]).each_with_index do |g, i|
          n = Lessons::Blocks.words(g)
          add("E-LESSON-BLOCK", slot("/front_matter/goals_it/#{i}"), "a goal has #{n} words (at most #{max})", line: line_of.call("goals_it")) if n > max
          add("E-LESSON-BLOCK", slot("/front_matter/goals_it/#{i}"), "a goal starts with a verb in bold: **Risolvere** ...", line: line_of.call("goals_it")) unless g.match?(/\A\*\*[^*]+\*\*/)
          markup_field("/front_matter/goals_it/#{i}", g, line_of.call("goals_it") || 1, false)
        end
        glossary_checks(line_of.call("glossary") || 1)
        markup_field("/front_matter/why_it", @body["why_it"], line_of.call("why_it") || 1, false)
        n = sentences(@body["why_it"])
        lo, hi = rule(:why_sentences)
        add("W-LESSON-WHY", slot("/front_matter/why_it"), "#{slot('why_it')} has #{n} sentence(s) (#{lo} to #{hi})", line: line_of.call("why_it")) unless (lo..hi).cover?(n)
        return unless fm["book_it"]

        words = Lessons::Blocks.words(fm["book_it"])
        add("E-LESSON-BOOK", "/front_matter/book_it", "book_it has #{words} words (at most #{rule(:book_extra_words)})", line: line_of.call("book_it")) if words > rule(:book_extra_words)
        markup_field("/front_matter/book_it", fm["book_it"], line_of.call("book_it") || 1, false, layer: (:italian if @lang))
      end

      def sentences(text)
        Readability.sentences_of(Readability.strip_markup(text.to_s.gsub(Readability::MATH, " m "))).size
      end

      def hero
        return unless @body["hero"]

        diagram_checks(@body["hero"], "/hero", Lessons::Parser2.front_line(@parsed.lines, "hero"))
      end

      # ---- structure ------------------------------------------------------------------------------

      def structure
        core = @cards.select { |c| c["level"] == "core" }
        extra = @cards.select { |c| c["level"] == "extra" }
        lo, hi = rule(:core_cards)
        add("E-LESSON-CARDS", "/cards", "the lesson has #{core.size} core cards (#{lo} to #{hi})") unless (lo..hi).cover?(core.size)
        add("E-LESSON-CARDS", "/cards", "the lesson has #{extra.size} extra cards (at most #{rule(:extra_cards_max)})") if extra.size > rule(:extra_cards_max)

        counts = core.group_by { |c| c["role"] }
        { "mistakes" => 1, "try" => 1, "summary" => 1 }.each do |role, want|
          have = counts.fetch(role, [])
          if have.size != want
            at = have[want]&.dig("line")
            add("E-LESSON-CARDS", "/cards", "the lesson has #{have.size} #{role} cards (exactly #{want})", line: at, rule: "count-#{role}")
          end
        end
        { "idea" => [ 1, 9 ], "example" => [ 1, 3 ] }.each do |role, (min, max)|
          n = counts.fetch(role, []).size
          add("E-LESSON-CARDS", "/cards", "the lesson has #{n} #{role} cards (#{min} to #{max})", rule: "count-#{role}") unless (min..max).cover?(n)
        end
        previous = nil
        core.each do |c|
          rank = SECTION_RANK.fetch(c["role"])
          if previous && rank < previous[0]
            add("E-LESSON-CARDS", "/cards/#{previous[2]['n'] - 1}", "order: idea and example cards, then mistakes, try, summary (the #{previous[1]} card comes before the #{c['role']} card at line #{c['line']})", line: previous[2]["line"], rule: "order-#{c['n']}")
          end
          previous = [ rank, c["role"], c ] if previous.nil? || rank >= previous[0]
        end
        first = core.find { |c| %w[idea example].include?(c["role"]) }
        add("E-LESSON-CARDS", "/cards/#{first['n'] - 1}", "the first idea card comes before the first example card", line: first["line"], rule: "first-idea") if first && first["role"] != "idea"
        summary = core.find { |c| c["role"] == "summary" }
        add("E-LESSON-CARDS", "/cards/#{summary['n'] - 1}", "the summary is the last core card", line: summary["line"], rule: "summary-last") if summary && summary != core.last
        extra.each do |c|
          add("E-LESSON-CARDS", "/cards/#{c['n'] - 1}", "an extra card has role idea or example, not #{c['role']}", line: c["line"], rule: "extra-role-#{c['n']}") unless %w[idea example].include?(c["role"])
          add("E-LESSON-CARDS", "/cards/#{c['n'] - 1}", "extra cards come after the summary", line: c["line"], rule: "extra-order-#{c['n']}") if core.any? { |k| k["n"] > c["n"] }
        end
      end

      # ---- one card -------------------------------------------------------------------------------

      def card_checks(card, i)
        base = "/cards/#{i}"
        line = card["line"]
        blocks = card["blocks"]
        extra = card["level"] == "extra"
        lo, hi = rule(:blocks_per_card)
        add("E-CARD-BLOCKS", base, "the card has #{blocks.size} blocks (#{lo} to #{hi})", line: line) unless (lo..hi).cover?(blocks.size)
        # wave 2 (rules version 9): one source, one dialogue, one reveal with options or one oral per card
        blocks.filter_map { |b| Lessons::Blocks.single_kind(b) }.tally.each do |kind, n|
          add("E-CARD-BLOCKS", base, "the card has #{n} #{kind.tr('_', ' ')} blocks (at most 1)", line: line, rule: "one-#{kind}") if n > 1 && rule(:one_per_card).include?(kind)
        end
        if !extra && (n = Lessons::Blocks.prose_words(card)) > rule(:max_card_words)
          running = Lessons::Blocks.words(card["title_it"])
          over = blocks.find { |b| (running += Lessons::Blocks.prose(b).sum { |t| Lessons::Blocks.words(t) }) > rule(:max_card_words) }
          add("E-CARD-WORDS", base, "the card has #{n} words of prose (at most #{rule(:max_card_words)})", line: (over || card)["line"])
        end
        target_lint("#{base}/title_#{@lang}", @lang, target_plain(card["title_it"]), line) if @lang
        add("E-LESSON-ICON", "#{base}/icon", "#{card['icon']} is not an icon of #{@subject} (config/banco/icons.yml)", line: line) unless Lessons::Icons.allowed?(@subject, card["icon"])
        add("E-LESSON-ROLE", "#{base}/tone", "#{card['tone']} is not a colour role of #{@subject}'s palette", line: line) if card["tone"] && !Lessons::Palette.role?(@subject, card["tone"])
        role_contract(card, base, line, extra)
        blocks.each_with_index { |b, j| block_checks(b, "#{base}/blocks/#{j}", card) }
        Lessons::Blocks::Truth.card(card, base, @ctx)
        Lessons::Blocks::Example.blank_data(card, base, @ctx)
        icon_roles(card, base, line)
      end

      def role_contract(card, base, line, extra)
        types = card["blocks"].map { |b| b["type"] }
        case card["role"]
        when "idea"
          add("E-CARD-NO-VISUAL", base, "an idea card needs a visual: a diagram, schema, procedure or cases with a diagram (fold the idea into an example card when none is honest)", line: line) unless card["blocks"].any? { |b| Lessons::Blocks.visual?(b) }
        when "example"
          add("E-LESSON-CARDS", base, "an example card holds an example block", line: line, rule: "example-block") unless types.include?("example")
        when "mistakes"
          n = types.count("mistake")
          lo, hi = rule(:mistakes)
          add("W-LESSON-MISTAKES", base, "the mistakes card has #{n} mistake block(s) (at least #{lo})", line: line) if n < lo
          add("E-LESSON-BLOCK", base, "the mistakes card has #{n} mistake blocks (at most #{hi})", line: line, rule: "mistakes-max") if n > hi
        when "try"
          add("E-LESSON-EXERCISES", base, "the try card holds one try block", line: line, rule: "try-block") unless types.count("try") == 1
        when "summary"
          add("E-LESSON-SUMMARY", base, "the summary card holds one summary block", line: line, rule: "summary-block") unless types.count("summary") == 1
          add("E-LESSON-MAP", base, "the summary card needs one schema (a concept map, a flow or a table)", line: line) unless types.count("schema") == 1
        end
        exclusive = { "try" => "try", "mistake" => "mistakes", "summary" => "summary" }
        card["blocks"].each_with_index do |b, j|
          want = exclusive[b["type"]]
          add("E-LESSON-BLOCK", "#{base}/blocks/#{j}", "a #{b['type']} block belongs in a #{want} card, not in #{card['role']}", line: b["line"], rule: "role-#{base}/#{j}") if want && card["role"] != want
        end
        _ = extra
      end

      # ---- one block ------------------------------------------------------------------------------

      def block_checks(block, path, card)
        @ctx.card_level = card["level"]
        @ctx.at(path, block["line"]) do
          case block["type"]
          when "check" then Lessons::Blocks::Check.check(block, @ctx)
          when "example" then Lessons::Blocks::Example.check(block, @ctx)
          when "try" then Lessons::Blocks::Try.check(block, @ctx)
          when "more" then more_checks(block, path, card)
          when "source", "reveal", "oral" then Lessons::Blocks::Docs.check(block, @ctx)
          when "dialogue" then Lessons::Blocks::Dialogue.check(block, @ctx)
          when "page" then Lessons::Blocks::FreePage.check(block, @ctx, card: card, body: @body)
          when "code" then Lessons::Blocks::Code.check(block, @ctx)
          else Lessons::Blocks::Simple.check(block, @ctx)
          end
        end
        markup_block(block, path)
        math_block(block, path)
        block_diagrams(block, path)
        return unless block["type"] == "more"

        block["blocks"].each_with_index { |b, k| block_checks(b, "#{path}/blocks/#{k}", card) }
      end

      # The formulas of a math block (tex, and the tex of each line) are read for chemistry symbols like the formulas of a text.
      def math_block(block, path)
        return unless block["type"] == "math"

        ([ [ "tex", block["tex"] ] ] + block["lines"].to_a.each_with_index.map { |l, i| [ "lines/#{i}/tex", l["tex"] ] }).each do |sub, tex|
          chem_formula("#{path}/#{sub}", tex, field_line(block["line"], sub)) if tex.is_a?(String)
        end
      end

      def more_checks(block, path, _card)
        words = block["blocks"].sum { |b| Lessons::Blocks.prose(b).sum { |t| Lessons::Blocks.words(t) } }
        max = rule(:more_words)
        @ctx.add("E-LESSON-EXTRA-WORDS", "", "a more block has #{words} words (at most #{max})", rule: "more-words-#{path}") if words > max
      end

      # +plain_only+: the Italian layer's pass, where a figure has no check but the plain-text one.
      def block_diagrams(block, path, plain_only: false)
        line = block["line"]
        # the own figure of a select check (a check block, a step blank or an exercise check)
        Lessons::Blocks::Truth.located_checks(block, path).each do |c, at, yaml|
          diagram_checks(c["diagram"], "#{at}/diagram", line, "#{yaml.empty? ? '' : "/#{yaml}"}/diagram", plain_only: plain_only) if c["component"] == "select"
        end
        case block["type"]
        when "diagram" then diagram_checks(block["diagram"], "#{path}/diagram", line, "", plain_only: plain_only)
        when "schema" then diagram_checks(block["schema"], "#{path}/schema", line, "", plain_only: plain_only)
        when "cases"
          block["cases"].each_with_index { |c, k| diagram_checks(c["diagram"], "#{path}/cases/#{k}/diagram", line, "/cases/#{k}/diagram", plain_only: plain_only) if c["diagram"] }
        when "example" then diagram_checks(block["diagram"], "#{path}/diagram", line, "/diagram", plain_only: plain_only) if block["diagram"]
        when "try"
          block["exercises"].each_with_index do |e, k|
            next unless e["diagram"]

            static_figure(e["diagram"], "#{path}/exercises/#{k}/diagram", line, "/exercises/#{k}/diagram") unless plain_only
            diagram_checks(e["diagram"], "#{path}/exercises/#{k}/diagram", line, "/exercises/#{k}/diagram", plain_only: plain_only)
          end
        end
      end

      # L7 (WAVE2 1.4): a figure in an exercise of the try card is static: no cursor to read with, no slider to move, no toggle (types of wave 2).
      def static_figure(diagram, path, line, yaml)
        return if Lessons::Types.entry(:diagram, diagram["type"])&.fetch("family", "core") == "core"

        %w[read try toggle controls run].each do |key|
          add("E-LESSON-BLOCK", "#{path}/#{key}", "a figure in an exercise is static (L7): #{key} belongs to the figures of the idea cards", line: field_line(line, "#{yaml}/#{key}"), rule: "static#{path}/#{key}") if diagram.key?(key)
        end
      end

      # +line+: the line of the block (or of the front matter key) and +yaml+ where the diagram sits in the block's YAML.
      def diagram_checks(diagram, path, line, yaml = nil, plain_only: false)
        (plain_only ? Lessons::Diagrams.plain_text_findings(diagram) : Lessons::Diagrams.check(diagram, subject: @subject)).each do |f|
          at = yaml.nil? ? line : field_line(line, "#{yaml}#{f.path}")
          add(f.code, "#{path}#{f.path}", f.message, line: at, rule: f.rule + path)
        end
      end

      # ---- markup, links, roles, readability ----------------------------------------------------------

      def markup_block(block, path, layer: nil)
        Lessons::Blocks.markup_fields(block).each do |sub, text, lists|
          next if block["type"] == "check" && block["component"] == "span_select" && sub == "text_it" # text_en and text_es are not Italian markup at all
          next if @lang && layer != :italian && block["type"] == "dialogue" && sub.end_with?("/gloss_it") # the gloss is Italian: the Italian pass reads it, never the target layer

          line = case block["type"]
          when "text" then block["line"]
          when "callout" then block["line"] + 1
          when "summary" then block["line"] + 1 + sub.split("/").last.to_i
          else field_line(block["line"], sub)
          end
          markup_field("#{path}/#{sub}", text, line, lists, layer: layer)
        end
      end

      # +layer+: :target (the text of a bilingual lesson in its language, in the `_it` slot of the view: its field is named `_en`/`_es`), :italian (its translation), nil
      # for a lesson that is not bilingual (the one layer, Italian prose with spans of the language it teaches).
      def markup_field(field, text, line, lists_allowed, layer: nil)
        layer ||= :target if @lang
        field = slot(field) if layer == :target
        @plain << [ text, line ]
        begin
          inline = lists_allowed == :inline # input_before / input_after: one inline run, never block markup
          blocks = Lessons::Markup.raw_blocks(text, line_offset: line, roles: true, inline: inline)
          unless lists_allowed || (blocks.size == 1 && blocks.first.type == :p)
            add("E-LESSON-MARKUP", field, "line #{line}: one paragraph is expected here, not a list or several paragraphs", line: line, rule: "inline-only")
            return
          end
          Lessons::Markup.roles_used(text, line_offset: line, inline: inline).each do |name, at|
            add("E-LESSON-ROLE", field, "line #{at}: #{name} is not a colour role of #{@subject}'s palette", line: at, rule: "role-#{name}-#{field}") unless Lessons::Palette.role?(@subject, name)
          end
          Lessons::Markup.links_used(text, line_offset: line, inline: inline).each { |kind, target, at| link(field, kind, target, at) }
          spans(field, text, line, layer, inline: inline)
          formula_space(field, text, line)
          lint(field, blocks, layer)
        rescue Lessons::Markup::Refused => e
          add("E-LESSON-MARKUP", field, "line #{e.line}: #{e.construct}", line: e.line, rule: "markup-#{field}", construct: e.construct)
        end
      end

      # The field name of a text of the target layer: the view holds it in the `_it` slot, the author wrote it under `_en` / `_es`.
      def slot(field) = @lang ? field.gsub(/_it(?=\/|\z)/, "_#{@lang}") : field

      # W-MATH-SPACE-PUNCT (D-335): a formula that ends in a spacing command right before a mark shows a gap before the mark.
      def formula_space(field, text, line)
        Validation::FormulaSpace.spaced(text).each_with_index do |tex, k|
          add("W-MATH-SPACE-PUNCT", field, Validation::FormulaSpace.message(tex, "line #{line}"), line: line, rule: "math-space-punct-#{field}-#{k}")
        end
      end

      def link(field, kind, target, at)
        if kind == "scheda"
          add("E-LESSON-LINK", field, "line #{at}: scheda:#{target} names no card (a card needs id=#{target} in its heading)", line: at, rule: "link-#{target}-#{field}") unless @ids.key?(target) && @ids[target]["id"] == target && explicit_id?(target)
        elsif !@context.topic?(target)
          add("E-LESSON-LINK", field, "line #{at}: argomento:#{target} is not a topic of the subject's course map", line: at, rule: "link-#{target}-#{field}")
        end
      end

      def explicit_id?(id) = !id.match?(/\Ac\d+\z/) || @parsed.cards.any? { |c| c.dig(:tag, :id) == id }

      # Readability per paragraph or list item, on the text S reads (colour spans and links shown as their words).
      def lint(field, blocks, layer = nil)
        blocks.each do |b|
          units = b.type == :p ? [ [ b.text, b.line ] ] : b.items.flat_map { |it| ([ [ it[:text], it[:line] ] ] + it[:subs].map { |s| [ s, it[:line] ] }) }
          units.each_with_index do |(text, line), k|
            if layer == :target # the target language has its own lint: short sentences, words a learner knows (D-402)
              target_lint(field, @lang, target_plain(text), line)
              next
            end
            plain = unmark(text, layer)
            tmp = Findings.new
            Readability.lint(plain, field: field, role: :text, findings: tmp, quotes: layer == :italian)
            tmp.each do |f|
              next if SKIP_IN_LINT.include?(f.code)

              detail = f.detail.merge(line: line)
              detail[:rule] = "#{detail[:rule]}-#{line}-#{k}"
              @findings.add(f.code, f.field, f.message, **detail)
            end
          end
        end
      end

      # [[role:text]] and [text](scheda:x) shown as text; the words of another language, a code span and (in a language subject) a role
      # span are out of the Italian lint (D-266): each stands for one word. In the translation of a bilingual lesson a role span is Italian words.
      def unmark(text, layer = nil) = Lessons::Lang.split(text, target: layer == :italian ? nil : @target).first

      # A text of the target layer as the target lint reads it: its words, the quoted Italian ([[it:..]]) and the formulas out. A span of a language or of code
      # counts one word (read as ` m `); a full stop that closes it, `[[es:¿Dónde estás?]]`, still ends the sentence.
      def target_plain(text)
        one_word = text.gsub(/\[\[(?:it|en|es|la|code):(.*?)\]\](?!\])/m) { Regexp.last_match(1).match?(/[.!?…]\s*\z/) ? " m . " : " m " }
        plain = Lessons::Lang.split(one_word, target: nil).first
        Readability.strip_markup(plain.gsub(Readability::MATH, " m "))
      end

      # ---- the text layer (D-266): language spans, role spans of a language subject, code spans, glossary words ---------------------------------

      def spans(field, text, line, layer = nil, inline: false)
        Lessons::Markup.each_node(text, line_offset: line, target: layer == :italian ? nil : @target, inline: inline) do |n, at|
          case n["t"]
          when "lang"
            language_span(field, n["lang"], n["v"], at, layer, plain_words: true)
          when "role"
            next unless n["lang"] && n["lang"] != "it"

            language_span(field, n["lang"], plain_of(n), at, layer)
          when "math"
            chem_formula(field, n["v"], at)
          when "gloss"
            terms = layer == :italian ? @glossary_it : @glossary
            add("E-LESSON-BLOCK", field, "line #{at}: [[g:#{n['term']}]] is not a term of the lesson's glossary (front matter glossary:)", line: at, rule: "gloss-#{n['term']}-#{field}") unless terms.key?(n["term"].downcase)
          end
        end
      end

      MHCHEM_SUBJECTS = %w[chemistry biology].freeze

      # \ce{} and \pu{} are for chemistry and biology (the browser loads mhchem for them only); a symbol inside \ce{} or \mathrm{} is an
      # element symbol, case-exact (E-CHEM-SYMBOL; \mathrm is read only where \ce is allowed: a unit in a math lesson is not a symbol).
      def chem_formula(field, tex, at)
        mhchem = Lessons::ChemSymbols.mhchem?(tex)
        add("E-LESSON-MARKUP", field, "line #{at}: \\ce and \\pu are for chemistry and biology lessons", line: at, rule: "mhchem-#{field}-#{at}") if mhchem && !MHCHEM_SUBJECTS.include?(@subject)
        return unless mhchem || MHCHEM_SUBJECTS.include?(@subject)

        Lessons::ChemSymbols.unknown(tex).each do |symbol|
          add("E-CHEM-SYMBOL", field, "line #{at}: #{symbol} is not an element symbol (case-exact, chem/elements)", line: at, rule: "chem-symbol-#{symbol}-#{field}-#{at}", symbol: symbol)
        end
      end

      def plain_of(node)
        Array(node["children"]).map { |c| c["t"] == "text" ? c["v"] : plain_of(c) }.join
      end

      # +plain_words+: a [[en:..]] span (words of a language), not a colour role span that happens to be in that language.
      def language_span(field, lang, text, at, layer = nil, plain_words: false)
        if lang == "it" # D-402: Italian words quoted inside target-language text
          add("E-LESSON-LANG", field, "line #{at}: a [[it:...]] span belongs in the target-language text of a bilingual lesson, not here", line: at, rule: "lang-span-it-#{field}") unless layer == :target
          return
        end
        unless Lessons::Lang.taught?(@subject, lang)
          add("E-LESSON-LANG", field, "line #{at}: a [[#{lang}:...]] span in a #{@subject} lesson (#{@subject} does not teach #{LANGUAGE_NAMES[lang]})", line: at, rule: "lang-span-#{lang}-#{field}")
        end
        if layer == :target && plain_words && lang == @lang && !quoted_unit?(text)
          add("W-LANG-SPAN-REDUNDANT", field, "line #{at}: [[#{lang}:#{text}]] is a #{LANGUAGE_NAMES[lang]} span in a text that is all #{LANGUAGE_NAMES[lang]}: leave it plain unless the lesson then discusses that unit (glossary, teaches_#{lang})", line: at, rule: "span-redundant-#{field}-#{at}")
        end
        # a span of the target text is a quoted unit: the level lint leaves it to the glossary and teaches_*; in the Italian text of a bilingual lesson it is a form quoted on purpose
        target_lint(field, lang, text, at, level: !@lang && layer != :target)
      end

      # A unit the lesson discusses: all its words are in the glossary or in teaches_en / teaches_es.
      def quoted_unit?(text)
        words = text.to_s.downcase.scan(Lessons::Lexicon::WORD)
        words.any? && (words - @known_words.fetch(@lang, [])).empty?
      end

      LANGUAGE_NAMES = { "en" => "English", "es" => "Spanish", "la" => "Latin", "it" => "Italian" }.freeze
      # The words of a check that are its material, never a claim of the lesson (no W-ABSOLUTE): the text around the box of a typed gap, the sentence, an option, a row,
      # a tile or an item. The prompt, the hints and the explanation are the lesson's own words.
      MATERIAL_FIELD = %r{/(?:input_before|input_after|sentence_\w+|(?:options|elements|left|right|tiles|items)/\d+/text_\w+)\z}
      # The wrong side of a mistake block is a form misspelled on purpose («¿Havéis…?», «cantió»): the level is not read there, in whichever pass reaches it.
      DELIBERATE_FORM = %r{/wrong_(?:en|es)\z}

      # The lint of words of another language (the target-language set, WAVE2 1.8): a short sentence, and words a learner of the lesson knows. A bilingual
      # lesson's target text (@lang) is read by Validation::Bilingual.target_report: sentences split after `.»`, `;` and a lone letter, the level also for form material,
      # quoted forms, spans and pieces of words, and the absolute words (W-ABSOLUTE). +level+ false: no word of the level, no absolute word.
      # +cell+: a cell of a table of forms, read for the level only (it is no sentence: no cap, no absolute word).
      def target_lint(field, lang, text, at, level: true, cell: false)
        level &&= !field.match?(DELIBERATE_FORM)
        max = rule(:target_sentence_words)
        known = @known_words.fetch(lang, []) + common_names(lang)
        if @lang
          # Form material (an option, a row, the sentence with its blank) is read for the level as the student reads it, in the target language alone: the words of
          # the key, the accepted answers and the error values of its exercise are the forms it teaches (Validation::Bilingual.own_words).
          form = cell || @forms.include?(field)
          known += Validation::Bilingual.own_words(@raw, field, lang).to_a if form
          report = Validation::Bilingual.target_report(lang, text, known: known, level: level, absolute: !form && !MATERIAL_FIELD.match?(field))
          long = cell ? 0 : report[:long]
          unknown = report[:unknown]
          add("W-ABSOLUTE", field, "an absolute word (#{report[:absolute]}) needs a counterexample check", line: at, rule: "absolute-#{field}-#{at}", word: report[:absolute]) if report[:absolute]
        else
          long = Readability.sentences_of(text.to_s).map { |t| Readability.count_words(t) }.max.to_i
          unknown = Lessons::Lexicon.unknown(lang, text, known: known)
        end
        add("E-READ", field, "a #{LANGUAGE_NAMES.fetch(lang, lang)} sentence has #{long} words (at most #{max})", line: at, rule: "target_sentence_words-#{field}-#{at}", words: long) if long > max
        return if unknown.empty?

        add("W-LANG-LEVEL", field, "#{LANGUAGE_NAMES.fetch(lang, lang)} words outside the first #{rule(:target_vocabulary_top)} (and the glossary and teaches_#{lang}): #{unknown.first(6).join(', ')}", line: at, rule: "lang-level-#{field}-#{at}", words: unknown)
      end

      # Words the lesson teaches, per language: the glossary's terms and the teaches_en / teaches_es lists, downcased.
      def known_words
        taught = %w[en es].to_h { |l| [ l, Array(@body["teaches_#{l}"]).flat_map { |w| w.to_s.downcase.scan(Lessons::Lexicon::WORD) } ] }
        glossed = @glossary.keys.flat_map { |t| t.scan(Lessons::Lexicon::WORD) }
        taught.transform_values { |w| w + glossed }
      end

      # The dialogue, mirror and word_parts checks already refused a language the subject does not teach, under this block: one fault, one finding.
      def block_owns_language?(at)
        @findings.any? { |f| f.code == "E-LESSON-LANG" && f.field.to_s.start_with?("#{at}/") && f.message.include?("is not a language this subject teaches") }
      end

      # Every key _en, _es or _la of a block holds words of that language: the subject must teach it, it must not be Italian, a figure
      # holds one language besides Italian, and the target-language lint applies.
      def target_keys
        @cards.each_with_index do |card, i|
          card["blocks"].each_with_index do |block, j|
            at = "/cards/#{i}/blocks/#{j}"
            Lessons::Lang.keyed(block).each do |pointer, key, text|
              lang = Lessons::Lang.key_lang(key)
              line = field_line(block["line"], pointer)
              field = "#{at}#{pointer}"
              add("E-LESSON-LANG", field, "#{key} holds #{LANGUAGE_NAMES[lang]} text and #{@subject} does not teach it", line: line, rule: "lang-key-#{field}") unless Lessons::Lang.taught?(@subject, lang) || block_owns_language?(at)
              add("E-LESSON-LANG", field, "#{key} holds Italian words (a key ending in _#{lang} holds #{LANGUAGE_NAMES[lang]} only)", line: line, rule: "lang-italian-#{field}") if %w[en es].include?(lang) && Lessons::Lang.italian?(text)
              target_lint(field, lang, joined_form(key, text), line)
            end
            figures(block).each do |diagram, where|
              langs = Lessons::Lang.languages_in(diagram)
              add("E-LESSON-LANG", "#{at}#{where}", "a figure holds one language besides Italian (#{langs.map { |l| "_#{l}" }.join(', ')})", line: field_line(block["line"], where), rule: "lang-figure-#{at}#{where}") if langs.size > 1
            end
          end
        end
        form_cells
      end

      # A word_parts form is written in split notation (writ|ing, p[ue]d|o): the level is read on the joined word («writing»), never on its pieces («writ»).
      def joined_form(key, text)
        return text unless key.start_with?("form_")

        Lessons::Words.split(text)["word"]
      rescue Lessons::Words::Refused
        text
      end

      # The cells of a table of forms (`translate_material: false` on a table: `header` and `rows` with no Italian) have no `_<lang>` key to be found by: read them for the level.
      def form_cells
        return unless @lang

        Validation::Bilingual.bare_material(@raw, @lang) { |pointer, text| target_lint(pointer, @lang, text, pair_line(pointer), cell: true) }
      end

      # The figures of a block with where they sit in it: [[diagram, "/diagram"]].
      def figures(block)
        out = []
        out << [ block["diagram"], "/diagram" ] if block["diagram"].is_a?(Hash)
        out << [ block["schema"], "/schema" ] if block["schema"].is_a?(Hash)
        block["cases"].to_a.each_with_index { |c, k| out << [ c["diagram"], "/cases/#{k}/diagram" ] if c["diagram"].is_a?(Hash) }
        out
      end

      # The glossary of the front matter: terms once, definitions and examples as short Italian markup.
      def glossary_checks(line)
        seen = {}
        Array(@body["glossary"]).each_with_index do |g, i|
          key = g["term_it"].to_s.downcase
          add("E-LESSON-BLOCK", "/front_matter/glossary/#{i}", "the term #{g['term_it']} is in the glossary twice", line: line, rule: "glossary-twice-#{i}") if seen[key]
          seen[key] = true
          %w[def_it example_it].each do |k|
            next unless g[k]

            markup_field("/front_matter/glossary/#{i}/#{k}", g[k], line, false)
          end
        end
      end

      # At most 3 roles with an icon in a card's running text (A6).
      def icon_roles(card, base, line)
        used = {} # role => the line where the card first uses it
        card["blocks"].each do |b|
          next if %w[legend check try].include?(b["type"])

          Lessons::Blocks.markup_fields(b).each do |sub, text, lists|
            at = b["type"] == "text" ? b["line"] : field_line(b["line"], sub)
            Lessons::Markup.roles_used(text, line_offset: at, inline: lists == :inline).each { |name, l| used[name] ||= l }
          rescue Lessons::Markup::Refused
            nil
          end
        end
        icon = used.select { |name, _| Lessons::Palette.icon_role?(@subject, name) }
        max = rule(:icon_roles_per_card)
        add("E-CARD-ROLES", base, "the card uses #{icon.size} colour roles with an icon in its text (#{icon.keys.join(', ')}; at most #{max})", line: icon.values[max] || line) if icon.size > max
      end

      # ---- the whole lesson -----------------------------------------------------------------------

      def lesson_counts
        core = @cards.select { |c| c["level"] == "core" }
        extra = @cards.select { |c| c["level"] == "extra" }
        outside = core.reject { |c| c["role"] == "try" }
        in_core = outside.sum { |c| count_checks(c) }
        blanks = outside.sum { |c| c["blocks"].sum { |b| b["type"] == "example" ? b["steps"].count { |s| s["blank"] } : 0 } }
        lo, hi = rule(:checks_core)
        add("E-LESSON-CHECKS", "/cards", "the core cards (outside Prova tu) hold #{in_core} checks, step blanks included (#{lo} to #{hi})", rule: "core-count") unless (lo..hi).cover?(in_core)
        add("E-LESSON-CHECKS", "/cards", "the lesson has #{blanks} step blanks (at most #{rule(:blanks_max)})", rule: "blanks") if blanks > rule(:blanks_max)
        in_extra = extra.sum { |c| count_checks(c) }
        add("E-LESSON-CHECKS", "/cards", "the extra cards hold #{in_extra} checks (at most #{rule(:checks_extra_max)})", rule: "extra-count") if in_extra > rule(:checks_extra_max)
        try_checks = core.select { |c| c["role"] == "try" }.sum { |c| c["blocks"].sum { |b| Lessons::Blocks.checks(b).size } }
        add("E-LESSON-CHECKS", "/cards", "Prova tu holds #{try_checks} checks (at most #{rule(:try_checks_max)})", rule: "try-count") if try_checks > rule(:try_checks_max)
        sparse(core)
        apparatus(core)
        visuals(core, extra)
        extra_words(core, extra)
      end

      def count_checks(card)
        card["blocks"].sum { |b| %w[check example].include?(b["type"]) ? Lessons::Blocks.checks(b).size : 0 }
      end

      # Three idea or example cards in a row without a check or a blank.
      def sparse(core)
        run = []
        flush = lambda do
          n = rule(:checks_gap)
          add("W-LESSON-CHECKS-SPARSE", "/cards", "#{run.size} idea or example cards in a row (#{run.map { |c| c['n'] }.join(', ')}) have no check or blank", rule: "sparse-#{run.first['n']}") if run.size >= n
          run = []
        end
        core.each do |c|
          if %w[idea example].include?(c["role"]) && count_checks(c).zero?
            run << c
          else
            flush.call
          end
        end
        flush.call
      end

      # Words open by default beside the prose (quotations, plain versions, reveal prompts and options), and originals closed by default.
      def apparatus(core)
        blocks = core.flat_map { |c| c["blocks"] }
        open_words = blocks.sum { |b| Lessons::Blocks.apparatus_words(b) } + glossary_open_words(core)
        closed = blocks.sum { |b| Lessons::Blocks.closed_original_words(b) }
        add("E-LESSON-APPARATUS-WORDS", "/cards", "the core cards show #{open_words} words of quotations, plain versions and reveal texts by default (at most #{rule(:apparatus_words)})", rule: "open") if open_words > rule(:apparatus_words)
        add("E-LESSON-APPARATUS-WORDS", "/cards", "the core cards hold #{closed} words of originals behind a tap (at most #{rule(:closed_original_words)})", rule: "closed") if closed > rule(:closed_original_words)
      end

      # The glossary lines listed under a card ("Parole di questa scheda") are open by default: each card counts the definitions of its terms.
      def glossary_open_words(core)
        core.sum do |card|
          terms = card_terms(card)
          terms.sum do |t|
            g = @glossary[t.downcase]
            g ? Lessons::Blocks.words(g["def_it"]) + Lessons::Blocks.words(g["example_it"]) : 0
          end
        end
      end

      # The glossary terms a card uses, once each, in the order of first use.
      def card_terms(card)
        terms = []
        Lessons::Blocks.each_block(card).each do |b, _|
          Lessons::Blocks.markup_fields(b).each do |_, text, lists|
            Lessons::Markup.each_node(text, inline: lists == :inline) { |n, _| terms << n["term"] if n["t"] == "gloss" }
          rescue Lessons::Markup::Refused
            nil
          end
        end
        terms.uniq { |t| t.downcase }
      end

      def visuals(core, extra)
        # a card whose only visual is a `source` is a reading card: at most lesson2.card_source_only_visual_max in a lesson
        only_source = core.count { |c| (v = c["blocks"].select { |b| Lessons::Blocks.visual?(b) }).any? && v.all? { |b| b["type"] == "source" } }
        add("E-CARD-NO-VISUAL", "/cards", "#{only_source} cards have a source as their only visual (at most #{rule(:card_source_only_visual_max)})", rule: "source-only") if only_source > rule(:card_source_only_visual_max)
        in_core = core.sum { |c| c["blocks"].sum { |b| Lessons::Blocks.visual_count(b) } }
        in_extra = extra.sum { |c| c["blocks"].sum { |b| Lessons::Blocks.visual_count(b) } } +
                   core.sum { |c| c["blocks"].select { |b| b["type"] == "more" }.sum { |m| m["blocks"].sum { |b| Lessons::Blocks.visual_count(b) } } }
        add("E-LESSON-VISUALS", "/cards", "the core cards hold #{in_core} diagrams, schemas and procedures (at most #{rule(:visuals_core_max)})", rule: "core") if in_core > rule(:visuals_core_max)
        add("E-LESSON-VISUALS", "/cards", "the extra cards and more blocks hold #{in_extra} diagrams, schemas and procedures (at most #{rule(:visuals_extra_max)})", rule: "extra") if in_extra > rule(:visuals_extra_max)
      end

      def extra_words(core, extra)
        n = @body.dig("words", "extra")
        add("E-LESSON-EXTRA-WORDS", "/cards", "the extra depth (more blocks and extra cards) has #{n} words (at most #{rule(:extra_words)})", rule: "total") if n > rule(:extra_words)
        _ = [ core, extra ]
      end

      # Whole-text rules: the 500 core words, bold ratio, page numbers, Gulpease of the core prose.
      def whole_text
        core_words = @body.dig("words", "core")
        add("E-LESSON-WORDS", "/cards", "the core cards have #{core_words} words of prose (at most #{rule(:max_words)})", words: core_words) if core_words > rule(:max_words)

        # the running text: the paragraphs of text and callout blocks (where an author over-bolds); goals are bold by rule
        running = @cards.flat_map { |c| Lessons::Blocks.each_block(c).filter_map { |b, _| b["text_it"] if %w[text callout].include?(b["type"]) } }
        all = running.sum { |t| Lessons::Blocks.words(t) }
        bold = running.sum { |t| t.scan(/\*\*(.+?)\*\*/).sum { |(inner)| Lessons::Blocks.words(inner) } }
        if all.positive? && bold.to_f / all > rule(:max_bold_ratio)
          boldest = @cards.flat_map { |c| Lessons::Blocks.each_block(c).map { |b, _| b } }.select { |b| %w[text callout].include?(b["type"]) }
                          .max_by { |b| b["text_it"].scan(/\*\*(.+?)\*\*/).sum { |(inner)| Lessons::Blocks.words(inner) } }
          add("E-LESSON-BOLD", "/cards", "#{(bold * 100.0 / all).round(1)}% of the words are bold (at most #{(rule(:max_bold_ratio) * 100).round}%): bold only the keywords", ratio: (bold.to_f / all).round(3), line: boldest && boldest["line"] + (boldest["type"] == "callout" ? 1 : 0))
        end
        pattern = Regexp.new(Rules.get(:lesson, :page_pattern), Regexp::IGNORECASE)
        if (hit = (@plain + [ [ @body["title_it"], nil ] ]).find { |t, _| t.to_s.match?(pattern) })
          add("E-LESSON-PAGE", "/cards", "a page number: never name a page of the book", line: hit[1])
        end

        cards = @lang ? @italian["cards"] : @cards # Gulpease is an Italian index: of the translation in a bilingual lesson
        prose = cards.select { |c| c["level"] == "core" }.flat_map { |c| Lessons::Blocks.prose_of(c) }
        text = Readability.strip_markup(unmark(prose.join(" "), (:italian if @lang)).gsub(Readability::MATH, " m "))
        sentences = Readability.sentences_of(text)
        n = sentences.sum { |s| Readability.count_words(s) }
        index = Readability.gulpease(text, sentences, n)
        min = rule(:min_gulpease)
        add("W-GULPEASE", "/cards", "Gulpease index #{index.round} on the core prose (below #{min})", index: index.round) if index && n >= Rules.get(:readability, :min_gulpease_words) && index < min
      end
    end
  end
end
