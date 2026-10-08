module Teacher
  # The entry test of a subject as the teacher approves it (C-04, A-05): one screen per
  # skill with every pinned item side by side. This is the read model behind
  # /teacher/subjects/:key/test; it writes nothing (opening an item is recorded by the
  # controller, as the gate asks).
  class TestReview
    SAMPLES = 4
    TRACE_SCRIPTS = %w[all-correct all-wrong].freeze
    CHECKLIST_PASS = %w[pass na].freeze

    SkillRow = Data.define(:skill, :label_it, :role, :item_ids, :not_assessed_reason_it, :redo_reserve, :choice_only_reason_it, :worked, :open_findings)
    Card = Data.define(:revision, :item, :body, :samples, :catalogue, :sources, :gate, :review, :blind, :findings, :send_backs, :superseded)
    Finding = Data.define(:finding, :disposition, :new_revision_expected, :evidence, :response)
    # What the teacher needs to judge a blind-solve finding (D-220): the key of the instance as the
    # student would type it, the other answers accepted, and what the solver wrote.
    Evidence = Data.define(:key, :accepted, :solver_answer, :dont_know)
    # A blocker or major finding nobody has decided yet, on a pinned revision, with where to find it.
    OpenFinding = Data.define(:finding, :skill, :label_it, :item_key)

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

    def skill_rows
      @skill_rows ||= begin
        rows = Array(body["entries"]).map { |e| [ e, :entry ] } + Array(body["descent"]).map { |d| [ d, :descent ] }
        rows.map do |e, role|
          ids = Array(e["items"]).map(&:to_i)
          SkillRow.new(e["skill"], labels[e["skill"]] || e["skill"], role, ids, e["not_assessed_reason_it"], e["redo_reserve"], e["choice_only_reason_it"], ids.all? { |id| worked?(id) }, open_findings(ids))
        end
      end
    end

    # What the author declared about the whole test, for the teacher to read (D-101).
    def settings
      { not_measured_it: body["not_measured_it"], intro_note_it: body["intro_note_it"], calculator: body["calculator"],
        budget: body["budget"], depends_on_subjects: Array(body["depends_on_subjects"]), kind_overrides: Array(body["kind_overrides"]) }
    end

    # The formula sheet as a declared support (D-216): its text in the latest draft, whether the
    # approved (else latest) test can offer it, and whether the teacher switched it on for the subject.
    def formula_sheet
      target = Diagnosis::FormulaSheet.target_blueprint(subject)
      { text: Diagnosis::FormulaSheet.text(blueprint), offerable: !Diagnosis::FormulaSheet.text(target).nil?,
        enabled: Diagnosis::FormulaSheet.enabled?(subject) }
    end

    def skill_row(skill) = skill_rows.find { |r| r.skill == skill }

    # The cards of one skill: every pinned item revision, side by side.
    def cards(skill)
      row = skill_row(skill) or return []
      revisions = ItemRevision.where(id: row.item_ids).includes(:item, :instances, { findings: :blind_solve }, :reviews, :blind_solves, :validations).index_by(&:id)
      dispositions = ReviewFinding.dispositions
      back = SendBacks.by_revision(row.item_ids)
      row.item_ids.filter_map { |id| revisions[id] }.map { |rev| card(rev, dispositions, back) }
    end

    # Dry runs of the engine on the draft with two scripted students: what the test does
    # when everything is right and when everything is wrong.
    def traces
      @traces ||= TRACE_SCRIPTS.map do |name|
        plan = Diagnosis::PlanLoader.for_blueprint_revision(blueprint)
        # The teacher confirms the short answer and any pending one as the script's student
        # would be graded, so a discursive subject's trace reaches its close (D-121).
        out = Diagnosis::Simulator.run(plan, Diagnosis::ScriptedStudent.new(name), resolve_pending: name == "all-correct" ? "correct" : "wrong")
        result = out[:result]
        { script: name, end_reason: result[:end_reason], served: result[:served], minutes: (result[:counted_seconds] / 60.0).round,
          sittings: result[:sittings].size, states: result[:skills].map { |r| r[:state] }.tally }
      rescue StandardError => e
        { script: name, error: "#{e.class}: #{e.message.to_s.first(160)}" }
      end
    end

    def pinned_count = blueprint.pinned_item_revision_ids.size

    # Blocker and major findings without a decision on the pinned revisions, by skill row (D-220).
    def open_finding_list
      @open_finding_list ||= begin
        dispositions = ReviewFinding.dispositions
        by_revision = skill_rows.each_with_object({}) { |row, h| row.item_ids.each { |id| (h[id] ||= []) << row } }
        found = ReviewFinding.must_be_disposed.where(item_revision_id: by_revision.keys).includes(item_revision: :item).order(:id)
                             .reject { |f| dispositions.key?(f.id) }
        skill_rows.flat_map do |row|
          found.select { |f| row.item_ids.include?(f.item_revision_id) }
               .map { |f| OpenFinding.new(f, row.skill, row.label_it, f.item_revision.item.key) }
        end
      end
    end

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
      sorted = rev.findings.sort_by(&:id)
      responses = FindingResponse.latest_for(sorted.map(&:id))
      findings = sorted.map do |f|
        disposition = dispositions[f.id]
        Finding.new(f, disposition, disposition == "fix_requested" && !later, evidence_of(f, rev, item_body), responses[f.id])
      end
      Card.new(rev, rev.item, item_body, samples, catalogue_of(item_body), Array(item_body["sources"]), Review::Gate.check(rev),
               review && JSON.parse(review.checklist_json), blind && JSON.parse(blind.results_json), findings, back[rev.id] || [], later)
    end

    # Only a blind-solve finding about an instance has evidence; a review finding quotes the item itself.
    def evidence_of(finding, rev, item_body)
      return nil unless finding.source == "blind_solve" && finding.instance

      row = rev.instances.sort_by(&:id)[finding.instance - 1] or return nil
      view = InstanceView.new(row, item_body, finding.instance)
      accepted = Array(item_body["accept"]) + (row.accept_json.present? ? Array(JSON.parse(row.accept_json)) : [])
      answers = finding.blind_solve ? JSON.parse(finding.blind_solve.answers_json) : []
      given = Array(answers).find { |a| a.is_a?(Hash) && a["instance"] == finding.instance }
      Evidence.new(view.key, accepted.map(&:to_s).uniq, given && raw_answer(given["answer"]), given.nil? || given["dont_know"] == true)
    end

    # The solver's answer as it was written: text as is, anything structured as JSON.
    def raw_answer(value)
      value.is_a?(String) ? value : JSON.generate(value)
    end

    def catalogue_of(body)
      return Array(body["error_catalogue"]) unless body["kind"] == "testlet"

      Array(body["sub_items"]).flat_map { |s| Array(s["error_catalogue"]).map { |e| e.merge("sub_item" => s["id"]) } }
    end
  end
end
