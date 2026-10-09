# frozen_string_literal: true

module Lessons
  # lesson.md -> the parsed body of banco.lesson/2 (A1, A2). The source is a front matter and then cards: a level-1
  # heading starts a part, a level-2 heading `## Title {ROLE [extra] [icon=NAME] [id=SLUG] [tone=ROLE]}` a card, and
  # inside a card plain text and fenced directives are the blocks. The splitter is fence-aware: a heading counts only
  # at depth 0, so a `## ` line in a YAML block scalar is text of its block.
  #
  # What this refuses is the shape: E-LESSON-PARSE, E-SCHEMA of the front matter, E-LESSON-CARD, E-LESSON-PARTS,
  # E-LESSON-BLOCK (with the line of the construct). Numbers, budgets, semantics and readability are
  # Validation::Lesson2Checks. When anything is refused here, body is nil.
  module Parser2
    ROLES = %w[idea example mistakes try summary].freeze
    HEADING = /\A## (?<title>.+?) \{(?<tag>[^{}]*)\}[ \t]*\z/
    SLUG = /\A[a-z0-9-]{1,32}\z/
    ICON = /\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z/
    ROLE_NAME = /\A[a-z]+(-[a-z]+)*\z/
    FENCE_OPEN = /\A(:{3,4}) (.*)\z/
    FENCE_CLOSE = /\A:{3,4}\z/

    Parsed2 = Struct.new(:front_matter, :body, :cards, :parts, :source, :lines, :body_start, :field_lines, keyword_init: true)

    module_function

    def schema2?(source)
      front = source.to_s.match(/\A---\n(.*?)\n---\n/m)&.[](1)
      !!front&.match?(/^schema:\s*["']?banco\.lesson\/2["']?\s*$/)
    end

    # Returns Parsed2, or nil when there is no front matter to speak of (the finding says why).
    def call(md, findings)
      source = Parser.normalize(md)
      unless source.valid_encoding?
        findings.add("E-LESSON-PARSE", "/", "lesson.md is not valid UTF-8", rule: "encoding")
        return nil
      end
      front, body_start = Parser.front_matter(source, findings)
      return nil unless front

      lines = source.split("\n", -1)
      schema_ok = front_matter_schema(front, lines, findings)
      key_consistent(front, lines, findings)
      cards, parts, field_lines = scan(lines, body_start, findings)
      structure(cards, parts, findings)
      parsed = Parsed2.new(front_matter: front, cards: cards, parts: parts, source: source, lines: lines, body_start: body_start, field_lines: field_lines)
      parsed.body = build_body(front, cards, parts) if schema_ok && !findings.any_error?
      parsed
    end

    # The 1-based line of a front matter key, for findings.
    def front_line(lines, key)
      index = lines.each_with_index.find { |l, i| i.positive? && l.match?(/\A#{Regexp.escape(key)}:/) }&.last
      index && index + 1
    end

    def front_matter_schema(front, lines, findings)
      errors = Banco::Schemas.validate_front_matter(front).first(12)
      errors.each do |e|
        key = e.field.split("/")[2]
        findings.add("E-SCHEMA", e.field, e.message, **{ rule: "front_matter", line: key && front_line(lines, key) }.compact)
      end
      errors.empty?
    end

    def key_consistent(front, lines, findings)
      key = front["key"].to_s
      kind, subject, = key.split(".", 3)
      return unless key.match?(/\A(ripasso|ponte|lezione)\.[a-z_]+\./)

      findings.add("E-LESSON-PARSE", "/front_matter/kind", "kind is #{front['kind'].inspect} but the key #{key} starts with #{kind}", rule: "kind", line: front_line(lines, "kind")) if front["kind"] != kind
      findings.add("E-LESSON-PARSE", "/front_matter/subject", "subject is #{front['subject'].inspect} but the key #{key} is for #{subject}", rule: "subject", line: front_line(lines, "subject")) if front["subject"] != subject
    end

    # ---- the splitter -------------------------------------------------------------------------------

    def scan(lines, body_start, findings)
      s = Scan.new(findings)
      lines.each_with_index do |line, i|
        n = i + 1
        next if n < body_start

        s.line(line, n)
      end
      s.finish
      [ s.cards, s.parts, s.field_lines ]
    end

    # The state of one pass over the body.
    class Scan
      attr_reader :cards, :parts, :field_lines

      def initialize(findings)
        @findings = findings
        @cards = []
        @parts = []
        @stack = []
        @field_lines = {}
        @card = nil
        @para = []
        @prev = :start # :start :blank :heading :more_open :close :text
        @reported_before_first = false
      end

      def error(code, line, message, rule)
        @findings.add(code, "/lesson.md", "line #{line}: #{message}", rule: "#{rule}-#{line}", line: line)
      end

      def block_error(line, message) = error("E-LESSON-BLOCK", line, message, "block")

      def line(text, n)
        return block_error(n, "a line starting with three backticks: code fences are not part of lessons") if text.start_with?("```")

        top = @stack.last
        return in_block(top, text, n) if top && top[:kind] == :block

        if text.strip.empty?
          @para << [ "", n ] unless @para.empty?
          @prev = :blank
        elsif (m = text.match(FENCE_OPEN))
          opening(m, n)
        elsif text.match?(FENCE_CLOSE)
          closing(text, n)
        elsif top.nil? && text.start_with?("# ")
          part(text, n)
        elsif top.nil? && text.start_with?("## ")
          heading(text, n)
        else
          text_line(text, n)
        end
      end

      def in_block(top, text, n)
        if text.match?(FENCE_CLOSE)
          if text.size == top[:width]
            @stack.pop
            attach(build(top))
            @prev = :close
          else
            block_error(top[:line], "the block opened at line #{top[:line]} is closed by #{text}, which has the wrong width: close it with #{':' * top[:width]}")
            @stack.pop
            @prev = :close
          end
        elsif text.match?(/\A:{3,4} [a-z]/)
          block_error(top[:line], "the block opened at line #{top[:line]} is never closed: a new directive starts at line #{n}")
          @stack.pop
          line(text, n)
        else
          top[:body] << text
        end
      end

      def build(frame)
        return nil unless frame[:head]

        block, index = Directives.build(frame[:head], frame[:body], frame[:line], in_more: frame[:in_more])
        @field_lines[frame[:line]] = index
        valid(block.merge("line" => frame[:line]), frame[:line])
      rescue Directives::Refused => e
        block_error(e.line, e.message)
        nil
      end

      # The block against its schema (the shape of A4): a refusal is E-LESSON-BLOCK at the block's opening line.
      def valid(block, line)
        errors = Parser2.block_errors(block)
        return block if errors.empty?

        block_error(line, "#{block['type']}: #{errors.first(3).join('; ')}")
        nil
      end

      def opening(match, n)
        flush
        unless %i[start blank heading more_open].include?(@prev)
          block_error(n, "a blank line is required before a fence (line #{n} follows text or a closing fence)")
        end
        width = match[1].size
        head = begin
          Directives.opening(match[2], n)
        rescue Directives::Refused => e
          block_error(n, e.message)
          nil
        end
        if @card.nil?
          error("E-LESSON-CARD", n, "a fence before the first card heading", "before-first") unless @reported_before_first
          @reported_before_first = true
        end
        if width == 4
          open_more(head, n)
        else
          block_error(n, "a more block opens with ::::, not :::") if head && head[:type] == "more"
          @stack << { kind: :block, width: 3, head: (head unless head && head[:type] == "more"), body: [], line: n, in_more: !@stack.empty? }
          @prev = :text
        end
      end

      def open_more(head, n)
        if head && head[:type] != "more"
          block_error(n, "only more uses ::::, here #{head[:type].inspect}")
          head = nil
        end
        bad = !@stack.empty? || head.nil?
        block_error(n, "a more block cannot go inside another more block") unless @stack.empty?
        block_error(n, "a more block has a title: :::: more \"Titolo\"") if head && !bad && head[:title].to_s.empty?
        @stack << { kind: :more, width: 4, head: head, blocks: [], line: n, bad: bad }
        @prev = :more_open
      end

      def closing(text, n)
        flush
        top = @stack.last
        if top.nil?
          block_error(n, "a closing fence with nothing open")
        elsif text.size == 4
          @stack.pop
          attach_more(top) unless top[:bad]
        else
          block_error(top[:line], "the more block opened at line #{top[:line]} is closed by ::: at line #{n}: close it with ::::")
          @stack.pop
        end
        @prev = :close
      end

      def attach_more(frame)
        title = frame[:head][:title]
        attach(valid({ "type" => "more", "title_it" => title, "blocks" => frame[:blocks], "line" => frame[:line] }, frame[:line]))
      end

      def attach(block)
        return unless block
        return if @card.nil?

        (@stack.last && @stack.last[:kind] == :more ? @stack.last[:blocks] : @card[:blocks]) << block
      end

      def part(text, n)
        flush
        title = text[2..].strip
        @parts << { "n" => @parts.size + 1, "title_it" => title, line: n }
        @card = nil if @card && @card[:bad]
        @prev = :heading
      end

      def heading(text, n)
        flush
        @prev = :heading
        m = text.size <= 400 ? text.match(HEADING) : nil
        unless m
          error("E-LESSON-CARD", n, "a ## heading is a card and ends with {ROLE ...} (role: idea, example, mistakes, try, summary), here #{text.inspect}", "heading")
          @card = { bad: true, blocks: [], line: n }
          return
        end
        title = m[:title].strip
        tag = tag(m[:tag], n)
        if title.gsub(/\$[^$]*\$/, "").match?(/[{}]/)
          error("E-LESSON-CARD", n, "a { or } in a title outside $...$: the last brace group of the heading is its tag", "heading")
          tag = nil
        end
        @card = { bad: tag.nil?, blocks: [], line: n, title: title, tag: tag, part: (@parts.size if @parts.any?) }
        @cards << @card
      end

      # {role:, extra:, icon:, id:, tone:} or nil (after reporting).
      def tag(text, n)
        tokens = text.split
        out = {}
        bad = lambda do |why|
          error("E-LESSON-CARD", n, "the tag {#{text}}: #{why}", "tag")
          nil
        end
        role = tokens.shift
        return bad.call("it starts with a role: #{ROLES.join(', ')}") unless ROLES.include?(role)

        out[:role] = role
        tokens.each do |t|
          if ROLES.include?(t)
            return bad.call("a role is given once (#{role} and #{t})")
          elsif t == "extra"
            return bad.call("extra is given once") if out[:extra]

            out[:extra] = true
          elsif (kv = t.match(/\A(icon|id|tone)=(.+)\z/))
            key = kv[1].to_sym
            return bad.call("#{kv[1]} is given once") if out.key?(key)

            ok = { icon: ICON, id: SLUG, tone: ROLE_NAME }.fetch(key).match?(kv[2])
            return bad.call("#{kv[1]}=#{kv[2]} is not a valid #{kv[1]}#{' (a-z, 0-9 and -, at most 32)' if key == :id}") unless ok

            out[key] = kv[2]
          else
            return bad.call("unknown token #{t.inspect} (extra, icon=NAME, id=SLUG, tone=ROLE)")
          end
        end
        out
      end

      def text_line(text, n)
        top = @stack.last
        if top.nil? && @card.nil?
          error("E-LESSON-CARD", n, "text before the first card: everything after the front matter belongs to a card (## Title {idea})", "before-first") unless @reported_before_first
          @reported_before_first = true
          @prev = :text
          return
        end
        if @prev == :close
          block_error(n, "a blank line is required after a closing fence (line #{n} follows a fence)")
        end
        @para << [ text, n ]
        @prev = :text
      end

      # Ends a run of text lines: one text block.
      def flush
        @para.pop while @para.last && @para.last[0].empty?
        return if @para.empty?

        attach("type" => "text", "text_it" => @para.map(&:first).join("\n"), "line" => @para.first[1]) if @card
        @para = []
      end

      def finish
        flush
        @stack.each { |f| block_error(f[:line], "the #{f[:kind] == :more ? 'more block' : 'block'} opened at line #{f[:line]} is never closed") }
      end
    end

    # The schema errors of one block (numbered as it will be), as short sentences. Counts that have a code of their
    # own (the points of a summary: E-LESSON-SUMMARY) are left to the checks.
    def block_errors(block)
      numbered = for_schema(number([ block ]).first)
      schema = Banco::Schemas.schema("lesson").ref("#/$defs/block")
      schema.validate(numbered).map { |e| "#{e['data_pointer'].to_s.sub(/\A\//, '')} #{short(e)}".strip }
    end

    # The counts that have a code of their own are not the schema's to judge (E-LESSON-SUMMARY: 3 to 5 points;
    # E-CARD-BLOCKS: 1 to 6 blocks): the copy the schema sees is trimmed or padded to fit them.
    def for_schema(node)
      case node
      when Array then node.map { |v| for_schema(v) }
      when Hash
        out = node.transform_values { |v| for_schema(v) }
        if out["type"] == "summary" && out["points_it"].is_a?(Array) && out["points_it"].any?
          pts = out["points_it"].first(5)
          pts += [ pts.last ] * (3 - pts.size) if pts.size < 3
          out["points_it"] = pts
        end
        out["blocks"] = out["blocks"].first(6) if out["role"] && out["blocks"].is_a?(Array) && out["blocks"].size > 6
        out
      else node
      end
    end

    def short(error)
      case error["type"]
      when "required" then "is missing #{error.dig('details', 'missing_keys')&.join(', ')}"
      when "additionalProperties", "unevaluatedProperties" then "has a field that is not part of the block: #{Array(error.dig('details', 'unexpected_keys') || error.dig('details', 'unevaluated_properties')).join(', ')}"
      else error["error"].to_s.sub(/\Avalue at `[^`]*` /, "").first(140)
      end
    end

    # ---- parts and body -----------------------------------------------------------------------------

    def structure(cards, parts, findings)
      ids = {}
      cards.each do |c|
        next if c[:bad]

        id = c.dig(:tag, :id)
        next unless id

        if ids.key?(id)
          findings.add("E-LESSON-CARD", "/lesson.md", "line #{c[:line]}: the card id #{id} is used twice (first at line #{ids[id]})", rule: "id-#{c[:line]}", line: c[:line])
        else
          ids[id] = c[:line]
        end
      end
      return if parts.empty?

      lo, hi = Validation::Rules.get(:lesson2, :parts)
      min = Validation::Rules.get(:lesson2, :part_min_cards)
      if parts.size < lo || parts.size > hi
        at = parts.size > hi ? parts[hi][:line] : parts.first[:line]
        findings.add("E-LESSON-PARTS", "/lesson.md", "line #{at}: a lesson has no parts or #{lo} to #{hi} (here #{parts.size})", rule: "count", line: at)
      end
      first = parts.first[:line]
      cards.each do |c|
        findings.add("E-LESSON-PARTS", "/lesson.md", "line #{c[:line]}: when there are parts, the first card follows the first part heading", rule: "before-first-#{c[:line]}", line: c[:line]) if c[:line] < first
      end
      parts.each_with_index do |p, i|
        n = cards.count { |c| !c[:bad] && !c.dig(:tag, :extra) && c[:part] == i + 1 }
        findings.add("E-LESSON-PARTS", "/lesson.md", "line #{p[:line]}: the part #{p['title_it'].inspect} has #{n} card(s) (at least #{min})", rule: "cards-#{i}", line: p[:line]) if n < min
      end
    end

    def build_body(front, cards, parts)
      built = cards.each_with_index.map { |c, i| card_json(c, i + 1) }
      core_words = built.reject { |c| c["level"] == "extra" }.sum { |c| Blocks.prose_words(c) }
      extra_words = built.select { |c| c["level"] == "extra" }.sum { |c| Blocks.prose_words(c) } + built.reject { |c| c["level"] == "extra" }.sum { |c| Blocks.more_prose(c).sum { |t| Blocks.words(t) } }
      body = {
        "schema" => "banco.lesson/2", "schema_version" => 2,
        "key" => front["key"], "kind" => front["kind"], "subject" => front["subject"], "title_it" => front["title_it"],
        "goals_it" => front["goals_it"], "why_it" => front["why_it"], "skills" => front["skills"], "uses" => front["uses"] || [],
        "refs" => front["refs"], "scope" => front["scope"], "minutes" => front["minutes"], "calculator" => front["calculator"]
      }
      body["book_it"] = front["book_it"] if front["book_it"]
      body["hero"] = front["hero"] if front["hero"]
      body["parts"] = parts.map { |p| p.slice("n", "title_it") } if parts.any?
      body.merge("cards" => built, "words" => { "core" => core_words, "extra" => extra_words }, "pages" => [])
    end

    def card_json(card, n)
      tag = card[:tag]
      extra = tag[:extra] == true
      h = { "n" => n, "id" => tag[:id] || "c#{n}", "role" => tag[:role], "level" => extra ? "extra" : "core", "title_it" => card[:title],
            "icon" => tag[:icon] || Icons.default_for(tag[:role], extra: extra) }
      h["tone"] = tag[:tone] if tag[:tone]
      h["part"] = card[:part] if card[:part] && !extra
      h["line"] = card[:line]
      h["blocks"] = number(card[:blocks])
      h
    end

    # n for every block (and every block inside a more, and every exercise of a try).
    def number(blocks)
      blocks.each_with_index.map do |b, i|
        out = { "n" => i + 1 }.merge(b)
        out["blocks"] = number(out["blocks"]) if out["blocks"]
        out["exercises"] = out["exercises"].each_with_index.map { |e, k| e.is_a?(Hash) ? { "n" => k + 1 }.merge(e) : e } if out["exercises"].is_a?(Array)
        out
      end
    end
  end
end
