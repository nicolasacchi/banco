# frozen_string_literal: true

module Lessons
  # Markup v2, for lessons only (A2.1): the restricted markup of agent text (bold, $latex$,
  # paragraphs, numbered lists) plus unordered lists with one nested level. Items keep markup v1
  # (app/javascript/items/markup_parser.js), so nothing approved changes rendering.
  #
  # This is the strict Ruby mirror of the browser parser's `parse(text, { lists: "v2" })`: where the
  # browser is lenient (an unclosed `$` stays text), this refuses with the line and the construct
  # (E-LESSON-MARKUP). Both are run against test/fixtures/markup/v2.json.
  #
  # Blocks (the shape of the browser parser, string keys so that a JSON compare works):
  #   {"type"=>"p",  "children"=>[node]}
  #   {"type"=>"ol"|"ul", "items"=>[{"children"=>[node], "sub"=>[[node]]}]}
  # Nodes: {"t"=>"text","v"=>s} | {"t"=>"bold","children"=>[node]} | {"t"=>"math","v"=>latex}
  module Markup
    class Refused < StandardError
      attr_reader :line, :construct

      def initialize(line, construct)
        @line = line
        @construct = construct
        super("line #{line}: #{construct}")
      end
    end

    ORDERED = /\A(\d+)\.\s+(.*)\z/
    ORDERED_EMPTY = /\A\d+\.\s*\z/
    BULLET = /\A-\s+(.*)\z/
    BULLET_EMPTY = /\A-\s*\z/
    SUB = /\A( {2,4})-\s+(.*)\z/
    DEEP = /\A\s{5,}-\s/
    RULE = /\A\s*([-*_])(\s*\1){2,}\s*\z/

    # One block as it stands in the source: type :p, :ol or :ul; text for a paragraph (lines joined
    # with one space); items for a list: {n:, text:, subs: [text], line:}; source is the block's own lines.
    RawBlock = Struct.new(:type, :line, :source, :text, :items, keyword_init: true)

    module_function

    # The canonical blocks of +text+. line_offset: the line number of the text's first line in the file.
    def parse(text, line_offset: 1)
      raw_blocks(text, line_offset: line_offset).map { |b| block_json(b, line_offset) }
    end

    def block_json(block, _offset)
      if block.type == :p
        { "type" => "p", "children" => inline(block.text, block.line) }
      else
        items = block.items.map { |i| { "children" => inline(i[:text], i[:line]), "sub" => i[:subs].map { |s| inline(s, i[:line]) } } }
        { "type" => block.type.to_s, "items" => items }
      end
    end

    # The blocks of +text+ before they become nodes; every construct outside v2 raises Refused.
    def raw_blocks(text, line_offset: 1)
      lines = text.to_s.gsub(/\r\n?/, "\n").split("\n", -1)
      blocks = []
      current = []
      lines.each_with_index do |line, i|
        if line.strip.empty?
          blocks << build(current) unless current.empty?
          current = []
        else
          current << [ line, i + line_offset ]
        end
      end
      blocks << build(current) unless current.empty?
      blocks
    end

    def build(rows)
      rows.each { |line, n| line_level(line, n) }
      first, number = rows.first
      source = rows.map(&:first).join("\n")
      if first.match?(ORDERED) || first.match?(ORDERED_EMPTY)
        list(:ol, rows, source)
      elsif first.match?(BULLET) || first.match?(BULLET_EMPTY)
        list(:ul, rows, source)
      else
        raise Refused.new(number, "a nested item with no item above") if first.match?(/\A\s+-\s/)

        rows.drop(1).each do |line, n|
          raise Refused.new(n, "a list marker inside a paragraph (leave a blank line before the list)") if line.match?(/\A\s{0,1}(\d+\.|-)\s/)
        end
        RawBlock.new(type: :p, line: number, source: source, text: rows.map { |l, _| l.strip }.join(" "))
      end
    end

    # What a whole line shows, before its inline content is read.
    def line_level(line, number)
      raise Refused.new(number, "a heading inside a section") if line.match?(/\A\s*\#{1,6}(\s|\z)/)
      raise Refused.new(number, "a quote (>)") if line.match?(/\A\s*>/)
      raise Refused.new(number, "a rule (---)") if line.match?(RULE)
    end

    def list(type, rows, source)
      marker = type == :ol ? ORDERED : BULLET
      empty = type == :ol ? ORDERED_EMPTY : BULLET_EMPTY
      items = []
      rows.each do |line, n|
        if (m = line.match(marker))
          text = type == :ol ? m[2] : m[1]
          raise Refused.new(n, "a list item without text") if text.strip.empty?
          items << { n: (type == :ol ? m[1].to_i : nil), text: text.strip, subs: [], line: n }
        elsif line.match?(empty)
          raise Refused.new(n, "a list item without text")
        elsif line.match?(ORDERED) || line.match?(BULLET)
          raise Refused.new(n, "an ordered and an unordered list in one block (leave a blank line between them)")
        elsif (m = line.match(SUB))
          raise Refused.new(n, "a nested item with no item above") if items.empty?

          items.last[:subs] << m[2].strip
        elsif line.match?(DEEP) || line.match?(/\A\s+(\d+\.)\s/)
          raise Refused.new(n, "more than one nested level")
        elsif line.match?(/\A\s{2,}\S/)
          # A wrapped line of the item above.
          if items.last[:subs].any? then items.last[:subs][-1] = "#{items.last[:subs].last} #{line.strip}"
          else items.last[:text] = "#{items.last[:text]} #{line.strip}"
          end
        elsif line.match?(/\A\s*-\s/)
          raise Refused.new(n, "a nested item indented by 2 to 4 spaces is expected")
        else
          raise Refused.new(n, "text inside a list (leave a blank line before it, or indent it by 2 spaces)")
        end
      end
      RawBlock.new(type: type, line: rows.first[1], source: source, items: items)
    end

    # Inline nodes of one paragraph or item. Strict: every construct outside $...$ and **...** is refused.
    def inline(text, line)
      nodes = []
      buffer = +""
      flush = lambda do
        nodes << { "t" => "text", "v" => buffer.dup } unless buffer.empty?
        buffer.clear
      end
      i = 0
      while i < text.length
        ch = text[i]
        nxt = text[i + 1]
        if ch == "\\"
          raise Refused.new(line, "a backslash outside $...$ (math goes between dollar signs)") unless nxt == "$"

          buffer << "$"
          i += 2
        elsif ch == "$"
          stop = closing(text, i + 1)
          raise Refused.new(line, "an unclosed $") if stop.nil?
          raise Refused.new(line, "an empty $$") if stop == i + 1

          flush.call
          nodes << { "t" => "math", "v" => text[(i + 1)...stop].gsub("\\$", "$") }
          i = stop + 1
        elsif ch == "*" && nxt == "*"
          stop = text.index("**", i + 2)
          raise Refused.new(line, "an unclosed **") if stop.nil? || stop == i + 2

          flush.call
          nodes << { "t" => "bold", "children" => inline(text[(i + 2)...stop], line) }
          i = stop + 2
        else
          refuse_char(text, i, line)
          buffer << ch
          i += 1
        end
      end
      flush.call
      nodes
    end

    def refuse_char(text, i, line)
      ch = text[i]
      case ch
      when "*" then raise Refused.new(line, "italics (*)")
      when "_" then raise Refused.new(line, "an underscore outside $...$ (italics or bare math)")
      when "^" then raise Refused.new(line, "a caret outside $...$ (bare math)")
      when "`" then raise Refused.new(line, "backticks")
      when "|" then raise Refused.new(line, "a table (|)")
      when "<" then raise Refused.new(line, "an HTML tag") if text[i + 1].to_s.match?(/[A-Za-z\/!]/)
      when "!" then raise Refused.new(line, "an image") if text[i + 1] == "["
      when "]" then raise Refused.new(line, "a link") if text[i + 1] == "("
      end
    end

    # Index of the next unescaped "$" at or after +from+, or nil.
    def closing(text, from)
      i = from
      while i < text.length
        if text[i] == "\\" then i += 2
        elsif text[i] == "$" then return i
        else i += 1
        end
      end
      nil
    end
  end
end
