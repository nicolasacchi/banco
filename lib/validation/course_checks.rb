# frozen_string_literal: true

module Validation
  # The synchronous checks of a course map (banco.course/1, A2.2): schema, the seconda skills beside the graph
  # (one key namespace), citations of the seconda programme, an acyclic union with the graph, and the ordered
  # topics. The map is validated against the subject's latest graph (+graph+, a parsed banco.skill_graph/1).
  # Nothing is written.
  module CourseChecks
    module_function

    def call(doc, subject:, graph:, context:)
      findings = Findings.new
      return findings unless SchemaCheck.call("course", doc, findings)

      if doc["subject"] != subject
        findings.add("E-SCHEMA", "/subject", "the course map is for #{doc['subject']}, submitted for #{subject}", rule: "subject")
        return findings
      end
      graph_index = graph["skills"].index_by { |s| s["key"] }
      skills = doc["skills"]
      own_keys(skills, subject, graph_index, findings)
      citations(skills, context, findings)
      references(skills, graph_index, context, findings)
      cycles(skills, graph, findings)
      topics(doc, subject, skills, graph_index, findings)
      Readability.lint_document(doc.slice("notes_it", "skills", "topics"), "", findings)
      findings
    end

    # E-COURSE-SKILL-DUPLICATE: a course skill is new: not in the graph, not twice.
    def own_keys(skills, subject, graph_index, findings)
      seen = {}
      skills.each_with_index do |s, i|
        key = s["key"]
        findings.add("E-SCHEMA", "/skills/#{i}/key", "#{key} does not start with #{subject}.", rule: "key_prefix") unless key.start_with?("#{subject}.")
        if graph_index.key?(key)
          findings.add("E-COURSE-SKILL-DUPLICATE", "/skills/#{i}/key", "#{key} is already a skill of the #{subject} graph", rule: "graph-#{key}", skill: key)
        elsif seen.key?(key)
          findings.add("E-COURSE-SKILL-DUPLICATE", "/skills/#{i}/key", "#{key} appears twice in the map (also at /skills/#{seen[key]})", rule: "twice-#{key}", skill: key)
        end
        seen[key] ||= i
      end
    end

    # Every course skill is taught in the seconda programme (a taught_in ref on that source), and every citation is exact.
    def citations(skills, context, findings)
      seconda = Rules.get(:course, :seconda_source)
      skills.each_with_index do |s, i|
        s["refs"].each_with_index { |ref, j| GraphChecks.citation(ref, "/skills/#{i}/refs/#{j}", context, findings) }
        next if s["refs"].any? { |r| r["source"] == seconda && r["role"] == "taught_in" }

        findings.add("E-SOURCE", "/skills/#{i}/refs", "#{s['key']} needs a taught_in ref on #{seconda}", rule: "taught_in", skill: s["key"])
      end
    end

    # Prerequisites, composite parts and implicated skills: the map, the graph, or an approved graph of another subject.
    def references(skills, graph_index, context, findings)
      map_keys = skills.to_set { |s| s["key"] }
      skills.each_with_index do |s, i|
        refs = [ [ "prerequisites", s["prerequisites"] ], [ "composite_of", s["composite_of"] ] ]
        s["errors"].each_with_index { |e, j| refs << [ "errors/#{j}/implicates", e["implicates"] ] }
        refs.each do |where, targets|
          Array(targets).each do |target|
            next if map_keys.include?(target) || graph_index.key?(target) || context.approved_skill(target)

            findings.add("E-SKILL-UNKNOWN", "/skills/#{i}/#{where}", "#{target} is not a skill of this map, of the #{context.subject} graph, or of an approved graph of another subject", skill: target)
          end
        end
      end
    end

    # The union of the graph's edges and the map's has no cycle.
    def cycles(skills, graph, findings)
      merged = graph["skills"] + skills.reject { |s| graph["skills"].any? { |g| g["key"] == s["key"] } }
      GraphChecks.cycles(merged, merged.to_h { |s| [ s["key"], s ] }, findings)
    end

    def topics(doc, subject, skills, graph_index, findings)
      topics = doc["topics"]
      known = skills.to_set { |s| s["key"] } | graph_index.keys
      keys = topics.map { |t| t["key"] }
      owner = {}
      topics.each_with_index do |t, i|
        field = "/topics/#{i}"
        kind, owner_subject, = t["key"].split(".", 3)
        bad = lambda do |why, rule|
          findings.add("E-COURSE-TOPIC", field, "#{t['key']}: #{why}", rule: "#{rule}-#{t['key']}")
        end
        bad.call("the key starts with #{kind} but kind is #{t['kind']}", "kind") if kind != t["kind"]
        bad.call("the key is for #{owner_subject}, the map is for #{subject}", "subject") if owner_subject != subject
        bad.call("the topic appears twice", "duplicate") if keys.count(t["key"]) > 1 && keys.index(t["key"]) != i
        t["skills"].each do |sk|
          bad.call("#{sk} is not a skill of #{subject}", "other-subject-#{sk}") unless sk.start_with?("#{subject}.")
          bad.call("#{sk} is not a skill of the graph or of this map", "unknown-#{sk}") unless known.include?(sk)
          if owner.key?(sk) && owner[sk] != t["key"]
            bad.call("#{sk} is already in #{owner[sk]}: a skill is in at most one topic", "twice-#{sk}")
          end
          owner[sk] ||= t["key"]
        end
        t["after"].each do |a|
          bad.call("after names #{a}, which is not a topic of this map", "after-#{a}") unless keys.include?(a)
          bad.call("a topic cannot come after itself", "after-self") if a == t["key"]
        end
      end
      after_cycle(topics, findings)
      order(topics, skills, graph_index, owner, findings)
    end

    def after_cycle(topics, findings)
      edges = topics.to_h { |t| [ t["key"], t["after"] ] }
      state = {}
      visit = lambda do |key, path|
        return if state[key] == :done || !edges.key?(key)

        if state[key] == :open
          findings.add("E-COURSE-TOPIC", "/topics", "after forms a cycle: #{(path.drop_while { |k| k != key } + [ key ]).join(' -> ')}", rule: "after-cycle")
          return
        end
        state[key] = :open
        edges[key].each { |t| visit.call(t, path + [ key ]) }
        state[key] = :done
      end
      edges.each_key { |k| visit.call(k, []) }
    end

    # W-COURSE-ORDER: the list is the recommended order; a topic before an after topic or before the holder of a direct prerequisite.
    def order(topics, skills, graph_index, owner, findings)
      position = topics.each_with_index.to_h { |t, i| [ t["key"], i ] }
      index = graph_index.merge(skills.to_h { |s| [ s["key"], s ] })
      topics.each_with_index do |t, i|
        t["after"].each do |a|
          findings.add("W-COURSE-ORDER", "/topics/#{i}", "#{t['key']} comes before #{a}, which it must follow", rule: "after-#{t['key']}-#{a}") if position[a] && position[a] > i
        end
        t["skills"].flat_map { |sk| Array(index.dig(sk, "prerequisites")) }.uniq.each do |pre|
          holder = owner[pre]
          next if holder.nil? || holder == t["key"] || position[holder].nil? || position[holder] < i

          findings.add("W-COURSE-ORDER", "/topics/#{i}", "#{t['key']} comes before #{holder}, which teaches the prerequisite #{pre}", rule: "prereq-#{t['key']}-#{pre}")
        end
      end
    end
  end
end
