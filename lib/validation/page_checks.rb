# frozen_string_literal: true

require "zlib"

module Validation
  # The static checks of a free page bundle at submit and dry run (D-290, SPEC B7): the manifest schema, the allowlist of
  # files and the budgets, the SVG checks of item figures, style.css, the readability of the texts, the `pages` rule set
  # of the JavaScript scan, the private hygiene terms. Nothing is written and nothing is run: Chrome comes later
  # (PageRunner). Thresholds: config/banco/validation_rules.yml, block page.
  module PageChecks
    Outcome = Struct.new(:findings, :manifest, :infos, :bundle_sha256, :hygiene_checked, keyword_init: true)

    ROOT_MODULE = /\A[a-z0-9_-]+\.mjs\z/
    ASSET = %r{\Aassets/[A-Za-z0-9_-]+\.(svg|png|webp|jpe?g)\z}
    WORD = /[\p{L}\p{N}][\p{L}\p{N}'’_-]*/
    MAGIC = {
      "png" => ->(b) { b.byteslice(0, 8) == "\x89PNG\r\n\x1a\n".b },
      "webp" => ->(b) { b.byteslice(0, 4) == "RIFF" && b.byteslice(8, 4) == "WEBP" },
      "jpg" => ->(b) { b.byteslice(0, 3) == "\xFF\xD8\xFF".b },
      "jpeg" => ->(b) { b.byteslice(0, 3) == "\xFF\xD8\xFF".b }
    }.freeze

    module_function

    # files: { "page.json" => bytes, "main.mjs" => bytes, ... }; key: the page key the submit names; subject: the subject key.
    # operator: true is the console task alone (bin/rails banco:pages_selftest); a reserved key is refused without it.
    # scan: false leaves out the JavaScript scan: only the operator's console stores the browser matrix page, which uses the APIs on purpose.
    def call(files, key:, subject:, scan: true, operator: false)
      findings = Findings.new
      if Pages::Submit.reserved?(key) && !operator
        findings.add("E-PAGE-TEXT", "/page.json/key", "the key #{key} is reserved for the operator's browser matrix page", rule: "key")
      end
      files = files.transform_values { |v| v.to_s.b }
      manifest = parse_manifest(files.delete("page.json"), key, subject, findings)
      names(files, findings)
      budgets(files, findings)
      assets(files, findings)
      style(files, findings)
      libs(manifest, findings) if manifest
      texts(manifest, findings) if manifest
      scan(files, manifest, findings) if scan
      checked = hygiene(files, manifest, findings)
      infos = Pages::Bundle.infos(files)
      sha = manifest && !findings.any_error? ? Pages::Bundle.sha256(manifest, infos) : nil
      Outcome.new(findings: findings, manifest: manifest, infos: infos, bundle_sha256: sha, hygiene_checked: checked)
    end

    def rules(*path) = Rules.get(:page, *path)

    # ---- page.json ----------------------------------------------------------------------------------------------
    def parse_manifest(bytes, key, subject, findings)
      unless bytes
        findings.add("E-PAGE-FILES", "/page.json", "page.json is missing: banco page open KEY gives the skeleton")
        return nil
      end
      manifest = JSON.parse(bytes.dup.force_encoding("UTF-8"))
      unless manifest.is_a?(Hash)
        findings.add("E-SCHEMA", "/page.json", "page.json must be an object")
        return nil
      end
      SchemaCheck.call("page", manifest, findings, prefix: "/page.json")
      if manifest["key"].is_a?(String) && manifest["key"] != key
        findings.add("E-PAGE-TEXT", "/page.json/key", "the manifest key #{manifest['key'].inspect} differs from the page #{key}", rule: "key")
      end
      if manifest["subject"].is_a?(String) && (manifest["subject"] != subject || !key.start_with?("#{subject}."))
        findings.add("E-PAGE-TEXT", "/page.json/subject", "the subject #{manifest['subject'].inspect} differs from the subject of the key #{key} (#{subject})", rule: "subject")
      end
      manifest
    rescue JSON::ParserError => e
      findings.add("E-SCHEMA", "/page.json", "page.json is not valid JSON: #{e.message.lines.first.to_s.strip.first(120)}")
      nil
    end

    # ---- files: allowlist ------------------------------------------------------------------------------------------
    def names(files, findings)
      findings.add("E-PAGE-FILES", "/main.mjs", "main.mjs is the entry module and is required") unless files.key?("main.mjs")
      modules = files.keys.select { |n| n.match?(ROOT_MODULE) }
      if modules.size - (files.key?("main.mjs") ? 1 : 0) > rules(:max_extra_modules)
        findings.add("E-PAGE-FILES", "/", "at most #{rules(:max_extra_modules)} modules besides main.mjs (#{modules.size - 1} sent)")
      end
      files.each_key do |name|
        next if name == "main.mjs" || name == "style.css" || name.match?(ROOT_MODULE) || name.match?(ASSET)

        reason =
          if name.match?(/\.(glb|gltf|json|bin)\z/i) then "#{name.split('.').last} files are loaded with fetch, which connect-src 'none' blocks: keep data in a module (export const data = ...)"
          elsif name.match?(/\.html?\z/i) then "no HTML file: the shell is generated"
          else "this file is not in the allowlist (page.json, *.mjs, one style.css, assets/*.svg|png|webp|jpg)"
          end
        findings.add("E-PAGE-FILES", "/#{name}", reason)
      end
    end

    def budgets(files, findings)
      raw = files.values.sum(&:bytesize)
      gz = Zlib.gzip(files.sort.map { |n, b| b }.join).bytesize
      findings.add("E-PAGE-SIZE", "/", "the files are #{raw / 1024} KB (at most #{rules(:max_total_bytes) / 1024} KB)", rule: "raw") if raw > rules(:max_total_bytes)
      findings.add("E-PAGE-SIZE", "/", "the files are #{gz / 1024} KB gzipped (at most #{rules(:max_gzip_bytes) / 1024} KB)", rule: "gzip") if gz > rules(:max_gzip_bytes)
      files.each do |name, bytes|
        findings.add("E-PAGE-SIZE", "/#{name}", "an asset is at most #{rules(:max_asset_bytes) / 1024} KB", rule: "asset") if name.start_with?("assets/") && bytes.bytesize > rules(:max_asset_bytes)
        findings.add("E-PAGE-SIZE", "/#{name}", "a module is at most #{rules(:max_module_bytes) / 1024} KB", rule: "module") if name.end_with?(".mjs") && bytes.bytesize > rules(:max_module_bytes)
      end
    end

    def assets(files, findings)
      files.each do |name, bytes|
        next unless (m = name.match(ASSET))

        ext = m[1]
        if ext == "svg"
          text = bytes.dup.force_encoding("UTF-8")
          problem = ItemChecks.svg_problem(text) || (text.valid_encoding? ? nil : "an SVG is not UTF-8 text")
          findings.add("E-PAGE-FILES", "/#{name}", problem, rule: "svg") if problem
        elsif !MAGIC.fetch(ext).call(bytes)
          findings.add("E-PAGE-FILES", "/#{name}", "the bytes are not a #{ext.upcase} image", rule: "magic")
        end
      end
    end

    def style(files, findings)
      css = files["style.css"] or return
      text = css.dup.force_encoding("UTF-8")
      findings.add("E-PAGE-CSS", "/style.css", "@import is not allowed: one style.css, nothing else", rule: "import") if text.match?(/@import/i)
      text.scan(/url\(\s*(["']?)([^"')]*)\1\s*\)/i).each do |(_, target)|
        next if target.match?(%r{\A(assets/[A-Za-z0-9_-]+\.(svg|png|webp|jpe?g))\z}) && files.key?(target)

        findings.add("E-PAGE-CSS", "/style.css", "url(#{target[0, 40]}) is not a file of the bundle (assets/NAME.svg|png|webp|jpg)", rule: "url")
      end
    end

    # ---- libs --------------------------------------------------------------------------------------------------------
    def libs(manifest, findings)
      Array(manifest["libs"]).each_with_index do |spec, i|
        findings.add("E-PAGE-LIBS", "/page.json/libs/#{i}", "#{spec} is not a library the server vendors (config/banco/pages_libs.yml)") unless Pages::Libs.parse(spec)
      end
      declared = Array(manifest["libs"]).filter_map { |s| Pages::Libs.parse(s) }
      addons = declared.select { |d| d[:addon] }
      addons.each { |a| findings.add("E-PAGE-LIBS", "/page.json/libs", "#{a[:name]}-addons@#{a[:version]} needs #{a[:name]}@#{a[:version]} in libs too") unless declared.any? { |d| d[:name] == a[:name] && !d[:addon] } }
    end

    # ---- texts ----------------------------------------------------------------------------------------------------------
    def texts(manifest, findings)
      words = ->(field) { manifest[field].to_s.scan(WORD).size }
      limits = rules(:words)
      if manifest["instructions_it"].is_a?(String) && words.call("instructions_it") > limits["instructions_max"]
        findings.add("E-PAGE-TEXT", "/page.json/instructions_it", "instructions_it has #{words.call('instructions_it')} words (at most #{limits['instructions_max']})", rule: "words")
      end
      { "alt_it" => limits["alt"], "fallback_it" => limits["fallback"] }.each do |field, (lo, hi)|
        next unless manifest[field].is_a?(String)

        n = words.call(field)
        findings.add("E-PAGE-TEXT", "/page.json/#{field}", "#{field} has #{n} words (#{lo} to #{hi})", rule: "words") unless (lo..hi).cover?(n)
      end
      Readability.lint_document(manifest.slice("title_it", "why_free_it", "instructions_it", "alt_it", "fallback_it"), "/page.json", findings)
    end

    # ---- code -----------------------------------------------------------------------------------------------------------
    def scan(files, manifest, findings)
      modules = files.select { |n, _| n.match?(ROOT_MODULE) }.transform_values { |b| b.dup.force_encoding("UTF-8").scrub }
      declared = Array(manifest&.dig("libs")).filter_map { |s| Pages::Libs.parse(s) }
      allowed = [ "banco" ] + Pages::Libs.specifiers(Array(manifest&.dig("libs")))
      PageScan.call(modules, allowed_imports: allowed).each do |file, hit|
        if hit.rule.start_with?("import")
          spec = hit.rule.delete_prefix("import ")
          known = Pages::Libs.all_specifiers.include?(spec)
          findings.add(known ? "E-PAGE-LIBS" : "E-PAGE-IMPORT", "/#{file}", known ? "#{spec} is imported but its library is not in libs of page.json" : hit.message, rule: hit.rule)
        else
          findings.add("E-PAGE-API", "/#{file}", hit.message, rule: hit.rule)
        end
      end
      _ = declared
    end

    # ---- hygiene ---------------------------------------------------------------------------------------------------------
    # The private terms, when the server has the list (BANCO_HYGIENE_TERMS_FILE); true when it was checked.
    def hygiene(files, manifest, findings)
      path = ENV["BANCO_HYGIENE_TERMS_FILE"].presence
      return false unless path && File.file?(path)

      terms = File.readlines(path, chomp: true).map(&:strip).reject { |t| t.empty? || t.start_with?("#") }.map(&:downcase)
      texts = files.select { |n, _| n.match?(ROOT_MODULE) || n == "style.css" || n.end_with?(".svg") }.transform_values { |b| b.dup.force_encoding("UTF-8").scrub.downcase }
      texts["page.json"] = JSON.generate(manifest).downcase if manifest
      texts.each do |name, text|
        hit = terms.find { |t| text.include?(t) }
        findings.add("E-PAGE-HYGIENE", "/#{name}", "the file carries a private term (the list is not shown)", rule: "hygiene") if hit
      end
      true
    end
  end
end
