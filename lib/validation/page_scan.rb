# frozen_string_literal: true

module Validation
  # The `pages` rule set of the JavaScript scan (D-290, SPEC B7): a lint of the modules of a free page for E-PAGE-API and
  # E-PAGE-IMPORT. It reuses the lexer of JsScan (comments and strings blanked, a name after `.` is a property, not an
  # identifier). Pages need `window` and `document`, which the generator rule set bans, so this set works by allowlist on
  # the two globals and denylist on the rest. It is a tripwire and a reviewer's aid, NOT the boundary: what it misses still
  # runs in an opaque-origin sandbox with the CSP of the shell and holds no personal data (B11).
  module PageScan
    Hit = JsScan::Hit
    NAMESPACE_URI = %r{\Ahttp://www\.w3\.org/}
    # Strings that, as the argument of createElement, would make an element CSP does not fully cover; "a" and "base" are
    # also plain words of a lesson (a variable, a logarithm's base), so they count only as that argument.
    ELEMENT_ONLY = %w[a base].freeze
    GLOBALS = %w[window document].freeze

    module_function

    # modules: { "main.mjs" => text }; allowed_imports: the bare specifiers (banco and the declared libraries);
    # local: the module names of the bundle. Returns the hits as [file, Hit].
    def call(modules, allowed_imports:)
      local = modules.keys
      modules.flat_map do |file, source|
        scan(source, allowed_imports: allowed_imports, local: local).map { |hit| [ file, hit ] }
      end
    end

    def scan(source, allowed_imports:, local:)
      lexed = JsScan.lex(source)
      hits = import_hits(lexed, allowed_imports, local)
      hits.concat(global_hits(lexed.code))
      hits.concat(identifier_hits(lexed))
      hits.concat(string_hits(lexed))
      hits.uniq(&:rule)
    end

    def rules = Rules.get(:page, :scan)

    # ---- imports: only a relative module of the bundle, banco, or a declared library; no import() --------------------
    def import_hits(lexed, allowed, local)
      specs = lexed.no_comments.scan(/\bimport\s+(?:[\w*${},\s]+?\s+from\s+)?["']([^"'\n]+)["']/).flatten +
              lexed.no_comments.scan(/\bexport\s+[\w*${},\s]+?\s+from\s+["']([^"'\n]+)["']/).flatten
      hits = specs.reject { |s| import_ok?(s, allowed, local) }.map do |s|
        Hit.new(rule: "import #{s}", message: "import of #{s.inspect}: only a relative module of the page, banco and the libraries in libs may be imported")
      end
      hits << Hit.new(rule: "import(", message: "dynamic import( is not allowed") if lexed.code.match?(/\bimport\s*\(/)
      hits
    end

    def import_ok?(spec, allowed, local)
      return allowed.include?(spec) unless spec.start_with?("./")

      local.include?(spec.delete_prefix("./")) && spec.delete_prefix("./").match?(/\A[a-z0-9_-]+\.mjs\z/)
    end

    # ---- window and document: only window.NAME / document.NAME with NAME on the allowlist ---------------------------
    def global_hits(code)
      hits = []
      GLOBALS.each do |global|
        allow = rules.fetch("#{global}_allow")
        code.scan(/(?<![.\w$])#{global}(?![\w$])(?!\s*:(?!:))(\s*(?:\?\.|\.)\s*([A-Za-z_$][\w$]*))?/) do
          name = Regexp.last_match(2)
          next if name && allow.include?(name)

          hits << Hit.new(rule: name ? "#{global}.#{name}" : global, message: name ? "#{global}.#{name} is not available to a page" : "#{global} only as #{global}.NAME with NAME on the allowlist (no alias, no computed access)")
        end
      end
      hits
    end

    def identifier_hits(lexed)
      code = lexed.code
      hits = []
      rules.fetch("banned_identifiers").each do |name|
        next unless code.match?(/(?<![.\w$])#{Regexp.escape(name)}(?![\w$])(?!\s*:(?!:))/)

        hits << Hit.new(rule: name, message: "#{name} is not available to a page")
      end
      rules.fetch("banned_properties").each do |name|
        hits << Hit.new(rule: ".#{name}", message: ".#{name} is not available to a page (build DOM with createElement and textContent)") if code.match?(/(?:\?\.|\.)\s*#{Regexp.escape(name)}(?![\w$])/)
        hits << Hit.new(rule: "[#{name}]", message: "[#{name.inspect}] is not available to a page") if lexed.no_comments.match?(/\[\s*(["'`])#{Regexp.escape(name)}\1\s*\]/)
      end
      if code.match?(/\bMath\s*\.\s*random\b/) || code.match?(/\bMath\s*\[/)
        hits << Hit.new(rule: "Math.random", message: "Math.random is not deterministic: use banco.random()")
      end
      hits
    end

    def string_hits(lexed)
      hits = []
      exact = rules.fetch("banned_strings")
      lexed.strings.each do |text|
        hits << Hit.new(rule: "external resource", message: "a string names an external resource (#{text[0, 40].inspect})") if external?(text)
        hits << Hit.new(rule: "string #{text}", message: "the string #{text.inspect} is refused in a page") if exact.include?(text) && !ELEMENT_ONLY.include?(text)
      end
      ELEMENT_ONLY.each do |name|
        hits << Hit.new(rule: "createElement #{name}", message: "createElement(#{name.inspect}) is refused in a page") if lexed.no_comments.match?(/createElement(?:NS)?\s*\([^)]*(["'`])#{Regexp.escape(name)}\1\s*\)/)
      end
      hits
    end

    def external?(text)
      return false if text.match?(NAMESPACE_URI)

      text.match?(%r{https?://}) || text.match?(%r{(^|[^:])//[a-z0-9.-]+\.[a-z]{2,}}) || text.match?(/\Adata:/) || text.match?(/\Ablob:/)
    end
  end
end
