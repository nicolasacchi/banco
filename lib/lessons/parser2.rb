# frozen_string_literal: true

module Lessons
  # lesson.md -> the parsed body of banco.lesson/2 (A1, A2). The source is a front matter and then cards: a level-1
  # heading starts a part, a level-2 heading `## Title {ROLE [extra] [icon=NAME] [id=SLUG] [tone=ROLE] [short="Name"]}` a card, and
  # inside a card plain text and fenced directives are the blocks. The splitter is fence-aware: a heading counts only
  # at depth 0, so a `## ` line in a YAML block scalar is text of its block.
  #
  # D-402: a lesson of english or spanish with `bilingual: true` is written in the target language and each text has its Italian translation:
  # the title of a heading is the target text and its tag adds `it="Titolo"` and `short_it="Nome"`, a `# Part` heading takes ` {it="Titolo"}`, the
  # `::: it` fence directly after a text, a callout or a summary holds its Italian, a titled fence (callout, procedure, cases, more) adds
  # `it="Titolo"`, and YAML blocks write the pair on adjacent keys. The body keeps both: `title_en`/`title_it`, `text_en`/`text_it`...
  #
  # What this refuses is the shape: E-LESSON-PARSE, E-SCHEMA of the front matter, E-LESSON-CARD, E-LESSON-PARTS,
  # E-LESSON-BLOCK (with the line of the construct). Numbers, budgets, semantics and readability are
  # Validation::Lesson2Checks. When anything is refused here, body is nil.
  module Parser2
    ROLES = %w[idea example mistakes try summary].freeze
    HEADING = /\A## (?<title>.+?) \{(?<tag>[^{}]*)\}[ \t]*\z/
    SLUG = /\A[a-z0-9-]{1,32}\z/
    ICON = /\A[a-z][a-z0-9]*(-[a-z0-9]+)*\z/
    ROLE_NAME = /\A[a-z]+([_-][a-z]+)*\z/
    FENCE_OPEN = /\A(:{3,4}) (.*)\z/
    FENCE_CLOSE = /\A:{3,4}\z/
    PART = /\A# (?<title>.+?) \{it="(?<it>[^"{}]*)"\}[ \t]*\z/
    # The blocks that a `::: it` fence can translate (the prose ones; the YAML blocks carry their pairs themselves).
    PAIRABLE = %w[text callout summary].freeze

    Parsed2 = Struct.new(:front_matter, :body, :cards, :parts, :source, :lines, :body_start, :field_lines, keyword_init: true)

    module_function

    def schema2?(source)
      front = source.to_s.match(/\A---\n(.*?)\n---\n/m)&.[](1)
      !!front&.match?(/^schema:\s*["']?banco\.lesson\/2["']?\s*$/)
    end

    # Returns Parsed2, or nil when there is no front matter to speak of (the finding says why).
    # +allow_reserved+: the reserved dry run (lesson submit --dry-run --allow-reserved): a reserved or draft piece passes the parse and
    # each use is a warning W-TYPE-RESERVED or W-TYPE-DRAFT. A lesson with such a use is never stored.
    def call(md, findings, allow_reserved: false)
      source = Parser.normalize(md)
      unless source.valid_encoding?
        findings.add("E-LESSON-PARSE", "/", "lesson.md is not valid UTF-8", rule: "encoding")
        return nil
      end
      front, body_start = Parser.front_matter(source, findings)
      return nil unless front

      lines = source.split("\n", -1)
      lang = bilingual_lang(front)
      schema_ok = front_matter_schema(front, lines, findings)
      key_consistent(front, lines, findings)
      cards, parts, field_lines = scan(lines, body_start, findings, allow_reserved, lang: lang, subject: front["subject"])
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

    # The target language of a bilingual lesson ("en", "es"); nil for a lesson that is not one.
    def bilingual_lang(front) = front["bilingual"] == true ? Lang.target(front["subject"]) : nil

    def front_matter_schema(front, lines, findings)
      errors = Banco::Schemas.validate_front_matter(front).first(12)
      wrong_flag = front.key?("bilingual") && Lang.target(front["subject"]).nil?
      if wrong_flag
        errors = errors.reject { |e| e.field.end_with?("/bilingual") || e.message.include?("bilingual") }
        findings.add("E-LANG-BILINGUAL-FLAG", "/front_matter/bilingual", "bilingual is for the subjects that teach a language (english, spanish), not #{front['subject'].inspect}", rule: "front_matter-bilingual", line: front_line(lines, "bilingual"))
      end
      errors.each do |e|
        key = e.field.split("/")[2]
        findings.add("E-SCHEMA", e.field, e.message, **{ rule: "front_matter", line: key && front_line(lines, key) }.compact)
      end
      errors.empty? && !wrong_flag
    end

    def key_consistent(front, lines, findings)
      key = front["key"].to_s
      kind, subject, = key.split(".", 3)
      return unless key.match?(/\A(ripasso|ponte|lezione|extra)\.[a-z_]+\./)

      findings.add("E-LESSON-PARSE", "/front_matter/kind", "kind is #{front['kind'].inspect} but the key #{key} starts with #{kind}", rule: "kind", line: front_line(lines, "kind")) if front["kind"] != kind
      findings.add("E-LESSON-PARSE", "/front_matter/subject", "subject is #{front['subject'].inspect} but the key #{key} is for #{subject}", rule: "subject", line: front_line(lines, "subject")) if front["subject"] != subject
    end

    # ---- the splitter -------------------------------------------------------------------------------

    def scan(lines, body_start, findings, allow_reserved = false, lang: nil, subject: nil)
      s = Scan.new(findings, allow_reserved: allow_reserved, lang: lang, subject: subject)
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

      def initialize(findings, allow_reserved: false, lang: nil, subject: nil)
        @findings = findings
        @allow_reserved = allow_reserved
        @lang = lang
        @subject = subject
        @pairable = nil # the text, callout or summary block that a `::: it` fence may translate next
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
          @prev = :blank # the dropped block took the blank line before this one
          line(text, n)
        else
          top[:body] << text
        end
      end

      def build(frame)
        return nil unless frame[:head]
        return translate(frame) if frame[:head][:type] == "it"

        holds = @allow_reserved ? [] : false
        block, index = Directives.build(frame[:head], frame[:body], frame[:line], in_more: frame[:in_more], allow_reserved: holds, lang: @lang)
        report_holds(holds)
        @field_lines[frame[:line]] = index
        valid(block.merge("line" => frame[:line]), frame[:line])
      rescue Directives::Refused => e
        block_error(e.line, e.message)
        nil
      end

      # The `::: it` fence: the Italian of the text, callout or summary right before it, in the same card (or more block).
      def translate(frame)
        target = @pairable
        container = @stack.last && @stack.last[:kind] == :more ? @stack.last[:blocks] : @card&.fetch(:blocks, nil)
        unless target && container && container.last.equal?(target)
          block_error(frame[:line], "::: it translates the text, callout or summary right before it: put it after that block, after one blank line")
          return nil
        end
        added = Directives.translation(target["type"], frame[:body].join("\n"), frame[:line])
        block_error(frame[:line], "the #{target['type']} block before this fence already has its Italian") if added.keys.any? { |k| target.key?(k) }
        target.merge!(added)
        @pairable = nil
        nil
      rescue Directives::Refused => e
        block_error(e.line, e.message)
        nil
      end

      # The reserved dry run: each use of a reserved or draft piece is a warning with the line of its block.
      def report_holds(holds)
        return unless holds.is_a?(Array)

        holds.each do |status, message, line|
          code = status == "draft" ? "W-TYPE-DRAFT" : "W-TYPE-RESERVED"
          @findings.add(code, "/lesson.md", "line #{line}: #{message}", rule: "#{code.downcase}-#{line}", line: line)
        end
      end

      # The block against its schema (the shape of A4): a refusal is E-LESSON-BLOCK at the block's opening line.
      def valid(block, line)
        errors = Parser2.block_errors(block, @subject, @lang)
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
        if head && head[:type] == "it"
          if @lang.nil? then block_error(n, "::: it is the Italian of a text in a bilingual lesson (bilingual: true in the front matter)")
          elsif head[:arg] || head[:title] then block_error(n, "::: it takes no argument and no title")
          end
          head = nil if @lang.nil? || head[:arg] || head[:title]
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
        @pairable = nil
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
        @pairable = nil
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
        head = frame[:head]
        block_error(frame[:line], "it=\"...\" belongs to a bilingual lesson (bilingual: true in the front matter)") if head[:it] && @lang.nil?
        titles = { "title_#{@lang || 'it'}" => head[:title] }
        titles["title_it"] = head[:it] if head[:it] && @lang
        attach(valid({ "type" => "more" }.merge(titles).merge("blocks" => frame[:blocks], "line" => frame[:line]), frame[:line]))
      end

      def attach(block)
        return unless block
        return if @card.nil?

        @pairable = (block if @lang && PAIRABLE.include?(block["type"]))
        (@stack.last && @stack.last[:kind] == :more ? @stack.last[:blocks] : @card[:blocks]) << block
      end

      def part(text, n)
        flush
        @pairable = nil
        m = @lang && text.match(PART)
        title = m ? m[:title].strip : text[2..].strip
        entry = { "n" => @parts.size + 1, "title_#{@lang || 'it'}" => title, line: n }
        entry["title_it"] = m[:it].strip if m
        @parts << entry
        @card = nil if @card && @card[:bad]
        @prev = :heading
      end

      def heading(text, n)
        flush
        @pairable = nil
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

      # {role:, extra:, icon:, id:, tone:, short:, it:, short_it:} or nil (after reporting). it and short_it are the Italian of the title and of the
      # short name in a bilingual lesson.
      def tag(text, n)
        tokens = text.scan(/(?:[^\s"]|"[^"]*")+/)
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
          elsif (kv = t.match(/\Ashort="([^"]+)"\z/))
            return bad.call("short is given once") if out.key?(:short)
            return bad.call('short="..." is 2 to 28 characters, no braces or $') unless kv[1].strip.size.between?(2, 28) && !kv[1].match?(/[{}$]/)

            out[:short] = kv[1].strip
          elsif (kv = t.match(/\A(it|short_it)="([^"]+)"\z/))
            return bad.call("#{kv[1]}=\"...\" belongs to a bilingual lesson (bilingual: true in the front matter)") unless @lang

            key = kv[1].to_sym
            return bad.call("#{kv[1]} is given once") if out.key?(key)
            return bad.call('short_it="..." is 2 to 28 characters, no braces or $') if key == :short_it && !(kv[2].strip.size.between?(2, 28) && !kv[2].match?(/[{}$]/))
            return bad.call('it="..." has no braces outside a formula') if key == :it && kv[2].gsub(/\$[^$]*\$/, "").match?(/[{}]/)

            out[key] = kv[2].strip
          elsif (kv = t.match(/\A(icon|id|tone)=(.+)\z/))
            key = kv[1].to_sym
            return bad.call("#{kv[1]} is given once") if out.key?(key)

            ok = { icon: ICON, id: SLUG, tone: ROLE_NAME }.fetch(key).match?(kv[2])
            return bad.call("#{kv[1]}=#{kv[2]} is not a valid #{kv[1]}#{' (a-z, 0-9 and -, at most 32)' if key == :id}") unless ok

            out[key] = kv[2]
          else
            return bad.call("unknown token #{t.inspect} (extra, icon=NAME, id=SLUG, tone=ROLE, short=\"Short name\"#{', it="Titolo", short_it="Nome"' if @lang})")
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
        @pairable = nil if @para.empty?
        @para << [ text, n ]
        @prev = :text
      end

      # Ends a run of text lines: one text block.
      def flush
        @para.pop while @para.last && @para.last[0].empty?
        return if @para.empty?

        attach("type" => "text", "text_#{@lang || 'it'}" => @para.map(&:first).join("\n"), "line" => @para.first[1]) if @card
        @para = []
      end

      def finish
        flush
        @stack.each { |f| block_error(f[:line], "the #{f[:kind] == :more ? 'more block' : 'block'} opened at line #{f[:line]} is never closed") }
      end
    end

    # The schema errors of one block (numbered as it will be), as short sentences. Counts that have a code of their
    # own (the points of a summary: E-LESSON-SUMMARY) are left to the checks. A missing Italian next to its target text is E-LANG-PAIR-MISSING's
    # (Validation::Bilingual), not the schema's. +subject+ picks the derived schema of english and spanish (D-402).
    def block_errors(block, subject = nil, lang = nil)
      numbered = for_schema(number([ pad_pairs(block, lang) ]).first)
      schema = Banco::Schemas.for_subject("lesson", subject).ref("#/$defs/block")
      schema.validate(numbered).map { |e| "#{e['data_pointer'].to_s.sub(/\A\//, '')} #{short(e)}".strip }
    end

    # The body against the lesson schema (derived for english and spanish), as raw errors; the Italian that is missing next to its target text is not one.
    def body_errors(body, subject, lang = nil)
      Banco::Schemas.for_subject("lesson", subject).validate(for_schema(pad_pairs(body, lang))).to_a
    end

    # A copy of +node+ in which each target text without its Italian is given itself as its Italian, so that the schema (which requires the `_it` of a field)
    # leaves the missing translation to E-LANG-PAIR-MISSING (D-402). A lesson that is not bilingual (+lang+ nil) is checked as it is. The form material has no
    # Italian by design: the derived schema asks for no `_it` of it (Banco::Schemas::Bilingual::MATERIAL_REQUIRED).
    def pad_pairs(node, lang)
      return node unless lang

      copy = JSON.parse(JSON.generate(node)) # a deep copy of the parsed lesson (plain JSON values)
      Bilingual.pairs(copy, lang).to_a.each do |pointer, _base, target, italian|
        next unless target.is_a?(String) && italian.nil?

        segs = pointer.split("/").drop(1)
        last = segs.pop
        index = last.match?(/\A\d+\z/) ? last.to_i : nil
        key = index ? segs.pop : last
        next unless key&.match?(/_(en|es)\z/)

        holder = segs.reduce(copy) { |n, seg| n.is_a?(Array) ? n[seg.to_i] : n[seg] }
        twin = key.sub(/_(en|es)\z/, "_it")
        if index then holder[twin] = Array(holder[twin]).dup.tap { |list| list[index] = target }
        else holder[twin] = target
        end
      end
      copy
    end

    # The body as the target layer reads it (D-402): each pair `foo_<lang>` + `foo_it` becomes `foo_it` holding the target text, so that the budgets, the
    # readability and the block checks, which read the lesson's text from the `_it` slots, read the target language. No `tr`, no `lang`.
    def target_view(node, lang) = strip_tr(Bilingual.fold(node, lang).except("lang"))

    def strip_tr(node)
      case node
      when Hash then node.except("tr").transform_values { |v| strip_tr(v) }
      when Array then node.map { |v| strip_tr(v) }
      else node
      end
    end

    # The counts that have a code of their own are not the schema's to judge (E-LESSON-SUMMARY: 3 to 5 points;
    # E-CARD-BLOCKS: 1 to 6 blocks): the copy the schema sees is trimmed or padded to fit them.
    def for_schema(node)
      case node
      when Array then node.map { |v| for_schema(v) }
      when Hash
        out = node.transform_values { |v| for_schema(v) }
        %w[points_it points_en points_es].each do |key|
          next unless out["type"] == "summary" && out[key].is_a?(Array) && out[key].any?

          pts = out[key].first(5)
          pts += [ pts.last ] * (3 - pts.size) if pts.size < 3
          out[key] = pts
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
        findings.add("E-LESSON-PARTS", "/lesson.md", "line #{p[:line]}: the part #{p.values_at('title_en', 'title_es', 'title_it').compact.first.inspect} has #{n} card(s) (at least #{min})", rule: "cards-#{i}", line: p[:line]) if n < min
      end
    end

    def build_body(front, cards, parts)
      lang = bilingual_lang(front)
      built = cards.each_with_index.map { |c, i| card_json(c, i + 1, lang) }
      counted = lang ? target_view({ "cards" => built }, lang)["cards"] : built # the words of the language the student reads
      core_words = counted.reject { |c| c["level"] == "extra" }.sum { |c| Blocks.prose_words(c) }
      extra_words = counted.select { |c| c["level"] == "extra" }.sum { |c| Blocks.prose_words(c) } + counted.reject { |c| c["level"] == "extra" }.sum { |c| Blocks.more_prose(c).sum { |t| Blocks.words(t) } }
      body = {
        "schema" => "banco.lesson/2", "schema_version" => 2,
        "key" => front["key"], "kind" => front["kind"], "subject" => front["subject"], "title_it" => front["title_it"],
        "goals_it" => front["goals_it"], "why_it" => front["why_it"], "skills" => front["skills"], "uses" => front["uses"] || [],
        "refs" => front["refs"], "scope" => front["scope"], "minutes" => front["minutes"], "calculator" => front["calculator"]
      }
      if lang
        body["bilingual"] = true
        %w[title goals why].each { |base| body["#{base}_#{lang}"] = front["#{base}_#{lang}"] if front.key?("#{base}_#{lang}") }
      end
      body["book_it"] = front["book_it"] if front["book_it"]
      %w[glossary teaches_en teaches_es].each { |k| body[k] = front[k] if front[k] }
      body["hero"] = front["hero"] if front["hero"]
      body["parts"] = parts.map { |p| p.slice("n", "title_it", "title_#{lang}") } if parts.any?
      body.merge("cards" => built, "words" => { "core" => core_words, "extra" => extra_words }, "pages" => [])
    end

    def card_json(card, n, lang = nil)
      tag = card[:tag]
      extra = tag[:extra] == true
      h = { "n" => n, "id" => tag[:id] || "c#{n}", "role" => tag[:role], "level" => extra ? "extra" : "core", "title_#{lang || 'it'}" => card[:title],
            "icon" => tag[:icon] || Icons.default_for(tag[:role], extra: extra) }
      h["title_it"] = tag[:it] if lang && tag[:it]
      h["tone"] = tag[:tone] if tag[:tone]
      h["short_#{lang || 'it'}"] = tag[:short] if tag[:short]
      h["short_it"] = tag[:short_it] if lang && tag[:short_it]
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
