# frozen_string_literal: true

module Validation
  # A lint of agent-written JavaScript (generator.mjs, verify.mjs) for E-CODE-GLOBAL:
  # banned globals, network and navigation primitives, imports other than the two
  # libraries, external resources in string literals. It is a tripwire against
  # mistakes, not a sandbox: the real boundary is the harness page (a CSP that
  # allows no connection, stubs that throw) in a Chrome with no network, and
  # firm rule 3 (agent code never runs outside Chrome).
  #
  # The lexer blanks comments and string literals (keeping line breaks) so that a
  # banned word inside a Italian sentence ("Date", "Function") is not a hit, and
  # code inside a template literal's ${...} is still code.
  module JsScan
    Hit = Struct.new(:rule, :message, keyword_init: true)

    Lexed = Struct.new(:code, :no_comments, :strings, keyword_init: true)

    REGEX_PRECEDERS = /(?:[(,=:\[!&|?{};+\-*%<>~^]|\breturn|\btypeof)\z/

    module_function

    # Returns the Hits for +source+, using the thresholds of Validation::Rules.
    def call(source)
      lexed = lex(source)
      hits = []
      hits.concat(import_hits(lexed))
      hits.concat(identifier_hits(lexed))
      hits.concat(string_hits(lexed))
      hits.uniq(&:rule)
    end

    def import_hits(lexed)
      allowed = Rules.list(:code, :allowed_imports)
      specs = lexed.no_comments.scan(/\bimport\s+(?:[\w*${},\s]+?\s+from\s+)?["']([^"'\n]+)["']/).flatten +
              lexed.no_comments.scan(/\bexport\s+[\w*${},\s]+?\s+from\s+["']([^"'\n]+)["']/).flatten
      hits = specs.reject { |s| allowed.include?(s) }.map do |s|
        Hit.new(rule: "import #{s}", message: "import of #{s.inspect}: only #{allowed.join(' and ')} may be imported")
      end
      if lexed.code.match?(/\bimport\s*\(/)
        hits << Hit.new(rule: "import(", message: "dynamic import( is not allowed")
      end
      hits
    end

    def identifier_hits(lexed)
      code = lexed.code
      hits = []
      Rules.list(:code, :banned_identifiers).each do |name|
        # Not a property name (x.location) and not an object key ({ location: 1 }).
        next unless code.match?(/(?<![.\w$])#{Regexp.escape(name)}(?![\w$])(?!\s*:(?!:))/)

        hits << Hit.new(rule: name, message: "#{name} is not available to generators")
      end
      Rules.list(:code, :banned_members).each do |name|
        hits << Hit.new(rule: ".#{name}", message: "#{name} depends on the locale and is not available") if code.match?(/\.\s*#{Regexp.escape(name)}\b/)
      end
      Rules.list(:code, :banned_member_calls).each do |(object, member)|
        if code.match?(/\b#{Regexp.escape(object)}\s*\.\s*#{Regexp.escape(member)}\b/) || code.match?(/\b#{Regexp.escape(object)}\s*\[/)
          hits << Hit.new(rule: "#{object}.#{member}", message: "#{object}.#{member} is not deterministic: use the rng argument")
        end
      end
      hits
    end

    def string_hits(lexed)
      patterns = Rules.list(:code, :banned_string_patterns).map { |p| Regexp.new(p) }
      lexed.strings.flat_map do |text|
        patterns.select { |re| re.match?(text) }.map do |re|
          Hit.new(rule: "external resource #{re.source}", message: "a string names an external resource (#{text[0, 40].inspect})")
        end
      end
    end

    # Splits the source into code (comments and strings blanked), the source
    # without comments, and the string literals found.
    def lex(source)
      src = source.to_s
      code = +""
      keep = +""
      strings = []
      i = 0
      n = src.length
      while i < n
        c = src[i]
        two = src[i, 2]
        if two == "//"
          j = src.index("\n", i) || n
          code << " " * (j - i)
          i = j
        elsif two == "/*"
          j = src.index("*/", i + 2)
          j = j ? j + 2 : n
          chunk = src[i...j]
          code << chunk.gsub(/[^\n]/, " ")
          keep << chunk.gsub(/[^\n]/, " ")
          i = j
        elsif c == '"' || c == "'"
          j = string_end(src, i, c)
          strings << src[(i + 1)...[ j - 1, i + 1 ].max]
          code << blank(src[i...j])
          keep << src[i...j]
          i = j
        elsif c == "`"
          i = template(src, i, code, keep, strings)
        elsif c == "/" && regex_start?(code)
          j = regex_end(src, i)
          code << blank(src[i...j])
          keep << src[i...j]
          i = j
        else
          code << c
          keep << c
          i += 1
        end
      end
      Lexed.new(code: code, no_comments: strip_line_comments(src, keep), strings: strings)
    end

    # keep holds the source with block comments blanked; remove // comments too,
    # outside strings, using the same walk on that text.
    def strip_line_comments(_src, keep)
      out = +""
      i = 0
      n = keep.length
      while i < n
        c = keep[i]
        if c == '"' || c == "'"
          j = string_end(keep, i, c)
          out << keep[i...j]
          i = j
        elsif c == "`"
          j = string_end(keep, i, "`")
          out << keep[i...j]
          i = j
        elsif keep[i, 2] == "//"
          j = keep.index("\n", i) || n
          i = j
        else
          out << c
          i += 1
        end
      end
      out
    end

    def blank(text) = text.gsub(/[^\n]/, " ")

    def string_end(src, i, quote)
      j = i + 1
      while j < src.length
        ch = src[j]
        if ch == "\\"
          j += 2
        elsif ch == quote
          return j + 1
        elsif ch == "\n" && quote != "`"
          return j
        else
          j += 1
        end
      end
      src.length
    end

    # A template literal: the text parts are strings, the ${ ... } parts code.
    def template(src, i, code, keep, strings)
      j = i + 1
      text = +""
      code << " "
      keep << "`"
      while j < src.length
        ch = src[j]
        if ch == "\\"
          text << src[j, 2].to_s
          code << "  "
          keep << src[j, 2].to_s
          j += 2
        elsif ch == "`"
          strings << text
          code << " "
          keep << "`"
          return j + 1
        elsif ch == "$" && src[j + 1] == "{"
          strings << text
          text = +""
          k = matching_brace(src, j + 1)
          inner = lex(src[(j + 2)...k])
          code << "  " << inner.code << " "
          keep << "${" << src[(j + 2)...k] << "}"
          strings.concat(inner.strings)
          j = k + 1
        else
          text << ch
          code << (ch == "\n" ? "\n" : " ")
          keep << ch
          j += 1
        end
      end
      strings << text
      j
    end

    def matching_brace(src, open)
      depth = 0
      j = open
      while j < src.length
        ch = src[j]
        case ch
        when '"', "'", "`" then j = string_end(src, j, ch) - 1
        when "{" then depth += 1
        when "}"
          depth -= 1
          return j if depth.zero?
        end
        j += 1
      end
      src.length
    end

    def regex_start?(code_so_far)
      before = code_so_far.rstrip
      before.empty? || before.match?(REGEX_PRECEDERS)
    end

    def regex_end(src, i)
      j = i + 1
      in_class = false
      while j < src.length
        ch = src[j]
        if ch == "\\"
          j += 2
          next
        elsif ch == "["
          in_class = true
        elsif ch == "]"
          in_class = false
        elsif ch == "/" && !in_class
          j += 1
          j += 1 while src[j]&.match?(/[a-z]/)
          return j
        elsif ch == "\n"
          return i + 1 # not a regex after all: a division
        end
        j += 1
      end
      i + 1
    end
  end
end
