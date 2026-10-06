module Diagnosis
  # The thin ActiveRecord side of the engine: reads the pinned blueprint and graph
  # revisions, the pool of instances and what the student has seen, and hands
  # the pure engine a Plan. It writes nothing.
  class PlanLoader
    # The plan of a run: its pinned blueprint revision and its seed salt, with the
    # results of the student's runs in other subjects (reused, B-03) and every
    # fingerprint seen in the student's other runs (redo never repeats one).
    def self.for_run(run, reuse: true)
      new(run.blueprint_revision, student: run.student, seed_salt: run.seed_salt, run: run, reuse: reuse).plan
    end

    # The plan of a blueprint revision, for `banco diagnosis simulate --subject`
    # (no student: nothing seen, nothing reused).
    def self.for_blueprint_revision(revision, seed_salt: "sim")
      new(revision, student: nil, seed_salt: seed_salt, run: nil).plan
    end

    # The plan of a bare banco.blueprint/1 document, for `banco diagnosis simulate
    # --blueprint FILE`: the graph is the pinned graph revision, and each pinned
    # item is its stored passed revision with its real instances. A pinned id with
    # no passed revision (or none stored) gets synthetic instances, and its id goes
    # in the second element: the dry run is then not faithful for it. Returns nil
    # when the graph revision does not exist (a flat dry run, as before).
    def self.for_document(blueprint, seed_salt: "sim")
      graph_rev = SkillGraphRevision.find_by(id: blueprint["graph_revision_id"])
      return nil unless graph_rev

      loader = new(nil, student: nil, seed_salt: seed_salt, run: nil)
      loader.instance_variable_set(:@document, blueprint)
      loader.instance_variable_set(:@graph_revision, graph_rev)
      loader.plan_with_synthetic
    end

    # The engine's instances of one stored item revision (for `banco items list`).
    def self.instances_of_revision(revision)
      new(nil, student: nil, seed_salt: "sim", run: nil).send(:revision_instances, revision)
    end

    def initialize(revision, student:, seed_salt:, run:, reuse: true)
      @reuse = reuse
      @revision = revision
      @student = student
      @seed_salt = seed_salt
      @run = run
    end

    def plan
      plan_with_synthetic.first
    end

    # [plan, ids of pinned items that were replaced by synthetic instances]
    def plan_with_synthetic
      blueprint = with_kind_overrides(@document || JSON.parse(@revision.body_json))
      graph = JSON.parse((@graph_revision || @revision.skill_graph_revision).body_json)
      graph = merge_foreign_skills(blueprint, graph)
      built = instances(blueprint)
      built, missing = add_synthetic(blueprint, built) if @document
      [ Plan.build(blueprint: blueprint, graph: graph, instances: built,
                   external: @reuse ? external_states : {}, seen: @reuse ? seen_fingerprints : [], seed_salt: @seed_salt),
        missing || [] ]
    end

    private

    def subject = @subject ||= @revision ? @revision.subject : Subject.find_by(key: @document.fetch("subject"))

    # Dry run of a document: pinned ids that did not load get synthetic instances.
    def add_synthetic(blueprint, built)
      have = built.map { |i| i.item.to_s }.uniq
      skill_of = {}
      blueprint["entries"].each { |e| e["items"].each { |i| skill_of[i.to_s] ||= e["skill"] } }
      Array(blueprint["descent"]).each { |d| Array(d["items"]).each { |i| skill_of[i.to_s] ||= d["skill"] } }
      missing = skill_of.keys - have
      extra = missing.flat_map { |id| Plan.instances_of(id, nil, [ skill_of[id] ], default_component: "number") }
      [ built + extra, missing ]
    end

    # The teacher's kind_override decisions (the latest per skill) go on top of the
    # blueprint's own kind_overrides.
    def with_kind_overrides(blueprint)
      latest = Decision.where(kind: "kind_override", subject_id: subject&.id).order(:id).each_with_object({}) do |d, map|
        payload = JSON.parse(d.payload_json)
        map[payload["skill"]] = { "skill" => payload["skill"], "kind" => payload["kind"], "reason_it" => payload["reason_it"] }
      end
      return blueprint if latest.empty?

      kept = Array(blueprint["kind_overrides"]).reject { |o| latest.key?(o["skill"]) }
      blueprint.merge("kind_overrides" => kept + latest.values)
    end

    # Skills of other subjects that the blueprint or the graph points at (guest
    # entries, cross-subject prerequisites) come from the latest graph of each.
    def merge_foreign_skills(blueprint, graph)
      mine = @revision ? @revision.subject.key : @document["subject"]
      wanted = (blueprint["entries"].map { |e| e["skill"] } + graph["skills"].flat_map { |s| s["prerequisites"] || [] })
               .map { |k| k.split(".").first }.uniq - [ mine ]
      extra = wanted.flat_map do |key|
        subject = Subject.find_by(key: key)
        rev = subject && SkillGraphRevision.where(subject: subject).order(:seq).last
        rev ? JSON.parse(rev.body_json)["skills"] : []
      end
      graph.merge("skills" => graph["skills"] + extra.reject { |s| graph["skills"].any? { |m| m["key"] == s["key"] } })
    end

    # Only what the blueprint pins is served (D-034): the items of the starting
    # skills and the items of the descent pool. A skill the descent reaches with
    # no pinned item ends not_assessed(no_unseen_items); nothing reaches the
    # student that the teacher did not approve with the blueprint, and an item
    # whose latest validation did not pass is never served (M9a).
    def instances(blueprint)
      ids = blueprint["entries"].flat_map { |e| e["items"] } + Array(blueprint["descent"]).flat_map { |d| Array(d["items"]) }
      ids.uniq.filter_map { |id| ItemRevision.find_by(id: id) }.select { |rev| rev.status == "passed" }.flat_map { |rev| revision_instances(rev) }
    end

    def revision_instances(revision)
      body = JSON.parse(revision.body_json)
      kind = body["kind"] || "diagnosis_item"
      component = body["component"] || "number"
      # A testlet's one attempt is attributed to its first skill (D-047), so only that
      # skill is charged the serve (D-098); E-TESTLET-SKILLS keeps all sub items on it.
      skills = kind == "testlet" ? [ Array(body["sub_items"]).first&.dig("skill") ] : [ body["skill"] ]
      revision.instances.order(:id).map do |inst|
        display = JSON.parse(inst.display_json)
        flags = kind == "testlet" ? Rules::V1.testlet_flags(body, display) : nil
        low, choice = if flags
          [ flags.values.any? { |f| f[:low_guess] }, flags.values.all? { |f| f[:choice] } ]
        else
          [ Rules::V1.low_guess?(component, size: display_size(display, component)), component == "choice" ]
        end
        Plan::Instance.new(flags: flags, id: inst.id, item: revision.id, skills: skills, component: component,
                           low_guess: low,
                           choice: choice, expected_seconds: body["expected_seconds"] || 60,
                           fingerprint: inst.fingerprint, kind: kind)
      end
    end

    # Elements of an ordering or pairs of a matching, to decide whether it is
    # low-guess. The display format of M4 names them elements or left.
    def display_size(display, component)
      case component
      when "ordering" then Array(display["elements"]).size
      when "matching" then Array(display["left"]).size
      end
    end

    # Results of the student's runs in other subjects: {skill => {state, reason}}.
    # Voided runs are ignored; a later run overrides an earlier one.
    def external_states
      return {} unless @student

      voided = voided_run_ids
      out = {}
      DiagnosisRun.where(student: @student).where.not(subject: @revision.subject).order(:created_at, :id).each do |other|
        next if voided.include?(other.id)

        other_plan = PlanLoader.for_run(other, reuse: false)
        Derivation.result(other_plan, EventLoader.for_run(other)).fetch(:skills).each do |row|
          next unless %w[demonstrated to_recover].include?(row[:state]) && row[:source] == "run"

          out[row[:skill]] = { "state" => row[:state], "reason" => row[:reason] }
        end
      end
      out
    end

    def voided_run_ids
      Decision.where(kind: "void_diagnosis_run", student_id: @student.id).filter_map do |d|
        JSON.parse(d.payload_json)["run_id"]
      end
    end

    def seen_fingerprints
      return [] unless @student

      scope = ItemServed.joins(diagnosis_event: :diagnosis_run).joins(:item_instance)
                        .where(diagnosis_runs: { student_id: @student.id })
      scope = scope.where.not(diagnosis_runs: { id: @run.id }) if @run
      scope.pluck("item_instances.fingerprint")
    end
  end
end
