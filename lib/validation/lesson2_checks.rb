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
    def call(md, subject:, context:)
      findings = Findings.new
      source = Lessons::Parser.normalize(md)
      if source.bytesize > rule(:max_bytes)
        findings.add("E-LESSON-SIZE", "/lesson.md", "lesson.md is #{source.bytesize / 1024} KB (at most #{rule(:max_bytes) / 1024} KB)", bytes: source.bytesize)
        return Outcome.new(findings: findings, parsed: nil)
      end
      parsed = Lessons::Parser2.call(source, findings)
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
      LessonChecks.refs(fm, context, findings)
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
      def initialize(parsed, subject, context, findings)
        @parsed = parsed
        @body = parsed.body
        @subject = subject
        @context = context
        @findings = findings
        @cards = @body["cards"]
        @ids = @cards.to_h { |c| [ c["id"], c ] }
        @catalogue = catalogue
        @ctx = Lessons::Blocks::Context.new(subject: subject, findings: findings, catalogue: @catalogue, resolver: method(:field_line))
        @plain = [] # every markup text, for the whole-lesson budgets: [[text, line]]
      end

      def rule(*path) = Rules.get(:lesson2, *path)

      def call
        return unless body_schema

        front_matter_texts
        hero
        structure
        @cards.each_with_index { |card, i| card_checks(card, i) }
        lesson_counts
        whole_text
      end

      def add(code, field, message, line: nil, **detail)
        detail[:line] = line if line
        detail[:rule] ||= "#{code}#{field}"
        @findings.add(code, field, message, **detail)
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
          hit = index["/#{parts.join('/')}"]
          return hit if hit

          parts.pop
        end
        block_line
      end

      # ---- schema -------------------------------------------------------------------------------

      def body_schema
        shape = Banco::Schemas.schema("lesson").validate(Lessons::Parser2.for_schema(@body)).to_a
        shape.first(12).each do |e|
          add("E-SCHEMA", "/body#{e['data_pointer']}", Validation::SchemaCheck.message(e), rule: e["type"].to_s)
        end
        shape.empty?
      end

      # ---- front matter ---------------------------------------------------------------------------

      def front_matter_texts
        fm = @parsed.front_matter
        lines = @parsed.lines
        line_of = ->(key) { Lessons::Parser2.front_line(lines, key) }
        max = rule(:goals_words_max)
        Array(@body["goals_it"]).each_with_index do |g, i|
          n = Lessons::Blocks.words(g)
          add("E-LESSON-BLOCK", "/front_matter/goals_it/#{i}", "a goal has #{n} words (at most #{max})", line: line_of.call("goals_it")) if n > max
          add("E-LESSON-BLOCK", "/front_matter/goals_it/#{i}", "a goal starts with a verb in bold: **Risolvere** ...", line: line_of.call("goals_it")) unless g.match?(/\A\*\*[^*]+\*\*/)
          markup_field("/front_matter/goals_it/#{i}", g, line_of.call("goals_it") || 1, false)
        end
        markup_field("/front_matter/why_it", fm["why_it"], line_of.call("why_it") || 1, false)
        n = sentences(fm["why_it"])
        lo, hi = rule(:why_sentences)
        add("W-LESSON-WHY", "/front_matter/why_it", "why_it has #{n} sentence(s) (#{lo} to #{hi})", line: line_of.call("why_it")) unless (lo..hi).cover?(n)
        return unless fm["book_it"]

        words = Lessons::Blocks.words(fm["book_it"])
        add("E-LESSON-BOOK", "/front_matter/book_it", "book_it has #{words} words (at most #{rule(:book_extra_words)})", line: line_of.call("book_it")) if words > rule(:book_extra_words)
        markup_field("/front_matter/book_it", fm["book_it"], line_of.call("book_it") || 1, false)
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
        if !extra && (n = Lessons::Blocks.prose_words(card)) > rule(:max_card_words)
          running = Lessons::Blocks.words(card["title_it"])
          over = blocks.find { |b| (running += Lessons::Blocks.prose(b).sum { |t| Lessons::Blocks.words(t) }) > rule(:max_card_words) }
          add("E-CARD-WORDS", base, "the card has #{n} words of prose (at most #{rule(:max_card_words)})", line: (over || card)["line"])
        end
        add("E-LESSON-ICON", "#{base}/icon", "#{card['icon']} is not an icon of #{@subject} (config/banco/icons.yml)", line: line) unless Lessons::Icons.allowed?(@subject, card["icon"])
        add("E-LESSON-ROLE", "#{base}/tone", "#{card['tone']} is not a colour role of #{@subject}'s palette", line: line) if card["tone"] && !Lessons::Palette.role?(@subject, card["tone"])
        role_contract(card, base, line, extra)
        blocks.each_with_index { |b, j| block_checks(b, "#{base}/blocks/#{j}", card) }
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
        @ctx.at(path, block["line"]) do
          case block["type"]
          when "check" then Lessons::Blocks::Check.check(block, @ctx)
          when "example" then Lessons::Blocks::Example.check(block, @ctx)
          when "try" then Lessons::Blocks::Try.check(block, @ctx)
          when "more" then more_checks(block, path, card)
          else Lessons::Blocks::Simple.check(block, @ctx)
          end
        end
        markup_block(block, path)
        block_diagrams(block, path)
        return unless block["type"] == "more"

        block["blocks"].each_with_index { |b, k| block_checks(b, "#{path}/blocks/#{k}", card) }
      end

      def more_checks(block, path, _card)
        words = block["blocks"].sum { |b| Lessons::Blocks.prose(b).sum { |t| Lessons::Blocks.words(t) } }
        max = rule(:more_words)
        @ctx.add("E-LESSON-EXTRA-WORDS", "", "a more block has #{words} words (at most #{max})", rule: "more-words-#{path}") if words > max
      end

      def block_diagrams(block, path)
        line = block["line"]
        case block["type"]
        when "diagram" then diagram_checks(block["diagram"], "#{path}/diagram", line, "")
        when "schema" then diagram_checks(block["schema"], "#{path}/schema", line, "")
        when "cases"
          block["cases"].each_with_index { |c, k| diagram_checks(c["diagram"], "#{path}/cases/#{k}/diagram", line, "/cases/#{k}/diagram") if c["diagram"] }
        when "example" then diagram_checks(block["diagram"], "#{path}/diagram", line, "/diagram") if block["diagram"]
        when "try"
          block["exercises"].each_with_index { |e, k| diagram_checks(e["diagram"], "#{path}/exercises/#{k}/diagram", line, "/exercises/#{k}/diagram") if e["diagram"] }
        end
      end

      # +line+: the line of the block (or of the front matter key) and +yaml+ where the diagram sits in the block's YAML.
      def diagram_checks(diagram, path, line, yaml = nil)
        Lessons::Diagrams.check(diagram, subject: @subject).each do |f|
          at = yaml.nil? ? line : field_line(line, "#{yaml}#{f.path}")
          add(f.code, "#{path}#{f.path}", f.message, line: at, rule: f.rule + path)
        end
      end

      # ---- markup, links, roles, readability ----------------------------------------------------------

      def markup_block(block, path)
        Lessons::Blocks.markup_fields(block).each do |sub, text, lists|
          next if block["type"] == "check" && block["component"] == "span_select" && sub == "text_it"

          line = case block["type"]
          when "text" then block["line"]
          when "callout" then block["line"] + 1
          when "summary" then block["line"] + 1 + sub.split("/").last.to_i
          else field_line(block["line"], sub)
          end
          markup_field("#{path}/#{sub}", text, line, lists)
        end
      end

      def markup_field(field, text, line, lists_allowed)
        @plain << [ text, line ]
        begin
          blocks = Lessons::Markup.raw_blocks(text, line_offset: line, roles: true)
          unless lists_allowed || (blocks.size == 1 && blocks.first.type == :p)
            add("E-LESSON-MARKUP", field, "line #{line}: one paragraph is expected here, not a list or several paragraphs", line: line, rule: "inline-only")
            return
          end
          Lessons::Markup.roles_used(text, line_offset: line).each do |name, at|
            add("E-LESSON-ROLE", field, "line #{at}: #{name} is not a colour role of #{@subject}'s palette", line: at, rule: "role-#{name}-#{field}") unless Lessons::Palette.role?(@subject, name)
          end
          Lessons::Markup.links_used(text, line_offset: line).each { |kind, target, at| link(field, kind, target, at) }
          lint(field, blocks)
        rescue Lessons::Markup::Refused => e
          add("E-LESSON-MARKUP", field, "line #{e.line}: #{e.construct}", line: e.line, rule: "markup-#{field}", construct: e.construct)
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
      def lint(field, blocks)
        blocks.each do |b|
          units = b.type == :p ? [ [ b.text, b.line ] ] : b.items.flat_map { |it| ([ [ it[:text], it[:line] ] ] + it[:subs].map { |s| [ s, it[:line] ] }) }
          units.each_with_index do |(text, line), k|
            plain = unmark(text)
            tmp = Findings.new
            Readability.lint(plain, field: field, role: :text, findings: tmp)
            tmp.each do |f|
              next if SKIP_IN_LINT.include?(f.code)

              detail = f.detail.merge(line: line)
              detail[:rule] = "#{detail[:rule]}-#{line}-#{k}"
              @findings.add(f.code, f.field, f.message, **detail)
            end
          end
        end
      end

      # [[role:text]] and [text](scheda:x) shown as text.
      def unmark(text)
        text.gsub(/\[\[[a-z-]+:(.*?)\]\](?!\])/m, '\1').gsub(/\[([^\[\]]*)\]\((?:scheda|argomento):[^()]*\)/, '\1')
      end

      # At most 3 roles with an icon in a card's running text (A6).
      def icon_roles(card, base, line)
        used = {} # role => the line where the card first uses it
        card["blocks"].each do |b|
          next if %w[legend check try].include?(b["type"])

          Lessons::Blocks.markup_fields(b).each do |sub, text, _|
            at = b["type"] == "text" ? b["line"] : field_line(b["line"], sub)
            Lessons::Markup.roles_used(text, line_offset: at).each { |name, l| used[name] ||= l }
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

      def visuals(core, extra)
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

        prose = @cards.select { |c| c["level"] == "core" }.flat_map { |c| Lessons::Blocks.prose_of(c) }
        text = Readability.strip_markup(unmark(prose.join(" ")).gsub(Readability::MATH, " m "))
        sentences = Readability.sentences_of(text)
        n = sentences.sum { |s| Readability.count_words(s) }
        index = Readability.gulpease(text, sentences, n)
        min = rule(:min_gulpease)
        add("W-GULPEASE", "/cards", "Gulpease index #{index.round} on the core prose (below #{min})", index: index.round) if index && n >= Rules.get(:readability, :min_gulpease_words) && index < min
      end
    end
  end
end
