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
  #
  # With roles: true (banco.lesson/2, A5) two constructs more: a colour role span [[role:text]]
  # ({"t"=>"role","role"=>name,"children"=>[node]}) and a link [text](scheda:SLUG) or
  # [text](argomento:KEY) ({"t"=>"link","kind"=>,"target"=>,"children"=>[node]}); and a formula may
  # hold \role{name}{tex} (KaTeX's macro) but none of the commands in FORBIDDEN_TEX.
  module Markup
    class Refused < StandardError
      attr_reader :line, :construct

      def initialize(line, construct)
        @line = line
        @construct = construct
        super("line #{line}: #{construct}")
      end
    end

    ROLE_NAME = /\A[a-z]+(-[a-z]+)*\z/
    LINK_TARGET = /\A[a-z0-9.-]+\z/
    LINK_KINDS = %w[scheda argomento].freeze
    # Commands that would let an agent reach KaTeX's trust functions or redefine the macro (A5).
    FORBIDDEN_TEX = /\\(htmlClass|htmlId|htmlStyle|htmlData|href|url|includegraphics|def|gdef|edef|xdef|newcommand|renewcommand|providecommand|let|futurelet|global|class|cssId|raw|include|input)(?![A-Za-z])/

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
    def parse(text, line_offset: 1, roles: false)
      raw_blocks(text, line_offset: line_offset, roles: roles).map { |b| block_json(b, roles) }
    end

    def block_json(block, roles = false)
      if block.type == :p
        { "type" => "p", "children" => inline(block.text, block.line, roles: roles) }
      else
        items = block.items.map { |i| { "children" => inline(i[:text], i[:line], roles: roles), "sub" => i[:subs].map { |s| inline(s, i[:line], roles: roles) } } }
        { "type" => block.type.to_s, "items" => items }
      end
    end

    # The blocks of +text+ before they become nodes; every construct outside v2 raises Refused.
    def raw_blocks(text, line_offset: 1, roles: false)
      lines = text.to_s.gsub(/\r\n?/, "\n").split("\n", -1)
      blocks = []
      current = []
      lines.each_with_index do |line, i|
        if line.strip.empty?
          blocks << build(current, roles) unless current.empty?
          current = []
        else
          current << [ line, i + line_offset ]
        end
      end
      blocks << build(current, roles) unless current.empty?
      blocks
    end

    def build(rows, roles = false)
      rows.each { |line, n| line_level(line, n) }
      block = classify(rows)
      texts = block.type == :p ? [ [ block.text, block.line ] ] : block.items.flat_map { |i| ([ i[:text] ] + i[:subs]).map { |t| [ t, i[:line] ] } }
      texts.each { |text, line| inline(text, line, roles: roles) } # strict: refuses what the browser would show as it is
      block
    end

    def classify(rows)
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
    def inline(text, line, roles: false)
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
          tex = text[(i + 1)...stop].gsub("\\$", "$")
          check_tex(tex, line) if roles
          nodes << { "t" => "math", "v" => tex }
          i = stop + 1
        elsif ch == "*" && nxt == "*"
          stop = text.index("**", i + 2)
          raise Refused.new(line, "an unclosed **") if stop.nil? || stop == i + 2

          flush.call
          nodes << { "t" => "bold", "children" => inline(text[(i + 2)...stop], line, roles: roles) }
          i = stop + 2
        elsif roles && ch == "[" && nxt == "["
          flush.call
          node, i = role_span(text, i, line)
          nodes << node
        elsif roles && ch == "[" && (link = text[i..].match(/\A\[([^\[\]]*)\]\(([^()]*)\)/))
          flush.call
          nodes << link_node(link[1], link[2], line)
          i += link[0].size
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

    # [[role:text]] at +start+: the node and the index after the closing ]].
    def role_span(text, start, line)
      stop = role_close(text, start + 2)
      raise Refused.new(line, "an unclosed [[ colour role span") if stop.nil?

      inner = text[(start + 2)...stop]
      name, body = inner.split(":", 2)
      raise Refused.new(line, "a [[ that is not a colour role span ([[role:text]])") if body.nil?
      raise Refused.new(line, "a colour role name that is not lowercase letters and hyphens") unless name.match?(ROLE_NAME)
      raise Refused.new(line, "a colour role span inside a colour role span") if outside_math(body).include?("[[")
      raise Refused.new(line, "a colour role span without text") if body.strip.empty?

      [ { "t" => "role", "role" => name, "children" => inline(body, line, roles: true) }, stop + 2 ]
    end

    # Index of the "]]" that closes a role span: a "]]" inside $...$ is LaTeX.
    def role_close(text, from)
      i = from
      while i < text.length
        if text[i] == "\\" then i += 2
        elsif text[i] == "$"
          stop = closing(text, i + 1)
          return nil if stop.nil?

          i = stop + 1
        elsif text[i] == "]" && text[i + 1] == "]" then return i
        else i += 1
        end
      end
      nil
    end

    # +text+ without its $...$ spans (a [[ inside a formula is LaTeX).
    def outside_math(text)
      out = +""
      i = 0
      while i < text.length
        if text[i] == "$" && (stop = closing(text, i + 1))
          i = stop + 1
        else
          out << text[i]
          i += 1
        end
      end
      out
    end

    def link_node(label, target, line)
      kind, id = target.split(":", 2)
      raise Refused.new(line, "a link other than scheda: or argomento:") unless LINK_KINDS.include?(kind) && !id.nil?
      raise Refused.new(line, "a link without a target") if id.empty?
      raise Refused.new(line, "a link target that is not lowercase letters, digits, dots and hyphens") unless id.match?(LINK_TARGET)
      raise Refused.new(line, "a link without text") if label.strip.empty?

      { "t" => "link", "kind" => kind, "target" => id, "children" => inline(label, line, roles: true) }
    end

    # A formula of a lesson/2 text: no command that reaches KaTeX's trust functions or redefines a macro, and
    # \role{name}{tex} with a name made of lowercase letters and hyphens.
    def check_tex(tex, line)
      if (m = tex.match(FORBIDDEN_TEX))
        raise Refused.new(line, "a command that is not allowed in a formula (\\#{m[1]})")
      end
      tex.scan(/\\role(?![A-Za-z])(.{0,80})/m).each do |(rest)|
        group = rest.match(/\A\{([^{}]*)\}\{/)
        raise Refused.new(line, "\\role takes a role name and a formula") unless group
        raise Refused.new(line, "a colour role name that is not lowercase letters and hyphens") unless group[1].match?(ROLE_NAME)
      end
    end

    # Every inline node of a lesson/2 text with the line of its paragraph or item: yields (node, line).
    def each_node(text, line_offset: 1, &block)
      walk = lambda do |nodes, line|
        nodes.each do |n|
          yield n, line
          walk.call(n["children"], line) if n["children"]
        end
      end
      raw_blocks(text, line_offset: line_offset, roles: true).each do |b|
        if b.type == :p then walk.call(inline(b.text, b.line, roles: true), b.line)
        else b.items.each { |it| ([ it[:text] ] + it[:subs]).each { |t| walk.call(inline(t, it[:line], roles: true), it[:line]) } }
        end
      end
    end

    # The colour roles a text uses, in [[role:...]] spans and \\role{name}{...} macros: [[name, line]].
    def roles_used(text, line_offset: 1)
      names = []
      each_node(text, line_offset: line_offset) do |n, line|
        case n["t"]
        when "role" then names << [ n["role"], line ]
        when "math" then n["v"].scan(/\\role\{([^{}]*)\}/) { |(name)| names << [ name, line ] }
        end
      end
      names
    end

    # The links a text holds: [[kind, target, line]].
    def links_used(text, line_offset: 1)
      links = []
      each_node(text, line_offset: line_offset) { |n, line| links << [ n["kind"], n["target"], line ] if n["t"] == "link" }
      links
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
