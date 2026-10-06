# frozen_string_literal: true

require "digest"
require "set"

module Diagnosis
  # What the engine needs besides the log: the pinned blueprint, the skill graph
  # and the pool of instances, as plain data. Built by Plan.build from parsed JSON
  # (banco.blueprint/1, banco.skill_graph/1) or by the ActiveRecord loader.
  # No I/O here.
  class Plan
    class Invalid < StandardError; end
    class CycleError < Invalid; end

    # One servable instance. skills has one entry, except a testlet (one per
    # sub-item). fingerprint is what "seen" is compared on.
    # flags: for a testlet {skill => {low_guess:, choice:}} from its sub items (D-096); nil otherwise.
    Instance = Data.define(:id, :item, :skills, :component, :low_guess, :choice, :expected_seconds, :fingerprint, :kind, :flags) do
      def initialize(flags: nil, **rest) = super(flags: flags, **rest)

      # Whether the instance is hard to guess / a choice for this skill: a testlet
      # decides per skill, any other instance for all of its skills.
      def low_guess_for(skill) = flags&.dig(skill, :low_guess).then { |v| v.nil? ? low_guess : v }
      def choice_for(skill) = flags&.dig(skill, :choice).then { |v| v.nil? ? choice : v }
      def skill = skills.first
      def testlet? = kind == "testlet"
      def short_answer? = kind == "short_answer"
    end

    # items: the blueprint's item ids for the skill, in the order the author wants
    # them served (D-138); [] when the plan does not know them.
    Entry = Data.define(:skill, :guest_of, :choice_only, :items) do
      def initialize(skill:, guest_of:, choice_only:, items: [])
        super(skill: skill, guest_of: guest_of, choice_only: choice_only, items: items.map(&:to_s).freeze)
      end
    end

    SkillDef = Data.define(:key, :subject, :scope, :kind, :prerequisites, :composite_of, :errors) do
      # Everything this skill rests on: prerequisites and the parts of a composite.
      def parents = (prerequisites + composite_of).uniq
    end

    attr_reader :subject, :entries, :skills, :pool, :sitting_seconds, :sittings, :seed_salt, :external, :seen

    # external: {skill_key => {"state"=>, "reason"=>}} of skills resolved in other
    # non-voided runs. seen: fingerprints the student saw in any run.
    def initialize(subject:, entries:, skills:, pool:, sitting_seconds:, sittings:, seed_salt: "", external: {}, seen: [])
      @subject = subject
      @entries = entries.freeze
      @skills = skills.freeze
      @pool = pool.freeze
      @sitting_seconds = sitting_seconds
      @sittings = sittings
      @seed_salt = seed_salt.to_s
      @external = external.freeze
      @seen = seen.to_set.freeze
      @closures = {}
      @by_skill = {}
      raise Invalid, "no entries" if @entries.empty?

      check_acyclic!
    end

    def skill(key) = @skills[key]
    def entry(key) = @entries.find { |e| e.skill == key }
    def short_instance = @short_instance ||= @pool.values.find(&:short_answer?)
    def short_skill = short_instance&.skill

    # Instances that can be served for a skill, in a fixed order that depends on
    # the run's seed salt (short answers are served on their own slot).
    def instances_for(key)
      @by_skill[key] ||= @pool.values.select { |i| i.skills.include?(key) && !i.short_answer? }
                              .sort_by { |i| Digest::SHA256.hexdigest("#{@seed_salt}|#{key}|#{i.fingerprint}") }
    end

    # Transitive parents of a skill (not the skill itself).
    def closure(key)
      @closures[key] ||= begin
        seen = Set.new
        stack = (@skills[key]&.parents || []).dup
        until stack.empty?
          k = stack.pop
          next unless seen.add?(k)

          stack.concat(@skills[k].parents) if @skills[k]
        end
        seen.freeze
      end
    end

    # Skills the descent can reach from the entries (parents and the implicates of
    # typical errors), plus testlet siblings and the short answer's skill.
    def reachable
      seen = Set.new
      stack = @entries.map(&:skill)
      until stack.empty?
        k = stack.pop
        next unless seen.add?(k)

        d = @skills[k]
        next unless d

        stack.concat(d.parents)
        d.errors.each_value { |imp| stack.concat(imp) }
      end
      @pool.each_value { |i| seen.merge(i.skills) if i.skills.any? { |s| seen.include?(s) } }
      seen << short_skill if short_skill
      seen
    end

    # The skills the descent can serve that are not starting skills: parents and
    # the implicates of typical errors, transitively, in this subject, never an
    # in_progress skill (Fold#descendable?). The blueprint must pin items for each,
    # or declare it not assessed with a reason the teacher sees (D-034,
    # E-BLUEPRINT-UNPINNED-DESCENT). The walk goes on through an in_progress skill
    # on purpose: a suspect below it can still be queued.
    def descent_targets
      seen = Set.new
      stack = @entries.map(&:skill)
      until stack.empty?
        k = stack.pop
        next unless seen.add?(k)

        d = @skills[k]
        next unless d

        stack.concat(d.parents)
        d.errors.each_value { |imp| stack.concat(imp) }
      end
      entry_keys = @entries.map(&:skill)
      (seen.to_a - entry_keys).select do |k|
        d = @skills[k]
        d && d.subject == @subject && d.scope != "in_progress" && k != short_skill
      end.sort
    end

    # ---- construction from parsed JSON ------------------------------------

    DEFAULT_INSTANCES_PER_ITEM = 3

    class << self
      # A simulation bundle: {"blueprint"=>, "graph"=>?, "pool"=>?, "external"=>?,
      # "seen"=>?, "seed_salt"=>?}, or a bare banco.blueprint/1 document. Raises
      # Invalid with the offending field when the document cannot be a plan.
      def from_bundle(doc)
        raise Invalid, "blueprint: the file is not a JSON object" unless doc.is_a?(Hash)

        bundle = doc.key?("blueprint") ? doc : { "blueprint" => doc }
        bp = bundle["blueprint"]
        raise Invalid, "blueprint: not an object" unless bp.is_a?(Hash)
        raise Invalid, "blueprint.subject: unknown subject" unless Rules::V1::SUBJECTS.include?(bp["subject"])
        entries = bp["entries"]
        unless entries.is_a?(Array) && entries.any? && entries.all? { |e| e.is_a?(Hash) && e["skill"].to_s.match?(Rules::V1::SKILL_KEY_PATTERN) }
          raise Invalid, "blueprint.entries: a list of {skill, items} is required"
        end
        entries.each { |e| e["items"] = Array(e["items"]) }
        raise Invalid, "graph: not an object with skills" if bundle["graph"] && !(bundle["graph"].is_a?(Hash) && bundle["graph"]["skills"].is_a?(Array))

        build(blueprint: bp, graph: bundle["graph"], pool: bundle["pool"], external: bundle["external"] || {},
              seen: bundle["seen"] || [], seed_salt: bundle["seed_salt"] || "sim")
      end

      # blueprint: banco.blueprint/1 hash (string keys). graph: banco.skill_graph/1
      # hash, or nil for a flat subject (the entries only). pool: nil, or a hash
      # {item_id => {"component"=>, "instances"=>n, "skills"=>[...], "kind"=>,
      # "expected_seconds"=>, "choice"=>bool}}; what it does not say is
      # synthesized, so a blueprint alone can be simulated.
      def build(blueprint:, graph: nil, pool: nil, external: {}, seen: [], seed_salt: "sim", instances: nil)
        subject = blueprint.fetch("subject")
        overrides = (blueprint["kind_overrides"] || []).to_h { |o| [ o["skill"], o["kind"] ] }
        skills = build_skills(graph, overrides)
        entries = blueprint.fetch("entries").map do |e|
          Entry.new(skill: e["skill"], guest_of: e["guest_of_subject"], choice_only: e["choice_only_reason_it"].to_s != "",
                    items: Array(e["items"]))
        end
        entries.each { |e| skills[e.skill] ||= flat_skill(e.skill, overrides) }
        budget = blueprint["budget"] || {}
        built = instances || build_pool(blueprint, skills, pool || {})
        new(subject: subject, entries: entries, skills: skills, pool: built.to_h { |i| [ i.id, i ] },
            sitting_seconds: (budget["sitting_minutes"] || Rules::V1.sitting_budget_minutes(subject)) * 60,
            sittings: budget["sittings"] || Rules::V1::SITTINGS_PER_SUBJECT,
            seed_salt: seed_salt, external: external, seen: seen)
      end

      def flat_skill(key, overrides, scope: "studied")
        SkillDef.new(key: key, subject: key.split(".").first, scope: scope, kind: Rules::V1.kind_for(scope, overrides[key]),
                     prerequisites: [], composite_of: [], errors: {})
      end

      def build_skills(graph, overrides)
        return {} unless graph

        graph.fetch("skills").to_h do |s|
          errors = (s["errors"] || []).to_h { |er| [ er["code"], er["implicates"] || [] ] }
          [ s["key"], SkillDef.new(key: s["key"], subject: s["key"].split(".").first, scope: s["scope"],
                                   kind: Rules::V1.kind_for(s["scope"], overrides[s["key"]]),
                                   prerequisites: s["prerequisites"] || [], composite_of: s["composite_of"] || [],
                                   errors: errors) ]
        end
      end

      # Entries use their blueprint items; items named only in the pool spec go
      # with the skills they declare; every other skill gets one synthetic item.
      def build_pool(blueprint, skills, spec)
        out = []
        covered = Set.new
        in_blueprint = blueprint["entries"].flat_map { |e| e["items"] } + Array(blueprint["descent"]).flat_map { |d| Array(d["items"]) }
        blueprint["entries"].each do |e|
          choice_only = e["choice_only_reason_it"].to_s != ""
          e["items"].each_with_index do |item, i|
            out.concat(instances_of(item, spec[item], [ e["skill"] ], default_component: choice_only && i.zero? ? "choice" : "number"))
          end
          covered << e["skill"]
        end
        spec.each do |item, s|
          next if in_blueprint.include?(item)

          out.concat(instances_of(item, s, s["skills"] || [], default_component: "number"))
          covered.merge(s["skills"] || [])
        end
        # A blueprint with a descent pool (D-034) serves only what it pins; a bare
        # file without one gets a synthetic item for every skill without items.
        Array(blueprint["descent"]).each do |d|
          Array(d["items"]).each { |item| out.concat(instances_of(item, spec[item], [ d["skill"] ], default_component: "number")) }
          covered << d["skill"]
        end
        unless blueprint.key?("descent")
          (skills.keys - covered.to_a).each do |k|
            out.concat(instances_of("sim_#{k}", nil, [ k ], default_component: "number"))
          end
        end
        out
      end

      def instances_of(item, spec, skills, default_component:)
        spec ||= {}
        component = spec["component"] || default_component
        kind = spec["kind"] || (component == "short_answer" ? "short_answer" : "diagnosis_item")
        n = spec["instances"] || (kind == "short_answer" ? 1 : DEFAULT_INSTANCES_PER_ITEM)
        sk = spec["skills"] || skills
        sk = sk.first(1) if kind == "testlet" # one attempt, counted for the first skill only (D-098)
        low = spec.fetch("low_guess") { Rules::V1.low_guess?(component, size: spec["size"]) }
        Array.new(n) do |i|
          Instance.new(id: "#{item}##{i + 1}", item: item, skills: sk, component: component, low_guess: low,
                       choice: spec.fetch("choice") { component == "choice" }, expected_seconds: spec["expected_seconds"] || 60,
                       fingerprint: Digest::SHA256.hexdigest("#{item}##{i + 1}"), kind: kind)
        end
      end
    end

    private

    def check_acyclic!
      state = {}
      visit = lambda do |k, path|
        return if state[k] == :done
        raise CycleError, "prerequisite cycle: #{(path + [ k ]).join(' -> ')}" if state[k] == :open

        state[k] = :open
        @skills[k]&.parents&.each { |p| visit.call(p, path + [ k ]) }
        state[k] = :done
      end
      @skills.each_key { |k| visit.call(k, []) }
    end
  end
end
