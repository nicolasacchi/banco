module Teacher
  # The entry test of a subject as the teacher approves it (C-04, A-05): one screen per
  # skill with every pinned item side by side. This is the read model behind
  # /teacher/subjects/:key/test; it writes nothing (opening an item is recorded by the
  # controller, as the gate asks).
  class TestReview
    SAMPLES = 4
    TRACE_SCRIPTS = %w[all-correct all-wrong].freeze
    CHECKLIST_PASS = %w[pass na].freeze

    SkillRow = Data.define(:skill, :label_it, :role, :item_ids, :not_assessed_reason_it, :redo_reserve, :worked, :open_findings)
    Card = Data.define(:revision, :item, :body, :samples, :catalogue, :sources, :gate, :review, :blind, :findings, :send_backs, :superseded)
    Finding = Data.define(:finding, :disposition, :new_revision_expected)

    attr_reader :subject, :blueprint, :approved

    def initialize(subject)
      @subject = subject
      @blueprint = BlueprintRevision.where(subject: subject).order(:seq).last
      @approved = SubjectStage.approved_blueprint(subject)
    end

    def present? = !@blueprint.nil?
    def body = @body ||= JSON.parse(blueprint.body_json)
    def graph = blueprint.skill_graph_revision
    def approved_latest? = !approved.nil? && approved.id == blueprint&.id
    def gate = @gate ||= Approval::BlueprintGate.check(blueprint)

    def labels
      @labels ||= JSON.parse(graph.body_json)["skills"].to_h { |s| [ s["key"], s["label_it"] ] }
    end

    # revision id => item key, for the gate's sentences.
    def names
      @names ||= ItemRevision.where(id: blueprint.pinned_item_revision_ids).includes(:item).to_h { |r| [ r.id, r.item.key ] }
    end

    def skill_rows
      @skill_rows ||= begin
        rows = Array(body["entries"]).map { |e| [ e, :entry ] } + Array(body["descent"]).map { |d| [ d, :descent ] }
        rows.map do |e, role|
          ids = Array(e["items"]).map(&:to_i)
          SkillRow.new(e["skill"], labels[e["skill"]] || e["skill"], role, ids, e["not_assessed_reason_it"], e["redo_reserve"], ids.all? { |id| worked?(id) }, open_findings(ids))
        end
      end
    end

    def skill_row(skill) = skill_rows.find { |r| r.skill == skill }

    # The cards of one skill: every pinned item revision, side by side.
    def cards(skill)
      row = skill_row(skill) or return []
      revisions = ItemRevision.where(id: row.item_ids).includes(:item, :instances, :findings, :reviews, :blind_solves, :validations).index_by(&:id)
      dispositions = ReviewFinding.dispositions
      back = SendBacks.by_revision(row.item_ids)
      row.item_ids.filter_map { |id| revisions[id] }.map { |rev| card(rev, dispositions, back) }
    end

    # Dry runs of the engine on the draft with two scripted students: what the test does
    # when everything is right and when everything is wrong.
    def traces
      @traces ||= TRACE_SCRIPTS.map do |name|
        plan = Diagnosis::PlanLoader.for_blueprint_revision(blueprint)
        out = Diagnosis::Simulator.run(plan, Diagnosis::ScriptedStudent.new(name))
        result = out[:result]
        { script: name, end_reason: result[:end_reason], served: result[:served], minutes: (result[:counted_seconds] / 60.0).round,
          sittings: result[:sittings].size, states: result[:skills].map { |r| r[:state] }.tally }
      rescue StandardError => e
        { script: name, error: "#{e.class}: #{e.message.to_s.first(160)}" }
      end
    end

    def pinned_count = blueprint.pinned_item_revision_ids.size

    private

    def worked?(id)
      rev = ItemRevision.find_by(id: id)
      rev ? Review::Gate.worked?(rev) : false
    end

    def open_findings(ids)
      dispositions = ReviewFinding.dispositions
      ReviewFinding.must_be_disposed.where(item_revision_id: ids).count { |f| !dispositions.key?(f.id) }
    end

    def card(rev, dispositions, back)
      item_body = JSON.parse(rev.body_json)
      samples = rev.instances.sort_by(&:id).first(SAMPLES).each_with_index.map { |inst, i| InstanceView.new(inst, item_body, i + 1) }
      review = rev.reviews.max_by(&:id)
      blind = rev.blind_solves.max_by(&:id)
      later = rev.item.revisions.map(&:seq).max.to_i > rev.seq
      findings = rev.findings.sort_by(&:id).map do |f|
        disposition = dispositions[f.id]
        Finding.new(f, disposition, disposition == "fix_requested" && !later)
      end
      Card.new(rev, rev.item, item_body, samples, catalogue_of(item_body), Array(item_body["sources"]), Review::Gate.check(rev),
               review && JSON.parse(review.checklist_json), blind && JSON.parse(blind.results_json), findings, back[rev.id] || [], later)
    end

    def catalogue_of(body)
      return Array(body["error_catalogue"]) unless body["kind"] == "testlet"

      Array(body["sub_items"]).flat_map { |s| Array(s["error_catalogue"]).map { |e| e.merge("sub_item" => s["id"]) } }
    end
  end
end
