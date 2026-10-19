# frozen_string_literal: true

require "psych"
require "yaml"

module Lessons
  # One fenced directive of a lesson/2 card (A1, A4): the opening line `::: TYPE [ARG] ["Title"]` and its body, as
  # the block hash of the body JSON (without n and line, which Parser2 numbers). Everything refused is
  # Directives::Refused with the line of the lesson (E-LESSON-BLOCK).
  module Directives
    class Refused < StandardError
      attr_reader :line

      def initialize(line, message)
        @line = line
        super(message)
      end
    end

    OPENING = /\A(?<type>[a-z][a-z_0-9]*)(?: (?<arg>[a-z][a-z_0-9-]*))?(?: "(?<title>[^"\n]*)")?\z/
    # What each directive's opening line may carry besides the type: [argument required?, values or nil, title allowed?]
    SHAPE = {
      "callout" => [ true, %w[tip warning remember rule], true ],
      "diagram" => [ true, nil, false ], "schema" => [ true, nil, false ], "check" => [ true, nil, false ],
      "procedure" => [ false, nil, true ], "cases" => [ false, nil, true ], "more" => [ false, nil, true ]
    }.freeze
    NO_ARG = [ false, nil, false ].freeze
    # Inside a more: text, callout, math, diagram, schema, table, procedure, image (A1).
    IN_MORE = %w[callout math diagram schema table procedure image].freeze

    module_function

    # Parses the opening line (without the fence) -> {type:, arg:, title:}; raises Refused.
    def opening(text, line)
      m = text.match(OPENING) or raise Refused.new(line, "the directive line is `::: TYPE [ARG] [\"Title\"]`, here #{text.inspect}")
      { type: m[:type], arg: m[:arg], title: m[:title] }
    end

    # The block hash for a directive. +lines+: the body lines; +first_line+: the lesson line of the opening line.
    # +allow_reserved+ is the reserved dry run (WAVE2 1.2): a block, type or option that is reserved or a draft passes here
    # and is validated against its frozen or draft schema; the caller reports it (W-TYPE-RESERVED, W-TYPE-DRAFT), and passes an Array
    # as +allow_reserved+ to be handed each use.
    def build(head, lines, first_line, in_more: false, allow_reserved: false)
      type = head[:type]
      raise Refused.new(first_line, "unknown block type #{type.inspect} (#{Types.names(:block, status: 'available').reject { |n| n == 'text' }.join(', ')})") unless Types.known?(:block, type) && type != "text"
      refuse_held_back(:block, type, "the #{type} block", first_line, allow_reserved)
      raise Refused.new(first_line, "a #{type} block cannot go inside a more block (only text, callout, math, diagram, schema, table, procedure)") if in_more && !IN_MORE.include?(type)

      needs_arg, values, title_ok = SHAPE.fetch(type, NO_ARG)
      raise Refused.new(first_line, "#{type} needs an argument (::: #{type} #{values ? values.join('|') : 'NAME'})") if needs_arg && head[:arg].nil?
      raise Refused.new(first_line, "#{type} takes no argument (here #{head[:arg].inspect})") if head[:arg] && !needs_arg
      raise Refused.new(first_line, "#{type} must be one of #{values.join(', ')}, not #{head[:arg].inspect}") if values && !values.include?(head[:arg])
      raise Refused.new(first_line, "#{type} takes no title") if head[:title] && !title_ok

      body = lines.join("\n")
      block = case type
      when "callout" then { "type" => "callout", "kind" => head[:arg], "title_it" => head[:title], "text_it" => text(body, first_line) }.compact
      when "summary" then summary(body, first_line)
      when "math" then math(body, first_line)
      when "diagram", "schema"
        refuse_held_back(:diagram, head[:arg], "the diagram type #{head[:arg]}", first_line, allow_reserved)
        data = yaml(body, first_line, type).merge("type" => head[:arg])
        refuse_uses(Types.held_back_uses(:diagram, head[:arg], data), "#{head[:arg]}", first_line, allow_reserved)
        { "type" => type, type => data }
      when "check"
        refuse_held_back(:check, head[:arg], "the check component #{head[:arg]}", first_line, allow_reserved) if Types.known?(:check, head[:arg])
        data = yaml(body, first_line, "check").merge("type" => "check", "component" => head[:arg])
        Types.held_back_options(data).each { |name, spec| refuse_one(Types.describe_hold("the check option #{name}", spec["status"], spec["batch"]), spec, first_line, allow_reserved) }
        data
      else
        data = yaml(body, first_line, type).merge("type" => type).merge(head[:title] ? { "title_it" => head[:title] } : {})
        refuse_uses(Types.held_back_uses(:block, type, data), type, first_line, allow_reserved)
        data
      end
      [ block, pointer_lines(body, first_line) ]
    end

    # A name the registry holds back (reserved or a draft) is E-LESSON-BLOCK unless the reserved dry run allows it.
    def refuse_held_back(kind, name, label, line, allow_reserved)
      entry = Types.entry(kind, name)
      return if entry.nil? || entry["status"] == "available"

      refuse_one(Types.describe_hold(label, entry["status"], entry["batch"]), entry, line, allow_reserved)
    end

    def refuse_uses(uses, name, line, allow_reserved)
      uses.each do |field, value, spec|
        refuse_one(Types.describe_hold("#{name} #{field}#{value == 'present' ? '' : ": #{value}"}", spec["status"], spec["batch"]), spec, line, allow_reserved)
      end
    end

    # +allow_reserved+ is false (refuse), true (let it pass) or an Array that collects [status, message, line] of each use that
    # passes, so that the caller can answer W-TYPE-RESERVED or W-TYPE-DRAFT per use.
    def refuse_one(message, spec, line, allow_reserved)
      raise Refused.new(line, message) unless allow_reserved && Types::STATUSES.include?(spec["status"])

      allow_reserved << [ spec["status"], message, line ] if allow_reserved.is_a?(Array)
    end

    # {JSON pointer of the YAML body => lesson line of its key}, so that a finding names the line of the field.
    def pointer_lines(body, first_line)
      doc = Psych.parse(body)
      index = {}
      walk(doc&.root, "", first_line + 1, index)
      index
    rescue Psych::Exception
      {}
    end

    def walk(node, pointer, base, index)
      case node
      when Psych::Nodes::Mapping
        node.children.each_slice(2) do |key, value|
          at = "#{pointer}/#{key.value}"
          index[at] = base + key.start_line
          walk(value, at, base, index)
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index do |item, i|
          at = "#{pointer}/#{i}"
          index[at] = base + item.start_line
          walk(item, at, base, index)
        end
      end
    end

    def text(body, line)
      stripped = body.strip
      raise Refused.new(line, "the block has no text") if stripped.empty?

      stripped
    end

    # A markup unordered list of 3 to 5 points becomes points_it (the count is the schema's).
    def summary(body, line)
      blocks = begin
        Markup.raw_blocks(body, line_offset: line + 1, roles: true)
      rescue Markup::Refused => e
        raise Refused.new(e.line, "summary: #{e.construct}")
      end
      raise Refused.new(line, "summary is exactly one list of points (each line starts with - )") unless blocks.size == 1 && blocks.first.type == :ul
      raise Refused.new(line, "a summary point is one line, without a nested list") if blocks.first.items.any? { |i| i[:subs].any? }

      { "type" => "summary", "points_it" => blocks.first.items.map { |i| i[:text] } }
    end

    # One LaTeX formula, or a YAML `lines:` list.
    def math(body, line)
      stripped = body.strip
      raise Refused.new(line, "math is one formula or a lines: list") if stripped.empty?

      if stripped.start_with?("lines:")
        data = yaml(body, line, "math")
        { "type" => "math" }.merge(data.slice("lines"))
      else
        raise Refused.new(line, "math is one formula on one line (use lines: for a chain)") if stripped.include?("\n")

        tex = unquote(stripped, line)
        raise Refused.new(line, "math is one formula or a lines: list") if tex.empty?

        { "type" => "math", "tex" => tex }
      end
    end

    # A one-line formula written in quotes, as the YAML of the other blocks is ('...' or "..."), loses the one matching pair around it
    # (D-310): KaTeX cannot draw a quote, and the author meant the formula. What is inside is kept as written: no YAML escape is read, so a
    # backslash stays a backslash and '' stays two primes.
    def unquote(text, line)
      return text unless text.length >= 2 && [ "'", '"' ].include?(text[0]) && text[-1] == text[0]

      inside = text[1..-2]
      raise Refused.new(line, "a quoted formula holds no #{text[0]} inside (YAML doubles it): write the formula without quotes") if inside.include?(text[0])

      inside.strip
    end

    # YAML.safe_load (no aliases, no custom tags), a mapping, and no double-quoted scalar with a backslash.
    def yaml(body, line, what)
      refuse_double_quoted_backslash(body, line)
      data = YAML.safe_load(body, permitted_classes: [], aliases: false)
      raise Refused.new(line, "the body of #{what} must be a mapping of keys and values") unless data.is_a?(Hash)

      yes_keys(data)
    rescue Psych::Exception, ArgumentError => e
      raise Refused.new(line, "the YAML of #{what} is not valid: #{e.message.lines.first.to_s.strip.first(160)} (LaTeX goes in single quotes or a block scalar)")
    end

    # YAML 1.1 reads a bare `yes:` as the boolean true, and `seats` has a field named yes (WAVE2 2.4): a key that came out as true is `yes`.
    # (`on:` and `true:` are no field of ours, and `no`/`off` stay false: a key that is false is left alone and the schema refuses it.)
    def yes_keys(node)
      case node
      when Hash then node.to_h { |k, v| [ k == true ? "yes" : k, yes_keys(v) ] }
      when Array then node.map { |v| yes_keys(v) }
      else node
      end
    end

    # "a \neq 0" in double quotes becomes a newline and "eq" (and "\cdot" is no escape at all): refuse a
    # double-quoted YAML value with a backslash (A1). A small scan of the raw lines, since the library stops at a bad
    # escape before it tells us where the scalar was: quotes count only where a value starts (after `: `, `- `, `[`,
    # `{` or `,`), block scalars (`|`, `>`) are skipped, a `#` outside quotes starts a comment.
    def refuse_double_quoted_backslash(body, line)
      block_indent = nil
      body.split("\n", -1).each_with_index do |row, i|
        indent = row[/\A */].size
        if block_indent
          next if row.strip.empty? || indent > block_indent

          block_indent = nil
        end
        block_indent = indent if row.match?(/(?:\A|:\s+|-\s+)[|>][+-]?\d?\s*(?:#.*)?\z/)
        hit = double_quoted_with_backslash(row)
        raise Refused.new(line + 1 + i, "a double-quoted YAML value with a backslash (#{hit.first(40)}): use single quotes or a block scalar") if hit
      end
    end

    # The first double-quoted scalar of +row+ whose source holds a backslash, or nil.
    def double_quoted_with_backslash(row)
      i = 0
      prev = nil # the last non-space character outside quotes
      while i < row.size
        ch = row[i]
        if ch == "#" && (i.zero? || row[i - 1] == " ")
          return nil
        elsif ch == "'" && value_start?(prev, row, i)
          i += 1
          while i < row.size
            if row[i] == "'"
              break unless row[i + 1] == "'"

              i += 2
            else
              i += 1
            end
          end
          prev = "'"
        elsif ch == '"' && value_start?(prev, row, i)
          stop = i + 1
          stop += (row[stop] == "\\" ? 2 : 1) while stop < row.size && row[stop] != '"'
          scalar = row[i..stop].to_s
          return scalar if scalar.include?("\\")

          i = stop
          prev = '"'
        elsif ch != " "
          prev = ch
        end
        i += 1
      end
      nil
    end

    def value_start?(prev, row, i)
      return true if prev.nil? || prev == "[" || prev == "{"

      row[i - 1] == " " && [ ":", "-", "," ].include?(prev)
    end
  end
end
