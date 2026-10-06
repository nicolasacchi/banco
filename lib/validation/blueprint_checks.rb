# frozen_string_literal: true

module Validation
  # The synchronous checks of a blueprint (the entry test of a subject; A-06, B-07,
  # D-038): schema and the number of starting skills, skills and pinned items that
  # exist and fit, validated items only, a pool for a redo, and a pinned (or
  # declared not assessed) answer for every skill the descent can reach.
  #
  # items: ->(revision_id string) { ItemInfo | nil }
  module BlueprintChecks
    ItemInfo = Struct.new(:id, :skills, :passed, :instances, :kind, :latest_passed_id, keyword_init: true)
    # instances: [{fingerprint:, low_guess:}]; latest_passed_id: the newest passed revision of the
    # same item (nil when unknown), for W-STALE-PIN

    module_function

    def call(blueprint, graph:, subject:, context:, items:)
      findings = Findings.new
      return findings unless SchemaCheck.call("blueprint", blueprint, findings)

      unless blueprint["subject"] == subject
        findings.add("E-SCHEMA", "/subject", "the blueprint is for #{blueprint['subject']}, submitted for #{subject}", rule: "subject")
      end
      entries(blueprint, graph, subject, context, items, findings)
      descent(blueprint, graph, context, items, findings)
      overrides(blueprint, graph, findings)
      findings
    end

    # ---- starting skills and their items -----------------------------------------

    def entries(blueprint, graph, subject, context, items, findings)
      known = graph["skills"].map { |s| s["key"] }
      blueprint["entries"].each_with_index do |entry, i|
        field = "/entries/#{i}"
        guest = entry["guest_of_subject"]
        if guest
          guest_entry(entry, field, guest, context, findings)
        elsif !known.include?(entry["skill"])
          findings.add("E-SKILL-UNKNOWN", "#{field}/skill", "#{entry['skill']} is not in the graph this blueprint is built on")
        end
        infos = pinned(entry["items"], entry["skill"], "#{field}/items", items, findings)
        infos = closed_beside_short(entry, infos, field, findings)
        pool_for_redo(entry, infos, field, findings)
      end
    end

    # A guest skill must sit in an approved graph of its subject. While that graph is
    # still a draft the entry is accepted with W-GUEST-UNAPPROVED, so that authors can
    # simulate; Approval::BlueprintGate refuses the approval until it is approved (D-129).
    def guest_entry(entry, field, guest, context, findings)
      skill = entry["skill"]
      return findings.add("E-SKILL-UNKNOWN", "#{field}/skill", "#{skill} is not in an approved graph of #{guest}") unless skill.start_with?("#{guest}.")
      return if context.approved_skill(skill)

      if context.draft_skill(skill)
        findings.add("W-GUEST-UNAPPROVED", "#{field}/skill", "#{skill} is in a graph of #{guest} that is not approved yet: the teacher cannot approve this test until it is", skill: skill)
      else
        findings.add("E-SKILL-UNKNOWN", "#{field}/skill", "#{skill} is not in an approved graph of #{guest}")
      end
    end

    # Resolves the pinned revisions of one skill; E-ITEM-NOT-PASSED for one that is
    # unknown or has no passed validation, E-SKILL-UNKNOWN for one that measures
    # another skill. Returns the infos found.
    def pinned(ids, skill, field, items, findings)
      Array(ids).each_with_index.filter_map do |id, i|
        info = items.call(id.to_s)
        if info.nil?
          findings.add("E-ITEM-NOT-PASSED", "#{field}/#{i}", "item revision #{id} does not exist", rule: "unknown", revision: id)
          next
        end
        findings.add("E-ITEM-NOT-PASSED", "#{field}/#{i}", "item revision #{id} has no passed validation", rule: "not_passed", revision: id) unless info.passed
        unless info.skills.include?(skill)
          findings.add("E-SKILL-UNKNOWN", "#{field}/#{i}", "item revision #{id} measures #{info.skills.join(', ')}, not #{skill}", rule: "item_skill", revision: id)
        end
        if info.passed && info.latest_passed_id && info.latest_passed_id.to_s != id.to_s
          findings.add("W-STALE-PIN", "#{field}/#{i}", "item revision #{id} is no longer the latest passed revision of its item: #{info.latest_passed_id} replaced it; pin #{info.latest_passed_id}",
                       rule: "stale_pin", revision: id, latest: info.latest_passed_id)
        end
        info
      end
    end

    # The engine serves only the short answer on its skill (Engine#servable?), so
    # closed items pinned beside it are never seen: W-SHORT-SKILL-CLOSED, and they do
    # not count for the redo pool. Returns the infos that can be served.
    def closed_beside_short(entry, infos, field, findings)
      return infos unless infos.any? { |i| i.kind == "short_answer" }

      closed = infos.reject { |i| i.kind == "short_answer" }
      unless closed.empty?
        findings.add("W-SHORT-SKILL-CLOSED", "#{field}/items",
                     "#{entry['skill']} holds the short answer: item(s) #{closed.map(&:id).join(', ')} are never served; give the short answer its own skill",
                     skill: entry["skill"], rule: "short_skill_closed")
      end
      infos - closed
    end

    # At least 6 distinct instances over 2 items, 3 of them hard to guess, or the
    # entry declares redo_reserve false (the teacher sees it); choice_only_reason_it
    # waives the hard-to-guess count (the first item is a choice, said and read).
    def pool_for_redo(entry, infos, field, findings)
      return if entry["redo_reserve"] == false

      instances = infos.flat_map(&:instances).uniq { |i| i[:fingerprint] }
      problems = []
      problems << "#{infos.size} item(s), at least #{Rules.get(:pool, :min_items_per_skill)} are needed" if infos.size < Rules.get(:pool, :min_items_per_skill)
      problems << "#{instances.size} distinct instance(s), at least #{Rules.get(:pool, :min_instances_per_skill)} are needed" if instances.size < Rules.get(:pool, :min_instances_per_skill)
      low = instances.count { |i| low_for?(i, entry["skill"]) }
      if entry["choice_only_reason_it"].to_s.empty? && low < Rules.get(:pool, :min_low_guess_instances)
        problems << "#{low} hard-to-guess instance(s), at least #{Rules.get(:pool, :min_low_guess_instances)} are needed"
      end
      return if problems.empty?

      findings.add("E-POOL-REDO", field, "#{entry['skill']}: #{problems.join('; ')}; or declare redo_reserve: false", skill: entry["skill"])
    end

    # A testlet instance is hard to guess per skill (low_guess_by_skill, D-096).
    def low_for?(instance, skill)
      by = instance[:low_guess_by_skill]
      by && by.key?(skill) ? by[skill] : instance[:low_guess]
    end

    # ---- the descent pool (D-038) -------------------------------------------------------

    def descent(blueprint, graph, context, items, findings)
      declared = Array(blueprint["descent"]).map { |d| d["skill"] }
      known = graph["skills"].map { |s| s["key"] }
      Array(blueprint["descent"]).each_with_index do |d, i|
        field = "/descent/#{i}"
        findings.add("E-SKILL-UNKNOWN", "#{field}/skill", "#{d['skill']} is not in the graph this blueprint is built on") unless known.include?(d["skill"])
        findings.add("E-SCHEMA", "#{field}/skill", "#{d['skill']} is a starting skill: its items are in entries", rule: "descent_entry") if blueprint["entries"].any? { |e| e["skill"] == d["skill"] }
        descent_low_guess(d, pinned(d["items"], d["skill"], "#{field}/items", items, findings), field, findings) if d["items"]
      end
      dup = declared.tally.find { |_k, n| n > 1 }&.first
      findings.add("E-SCHEMA", "/descent", "#{dup} appears twice in descent", rule: "descent_duplicate") if dup

      (descent_targets(blueprint, graph) - declared).each do |skill|
        findings.add("E-BLUEPRINT-UNPINNED-DESCENT", "/descent", "the descent can reach #{skill}: pin its items or declare it not assessed with a reason", rule: skill, skill: skill)
      end
    end

    # The first item of a skill is hard to guess (B-02) and a descent skill has no
    # choice_only_reason: the pinned items of a descent skill must hold at least one
    # hard-to-guess instance, or two lucky answers would read as demonstrated.
    def descent_low_guess(descent, infos, field, findings)
      return if infos.empty? || infos.flat_map(&:instances).any? { |i| low_for?(i, descent["skill"]) }

      findings.add("E-POOL-REDO", "#{field}/items", "#{descent['skill']}: no hard-to-guess instance among the pinned items; the first item of a skill must be hard to guess",
                   skill: descent["skill"], rule: "descent_low_guess")
    end

    # The skills the engine can serve by descent from the starting skills (the one
    # definition: Diagnosis::Plan#descent_targets).
    def descent_targets(blueprint, graph)
      plan = Diagnosis::Plan.build(blueprint: blueprint.merge("entries" => blueprint["entries"].map { |e| e.merge("items" => []) }),
                                   graph: graph, instances: [])
      plan.descent_targets
    rescue Diagnosis::Plan::Invalid
      []
    end

    def overrides(blueprint, graph, findings)
      known = graph["skills"].map { |s| s["key"] }
      Array(blueprint["kind_overrides"]).each_with_index do |o, i|
        findings.add("E-SKILL-UNKNOWN", "/kind_overrides/#{i}/skill", "#{o['skill']} is not in the graph") unless known.include?(o["skill"])
      end
    end
  end
end
