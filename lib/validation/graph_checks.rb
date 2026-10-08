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
      deferred(skills, index, subject, context, findings)
      citations(graph, context, findings)
      scope(skills, findings)
      scope_markers(skills, context, findings)
      other_subject_refs(skills, context, findings)
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

    # D-091: a declared edge into another subject that waits for that subject's graph.
    # It must name a skill of another subject (an edge inside this graph is a plain
    # prerequisite); when the target is already approved, it should be a plain one.
    def deferred(skills, index, subject, context, findings)
      skills.each_with_index do |s, i|
        refs = Array(s["deferred_prerequisites"]).each_with_index.map { |d, j| [ "deferred_prerequisites/#{j}/skill", d["skill"] ] }
        Array(s["errors"]).each_with_index do |e, j|
          Array(e["deferred_implicates"]).each_with_index { |d, k| refs << [ "errors/#{j}/deferred_implicates/#{k}/skill", d["skill"] ] }
        end
        refs.each do |where, target|
          field = "/skills/#{i}/#{where}"
          if target.start_with?("#{subject}.") || index.key?(target)
            findings.add("E-SCHEMA", field, "#{target} is a skill of this graph: use prerequisites or implicates", rule: "deferred_own_subject", skill: target)
          elsif context.approved_skill(target)
            findings.add("W-GRAPH-DEFERRED-APPROVED", field, "#{target} is in an approved graph now: put it in prerequisites or implicates", skill: target)
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
          citation(ref, "/skills/#{i}/refs/#{j}", context, findings)
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

    # One citation: the line exists, is the source's own content and holds the fragment (also used by
    # the course map and the lessons, whose refs have the same shape).
    def citation(ref, field, context, findings)
      line = context.source_line(ref["source"], ref["line"])
      if line.nil?
        findings.add("E-SOURCE", field, "line #{ref['line']} of #{ref['source']} does not exist", rule: "missing_line")
      elsif line[:origin] == "transcript"
        findings.add("E-SOURCE", field, "line #{ref['line']} of #{ref['source']} is a transcriber line and cannot be cited", rule: "transcript")
      elsif !line[:text].include?(ref["fragment"])
        findings.add("E-SOURCE", "#{field}/fragment", "the fragment is not an exact substring of line #{ref['line']} of #{ref['source']}", rule: "fragment")
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

        # A cited line without a marker stays in the list as nil (studied); only a
        # line the source does not have is skipped.
        markers = Array(s["refs"]).select { |r| prima_ref?(r) }.filter_map do |r|
          line = context.source_line(r["source"], r["line"])
          next unless line

          [ fragment_marker(r["fragment"], line[:text]) || line[:marker] || line[:block_marker] ]
        end.flatten(1)
        next if markers.compact.empty?

        expected = markers.flat_map { |m| Syllabus::BlockMarker.scopes_for(m) }.uniq
        next if expected.include?(s["scope"])

        seen = markers.map { |m| m || "no marker" }.uniq.join(", ")
        findings.add("W-SCOPE-MARKER", "/skills/#{i}/scope", "#{s['key']} is #{s['scope']} but the lines it cites carry #{seen} (expected #{expected.join(' or ')})", skill: s["key"], expected: expected)
      end
    end

    # A programme has one "## <subject>" section per subject. A ref into a section other
    # than the one most of the graph's refs of that source cite is probably another
    # subject's line (a next-year line of English, History...): a warning, so that the
    # author labels it (scope_reason_it naming the line number: then quiet) and the reviewer does not read it as ours.
    # No majority (a tie) or no section: quiet.
    def other_subject_refs(skills, context, findings)
      cited = []
      skills.each_with_index do |s, i|
        Array(s["refs"]).each_with_index do |ref, j|
          section = context.source_section(ref["source"], ref["line"])
          cited << [ "/skills/#{i}/refs/#{j}", ref, section ] if section
        end
      end
      cited.group_by { |_, ref, _| ref["source"] }.each_value do |group|
        counts = group.map(&:last).tally.sort_by { |_, n| -n }
        next if counts.size < 2 || counts[0][1] == counts[1][1]

        own = counts[0][0]
        group.each do |field, ref, section|
          next if section == own

          reason = skills[field[%r{\A/skills/(\d+)/}, 1].to_i]["scope_reason_it"].to_s
          next if names_line?(reason, ref["line"].to_i) # the author already named the line

          findings.add("W-REF-OTHER-SUBJECT", field, "line #{ref['line']} of #{ref['source']} is under \"#{section}\", not \"#{own}\" like most of the lines cited: say in scope_reason_it, naming line #{ref['line']} (or a range N-M that includes it), that it belongs to another subject", line: ref["line"], section: section)
        end
      end
    end

    # The reason names the line alone ("517") or inside a range "516-518" (hyphen, en or em dash).
    def names_line?(reason, line)
      return true if reason.match?(/(?<!\d)#{line}(?!\d)/)

      reason.scan(/(?<!\d)(\d+)\s*[-\u2013\u2014]\s*(\d+)(?!\d)/).any? { |a, b| (a.to_i..b.to_i).cover?(line) }
    end

    # A star inside the cited fragment itself decides first (a line can hold several
    # starred fragments without starting with a star); else the line's marker applies.
    # A fragment cited without its star takes the star that stands just before it in
    # the same sentence ("... ☆ Un mondo inquinato." cited as "Un mondo inquinato").
    def fragment_marker(fragment, text = nil)
      full = fragment.to_s.include?("\u2605")
      half = fragment.to_s.include?("\u2606")
      return "\u2605\u2606" if full && half
      return "\u2605" if full
      return "\u2606" if half

      preceding_marker(fragment.to_s, text.to_s)
    end

    def preceding_marker(fragment, text)
      at = fragment.empty? ? nil : text.index(fragment)
      return nil unless at

      sentence = text[0...at].split(/[.;!?]\s/, -1).last.to_s
      sentence[/[\u2605\u2606](?=[^\u2605\u2606]*\z)/]
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
