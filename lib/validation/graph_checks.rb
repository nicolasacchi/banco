# frozen_string_literal: true

module Validation
  # The synchronous checks of a skill graph (A-06, C-01): schema, a graph without
  # cycles, programme citations that are exact, scope that matches the citations,
  # every skill needed by something in the next year's programme, and cross-subject
  # edges that point into approved graphs.
  module GraphChecks
    module_function

    # Returns Findings for +graph+ (a parsed banco.skill_graph/1 document) submitted
    # for +subject+.
    def call(graph, subject:, context:)
      findings = Findings.new
      return findings unless SchemaCheck.call("skill_graph", graph, findings)

      own_subject(graph, subject, findings)
      skills = graph["skills"]
      index = skills.to_h { |s| [ s["key"], s ] }
      cycles(skills, index, findings)
      keys(skills, index, subject, findings)
      references(skills, index, subject, context, findings)
      citations(graph, context, findings)
      scope(skills, findings)
      scope_markers(skills, context, findings)
      needed_by(skills, index, findings)
      readability(skills, findings)
      findings
    end

    # D-085: the *_it texts of the skills are linted like an item's; an E-READ there is
    # only a warning (the graph is the teacher's reading text, the item copy is the block).
    def readability(skills, findings)
      lint = Findings.new
      Readability.lint_document(skills, "/skills", lint)
      lint.each do |f|
        next unless f.code == "E-READ"

        findings.add("W-GRAPH-READABILITY", f.field, f.message, rule: f.detail[:rule])
      end
    end

    def own_subject(graph, subject, findings)
      return if graph["subject"] == subject

      findings.add("E-SCHEMA", "/subject", "the graph is for #{graph['subject']}, submitted for #{subject}", rule: "subject")
    end

    def keys(skills, index, subject, findings)
      if index.size != skills.size
        dup = skills.map { |s| s["key"] }.tally.find { |_k, n| n > 1 }&.first
        findings.add("E-SCHEMA", "/skills", "the skill key #{dup} appears twice", rule: "duplicate_key")
      end
      skills.each_with_index do |s, i|
        next if s["key"].start_with?("#{subject}.")

        findings.add("E-SCHEMA", "/skills/#{i}/key", "#{s['key']} does not start with #{subject}.", rule: "key_prefix")
      end
    end

    # Prerequisites, composites and error implicates name known skills; an edge into
    # another subject needs a skill of an approved graph.
    def references(skills, index, subject, context, findings)
      skills.each_with_index do |s, i|
        refs = [ [ "prerequisites", s["prerequisites"] ], [ "composite_of", s["composite_of"] ] ]
        Array(s["errors"]).each_with_index { |e, j| refs << [ "errors/#{j}/implicates", e["implicates"] ] }
        refs.each do |where, targets|
          Array(targets).each do |target|
            next if index.key?(target)

            field = "/skills/#{i}/#{where}"
            if target.start_with?("#{subject}.")
              findings.add("E-SKILL-UNKNOWN", field, "#{target} is not a skill of this graph", skill: target)
            elsif context.approved_skill(target).nil?
              findings.add("E-GRAPH-EDGE-UNAPPROVED", field, "#{target} is not in an approved graph of its subject", skill: target)
            end
          end
        end
      end
    end

    # A cycle over prerequisites and composite parts, reported with its path.
    def cycles(skills, index, findings)
      state = {}
      visit = lambda do |key, path|
        return if state[key] == :done || !index.key?(key)

        if state[key] == :open
          findings.add("E-GRAPH-CYCLE", "/skills", "prerequisite cycle: #{(path.drop_while { |k| k != key } + [ key ]).join(' -> ')}", path: path)
          return
        end
        state[key] = :open
        s = index[key]
        (Array(s["prerequisites"]) + Array(s["composite_of"])).each { |t| visit.call(t, path + [ key ]) }
        state[key] = :done
      end
      skills.each { |s| visit.call(s["key"], []) }
    end

    # Every citation is an exact substring of a line of the programme that is the
    # source's own content (never a transcriber line); excluded lines must exist.
    def citations(graph, context, findings)
      graph["skills"].each_with_index do |s, i|
        Array(s["refs"]).each_with_index do |ref, j|
          field = "/skills/#{i}/refs/#{j}"
          line = context.source_line(ref["source"], ref["line"])
          if line.nil?
            findings.add("E-SOURCE", field, "line #{ref['line']} of #{ref['source']} does not exist", rule: "missing_line")
          elsif line[:origin] == "transcript"
            findings.add("E-SOURCE", field, "line #{ref['line']} of #{ref['source']} is a transcriber line and cannot be cited", rule: "transcript")
          elsif !line[:text].include?(ref["fragment"])
            findings.add("E-SOURCE", "#{field}/fragment", "the fragment is not an exact substring of line #{ref['line']} of #{ref['source']}", rule: "fragment")
          end
        end
      end
      Array(graph["excluded"]).each_with_index do |ex, i|
        source = Rules.get(:coverage, :prima_source)
        line = context.source_line(source, ex["line"])
        if line.nil?
          findings.add("E-SOURCE", "/excluded/#{i}/line", "line #{ex['line']} of #{source} does not exist", rule: "missing_line")
        elsif ex["fragment"] && !line[:text].include?(ex["fragment"])
          findings.add("E-SOURCE", "/excluded/#{i}/fragment", "the fragment is not an exact substring of line #{ex['line']} of #{source}", rule: "fragment")
        end
      end
    end

    def prima_ref?(ref) = ref["source"].to_s.start_with?("prima")
    def seconda_ref?(ref) = ref["source"].to_s.start_with?("seconda")

    # middle_school and not_in_prima skills cite no line of the previous year;
    # studied, integration_studied and in_progress ones cite at least one.
    def scope(skills, findings)
      skills.each_with_index do |s, i|
        prima = Array(s["refs"]).select { |r| prima_ref?(r) }
        if %w[middle_school not_in_prima].include?(s["scope"])
          findings.add("E-SCOPE", "/skills/#{i}/scope", "#{s['key']} is #{s['scope']} and cites a line of the previous year's programme", skill: s["key"]) if prima.any?
        elsif prima.empty?
          findings.add("E-SCOPE", "/skills/#{i}/scope", "#{s['key']} is #{s['scope']} but cites no line of the previous year's programme", skill: s["key"])
        end
      end
    end

    # The programme's own markers decide the scope (brief rule 3): a star line is
    # integration_studied, an empty star or both in_progress, an unmarked line
    # studied. The marker is the line's own or the one it inherits from the header of
    # its block. A warning, not an error: a skill may rightly span lines of two kinds.
    def scope_markers(skills, context, findings)
      skills.each_with_index do |s, i|
        next unless %w[studied integration_studied in_progress].include?(s["scope"])

        lines = Array(s["refs"]).select { |r| prima_ref?(r) }.filter_map { |r| context.source_line(r["source"], r["line"]) }
        next if lines.empty?

        markers = lines.map { |l| l[:marker] || l[:block_marker] }
        expected = markers.flat_map { |m| Syllabus::BlockMarker.scopes_for(m) }.uniq
        next if expected.include?(s["scope"])

        seen = markers.map { |m| m || "no marker" }.uniq.join(", ")
        findings.add("W-SCOPE-MARKER", "/skills/#{i}/scope", "#{s['key']} is #{s['scope']} but the lines it cites carry #{seen} (expected #{expected.join(' or ')})", skill: s["key"], expected: expected)
      end
    end

    # A skill needs a next-year line that requires it, directly or through a skill
    # that depends on it (transitively).
    def needed_by(skills, index, findings)
      needed = skills.select { |s| Array(s["refs"]).any? { |r| r["role"] == "needed_by" && seconda_ref?(r) } }.map { |s| s["key"] }
      reach = Set.new
      stack = needed.dup
      until stack.empty?
        k = stack.pop
        next unless reach.add?(k)

        s = index[k]
        stack.concat(Array(s["prerequisites"]) + Array(s["composite_of"])) if s
      end
      skills.each_with_index do |s, i|
        next if reach.include?(s["key"])

        findings.add("E-NEEDED-BY", "/skills/#{i}/refs", "#{s['key']} is not needed by a line of the next year's programme, directly or through a skill that depends on it", skill: s["key"])
      end
    end
  end
end
