# frozen_string_literal: true

module Validation
  # The checks on item.json and its files that need no instance: skills, sources,
  # assets, composites, accent policy, structure-only sources, quotes, the
  # readability of every Italian text and the scan of generator.mjs and verify.mjs.
  module ItemChecks
    SKILL_FIELDS_NOTE = "a skill of the subject's graph"

    module_function

    def call(item, files:, context:, findings:)
      skills(item, context, findings)
      graph_errors(item, context, findings)
      composite(item, context, findings)
      testlet_skills(item, findings)
      form_skill_closure(item, context, findings)
      sources(item, context, findings)
      assets(item, files, findings)
      accent_policy(item, findings)
      prova_a(item, findings)
      quote_ref(item.dig("prompt", "quote"), "/prompt/quote", context, findings) if item.dig("prompt", "quote").is_a?(Hash)
      Readability.lint_document(item, "", findings)
      calculator(item, findings)
      code_scan(files, findings)
    end

    # ---- E-SKILL-UNKNOWN ---------------------------------------------------------

    def skills(item, context, findings)
      unless context.graph_present?
        findings.add("E-SKILL-UNKNOWN", "/skill", "the subject #{item['subject']} has no skill graph yet: submit the graph first")
        return
      end
      each_skill_ref(item) do |path, key, own|
        skill = context.skill(key)
        if skill.nil?
          findings.add("E-SKILL-UNKNOWN", path, "#{key} is not in the graph of #{item['subject']}")
        elsif own && key.split(".").first != item["subject"]
          findings.add("E-SKILL-UNKNOWN", path, "#{key} belongs to another subject than #{item['subject']}")
        end
      end
    end

    # Yields [path, skill key, own?]: own is true for the skill an item measures.
    def each_skill_ref(item)
      yield "/skill", item["skill"], true if item["skill"]
      yield "/form_skill", item["form_skill"], false if item["form_skill"]
      Array(item["error_catalogue"]).each_with_index do |e, i|
        Array(e["implicates"]).each { |k| yield "/error_catalogue/#{i}/implicates", k, false }
      end
      Array(item["sub_items"]).each_with_index do |sub, i|
        yield "/sub_items/#{i}/skill", sub["skill"], true
        yield "/sub_items/#{i}/form_skill", sub["form_skill"], false if sub["form_skill"]
        Array(sub["error_catalogue"]).each_with_index do |e, j|
          Array(e["implicates"]).each { |k| yield "/sub_items/#{i}/error_catalogue/#{j}/implicates", k, false }
        end
      end
    end

    # ---- W-ERROR-NOT-IN-GRAPH ------------------------------------------------------------

    # The engine reads the errors of a skill from the graph alone (Plan.build_skills):
    # a code the graph does not list is unclassified (the fold descends into every parent),
    # and implicates that differ from the graph's are ignored.
    def graph_errors(item, context, findings)
      return unless context.graph_present?

      bodies = item["kind"] == "testlet" ? Array(item["sub_items"]).each_with_index.map { |b, i| [ b, "/sub_items/#{i}" ] } : [ [ item, "" ] ]
      bodies.each do |body, path|
        skill = context.skill(body["skill"]) or next
        known = Array(skill["errors"]).to_h { |er| [ er["code"], Array(er["implicates"]).sort ] }
        Array(body["error_catalogue"]).each_with_index do |entry, i|
          code = entry["code"]
          field = "#{path}/error_catalogue/#{i}"
          if !known.key?(code)
            findings.add("W-ERROR-NOT-IN-GRAPH", field,
                         "#{code} is not an error of #{body['skill']} in the graph: the engine treats it as unclassified and descends into every parent; add it to the graph first, or use a graph code",
                         code: code)
          elsif known[code] != Array(entry["implicates"]).sort
            findings.add("W-ERROR-NOT-IN-GRAPH", "#{field}/implicates",
                         "the graph says #{code} implicates #{known[code].inspect}, the item says #{Array(entry['implicates']).sort.inspect}: the engine reads the graph, the item's list is ignored",
                         code: code)
          end
        end
      end
    end

    # ---- W-FORM-SKILL-CLOSURE ----------------------------------------------------------

    # A wrong form that another skill owns gives credit and a tail suspect only when that
    # skill is inside the prerequisite closure of the item's skill (docs/rules/diagnosis-1.md).
    def form_skill_closure(item, context, findings)
      return unless context.graph_present?

      bodies = item["kind"] == "testlet" ? Array(item["sub_items"]).each_with_index.map { |b, i| [ b, "/sub_items/#{i}" ] } : [ [ item, "" ] ]
      bodies.each do |body, path|
        owner = body["form_skill"]
        next if owner.nil? || owner == body["skill"] || context.skill(owner).nil? || context.skill(body["skill"]).nil?
        next if skill_closure(context, body["skill"]).include?(owner)

        findings.add("W-FORM-SKILL-CLOSURE", "#{path}/form_skill",
                     "#{owner} is not a prerequisite, direct or transitive, of #{body['skill']}: a wrong form gets credit but no tail suspect; add the edge to the graph or drop form_skill",
                     form_skill: owner)
      end
    end

    def skill_closure(context, key)
      seen = Set.new
      stack = [ key ]
      until stack.empty?
        skill = context.skill(stack.pop) or next
        (Array(skill["prerequisites"]) + Array(skill["composite_of"])).each { |k| stack << k if seen.add?(k) }
      end
      seen
    end

    # ---- E-COMPOSITE -----------------------------------------------------------------

    # A multi-step item whose errors implicate two or more distinct prerequisites
    # must measure a composite skill that lists them.
    def composite(item, context, findings)
      bodies = item["kind"] == "testlet" ? Array(item["sub_items"]) : [ item ]
      bodies.each_with_index do |body, i|
        implicated = Array(body["error_catalogue"]).flat_map { |e| Array(e["implicates"]) }.uniq - [ body["skill"] ]
        next if implicated.size < 2

        skill = context.skill(body["skill"])
        next unless skill # E-SKILL-UNKNOWN says it

        missing = implicated - Array(skill["composite_of"])
        next if missing.empty?

        findings.add("E-COMPOSITE", item["kind"] == "testlet" ? "/sub_items/#{i}/skill" : "/skill",
                     "the errors implicate #{implicated.join(', ')} but #{body['skill']} is not a composite of #{missing.join(', ')}", missing: missing)
      end
    end

    # ---- E-TESTLET-SKILLS (D-098) ---------------------------------------------------------

    # A testlet has one attempt, attributed to its first sub item's skill (D-047), so
    # every sub item must be on that skill until sub items have attempts of their own.
    def testlet_skills(item, findings)
      return unless item["kind"] == "testlet"

      subs = Array(item["sub_items"])
      first = subs.first&.dig("skill")
      subs.each_with_index do |sub, i|
        next if sub["skill"] == first

        findings.add("E-TESTLET-SKILLS", "/sub_items/#{i}/skill",
                     "sub item #{i + 1} is on #{sub['skill']} but the testlet counts for #{first} only: put every sub item on one skill", skill: first)
      end
    end

    # ---- E-SOURCE -------------------------------------------------------------------------

    LINE_KINDS = %w[prima_line seconda_line].freeze

    def sources(item, context, findings)
      Array(item["sources"]).each_with_index do |source, i|
        next unless LINE_KINDS.include?(source["kind"])

        path = "/sources/#{i}"
        key, number = source["ref"].to_s.split(":", 2)
        line = number.to_s.match?(/\A\d+\z/) ? context.source_line(key, number.to_i) : nil
        if line.nil?
          findings.add("E-SOURCE", "#{path}/ref", "#{source['ref'].inspect} names no programme line (use source-key:line)")
        elsif line[:origin] == "transcript"
          findings.add("E-SOURCE", "#{path}/ref", "line #{number} of #{key} is a transcriber line and cannot be cited")
        elsif source["fragment"].to_s.empty?
          findings.add("E-SOURCE", "#{path}/fragment", "a programme-line source needs the fragment it relies on")
        elsif !line[:text].include?(source["fragment"])
          findings.add("E-SOURCE", "#{path}/fragment", "the fragment is not an exact substring of line #{number} of #{key}")
        end
      end
    end

    # ---- E-ASSET ----------------------------------------------------------------------------

    def assets(item, files, findings)
      declared = Array(item["assets"]).map { |a| a["file"] }
      declared.each_with_index do |file, i|
        findings.add("E-ASSET", "/assets/#{i}/file", "#{file} is declared but not submitted") unless files.key?(file)
      end
      files.each do |name, text|
        next unless name.start_with?("assets/")

        field = "/#{name}"
        findings.add("E-ASSET", field, "an asset has no source: declare it in assets[]") unless declared.include?(name)
        findings.add("E-ASSET", field, "only SVG figures are accepted in 1a") unless name.end_with?(".svg")
        if text.bytesize > Rules.get(:files, :max_asset_bytes)
          findings.add("E-ASSET", field, "an asset is at most #{Rules.get(:files, :max_asset_bytes) / 1024} KB")
        end
        svg_problem(text)&.then { |problem| findings.add("E-ASSET", field, problem) } if name.end_with?(".svg")
      end
      figure = item.dig("prompt", "figure", "asset")
      findings.add("E-ASSET", "/prompt/figure/asset", "the figure #{figure} is not among the submitted assets") if figure && !files.key?(figure)
    end

    def svg_problem(text)
      if text.match?(/<script/i) then "an SVG carries a script"
      elsif text.match?(/\son\w+\s*=/i) then "an SVG carries an on* handler"
      elsif text.match?(/<foreignObject/i) then "an SVG carries foreignObject"
      elsif text.match?(/(?:xlink:)?href\s*=\s*["']\s*(?!#)/i) || text.match?(/url\(\s*["']?(?!#)/i) || text.match?(/@import/i)
        "an SVG refers to something outside itself"
      end
    end

    # ---- E-ACCENT-POLICY ----------------------------------------------------------------------

    # accent_policy flag says accents are not measured; declaring the unaccented
    # form of the key as another word (a paradigm form) says they are.
    def accent_policy(item, findings)
      bodies = item["kind"] == "testlet" ? Array(item["sub_items"]).each_with_index.map { |b, i| [ b, "/sub_items/#{i}" ] } : [ [ item, "" ] ]
      bodies.each do |body, path|
        policy = body["accent_policy"]
        forms = Array(body["paradigm_forms"])
        if (policy || forms.any?) && body["component"] != "normalized_text"
          findings.add("E-ACCENT-POLICY", "#{path}/accent_policy", "accent_policy and paradigm_forms belong to normalized_text items")
          next
        end
        if body["component"] == "number"
          Array(body["accept"]).each_with_index do |v, i|
            findings.add("E-SCHEMA", "#{path}/accept/#{i}", "an accepted value of a number item is a finite decimal such as \"273,15\"", rule: "accept_number") unless (r = Answers.rational(v)) && Answers.decimal_string(r)
          end
        end
        if body["component"] == "normalized_text"
          Array(body["accept"]).each_with_index do |text, i|
            findings.add("E-SCHEMA", "#{path}/accept/#{i}", "an accepted text that is only punctuation normalizes to nothing: no answer could match it") if Answers.punctuation_only?(text)
          end
        end
        next unless policy == "flag" && forms.any?

        keys = Array(body["instances"]).map { |i| i["answer"].to_s } + Array(body["accept"])
        clash = keys.find { |k| forms.any? { |f| f != k && fold(f) == fold(k) } }
        if clash
          findings.add("E-ACCENT-POLICY", "#{path}/accent_policy", "accent_policy flag says accents are not measured, but #{clash.inspect} and a paradigm form differ only by accents")
        end
      end
    end

    def fold(text) = text.to_s.unicode_normalize(:nfd).gsub(/[̀-ͯ]/, "").downcase

    # ---- E-PROVA-A-PARAMS -----------------------------------------------------------------------

    # An item that takes only the structure of last year's exam must have new
    # numbers; a list of instances is fixed numbers, so it needs a generator.
    def prova_a(item, findings)
      return unless Array(item["sources"]).any? { |s| s["kind"] == "prova_a_structure" }

      static = Array(item["instances"]).any? || Array(item["sub_items"]).any? { |s| Array(s["instances"]).any? }
      return unless static

      findings.add("E-PROVA-A-PARAMS", "/instances", "an item built on last year's exam structure takes new numbers: write a generator, not listed instances")
    end

    # The item's `exclude_params`: values of last year's exam that no instance may show or
    # have as the key or an error value. An entry is matched in the display, the answer and
    # the error values with whitespace, `$`, `\\left`/`\\right` and braces-free spacing
    # removed; an entry that starts or ends with a digit does not match inside a longer number.
    def excluded_params(item, inst, label, findings, seed: nil)
      list = Array(item["exclude_params"])
      return if list.empty?

      text = squash_params(JSON.generate([ inst["display"], inst["answer"], inst["errors"] ]))
      list.each do |entry|
        needle = squash_params(entry)
        next if needle.empty?

        re = Regexp.new((needle.match?(/\A\d/) ? '(?<![\d.,])' : "") + Regexp.escape(needle) + (needle.match?(/\d\z/) ? '(?![\d])' : ""))
        next unless text.match?(re)

        findings.add("E-PROVA-A-PARAMS", label, "an instance shows #{entry.inspect}, which the item excludes (a number of last year's exam)", rule: "excluded", seed: seed)
      end
    end

    def squash_params(text) = text.to_s.gsub(/\\left|\\right|\\[,;:! ]|[\s$]/, "")

    # ---- E-QUOTE-REF ------------------------------------------------------------------------------

    def quote_ref(quote, field, context, findings, seed: nil)
      body = context.reference_body(quote["ref"].to_s)
      if body.nil?
        findings.add("E-QUOTE-REF", "#{field}/ref", "#{quote['ref'].inspect} is not an imported reference text", seed: seed)
      elsif !squish(body).include?(squish(quote["text"]))
        findings.add("E-QUOTE-REF", "#{field}/text", "the quotation is not an exact substring of the reference text", seed: seed)
      end
    end

    def squish(text) = text.to_s.gsub(/\s+/, " ").strip

    # ---- W-CALCULATOR -------------------------------------------------------------------------------

    def calculator(item, findings)
      return unless Rules.list(:readability, :calculator_subjects).include?(item["subject"])

      bodies = item["kind"] == "testlet" ? Array(item["sub_items"]).each_with_index.map { |b, i| [ b, "/sub_items/#{i}" ] } : [ [ item, "" ] ]
      bodies.each do |body, path|
        next unless %w[number fraction expression].include?(body["component"])
        next if body["calculation"] == false # D-106: a counting or reading item has no arithmetic to allow

        stem = body.dig("prompt", "stem_it").to_s
        next if stem.downcase.include?(Rules.get(:readability, :calculator_sentence))

        findings.add("W-CALCULATOR", "#{path}/prompt/stem_it", "a numeric item in #{item['subject']} says whether the calculator is allowed")
      end
    end

    # ---- E-CODE-GLOBAL ---------------------------------------------------------------------------------

    def code_scan(files, findings)
      %w[generator.mjs verify.mjs].each do |name|
        next unless files.key?(name)

        JsScan.call(files[name]).each do |hit|
          findings.add("E-CODE-GLOBAL", "/#{name}", hit.message, rule: "#{name}: #{hit.rule}")
        end
      end
    end
  end
end
