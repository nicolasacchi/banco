module Approval
  # The mechanical half of approving an entry test (B-07, C-04): approve_blueprint
  # is possible only when
  #
  #   - the graph revision the blueprint references is the approved one,
  #   - every pinned item revision (entries and descent pool) is approvable?
  #     (Review::Gate, M6),
  #   - the teacher opened each pinned item in the preview (app_event
  #     teacher_viewed_item), and
  #   - the teacher played the whole test once as the preview student: a closed run
  #     in the context teacher_preview pinned to this very revision.
  #
  # Nothing here decides: it says what is still missing, in the teacher's words.
  module BlueprintGate
    Result = Struct.new(:approvable, :reasons, keyword_init: true) do
      def to_h = { approvable: approvable, reasons: reasons }
    end

    module_function

    def approvable?(revision) = check(revision).approvable

    def check(revision)
      reasons = []
      approved_graph = SubjectStage.approved_graph(revision.subject)
      reasons << "the graph revision #{revision.skill_graph_revision_id} of this test is not approved" unless approved_graph&.id == revision.skill_graph_revision_id
      unapproved_guests(revision).each { |skill| reasons << "the guest skill #{skill} is not in an approved graph of its subject" }
      ids = revision.pinned_item_revision_ids
      reasons << "the test pins no item" if ids.empty?
      revisions = ItemRevision.where(id: ids).index_by(&:id)
      viewed = viewed_ids
      ids.each do |id|
        item_revision = revisions[id]
        unless item_revision
          reasons << "item revision #{id} does not exist"
          next
        end
        gate = Review::Gate.check(item_revision)
        reasons << "item revision #{id} is not approvable: #{gate.reasons.join('; ')}" unless gate.approvable
        reasons << "item revision #{id} was not opened in the preview" unless viewed.include?(id)
      end
      stale_pins(revision).each { |pin| reasons << "item revision #{pin[:pinned]} is no longer the latest passed revision of its item: #{pin[:latest]} replaced it (W-STALE-PIN)" }
      reasons << "the test was not played to the end as the preview student" unless previewed?(revision)
      Result.new(approvable: reasons.empty?, reasons: reasons)
    end

    # [{pinned:, latest:}] for each pinned revision that passed but is not the newest
    # passed revision of its item (D-136).
    def stale_pins(revision)
      ItemRevision.where(id: revision.pinned_item_revision_ids).includes(item: { revisions: :validations }).filter_map do |r|
        next unless r.status == "passed"

        latest = r.item.revisions.select { |x| x.status == "passed" }.max_by(&:seq)
        { pinned: r.id, latest: latest.id } if latest && latest.id != r.id
      end
    end

    def unapproved_guests(revision)
      Array(JSON.parse(revision.body_json)["entries"]).filter_map do |e|
        next unless e["guest_of_subject"]

        owner = Subject.find_by(key: e["skill"].to_s.split(".").first)
        graph = owner && SubjectStage.approved_graph(owner)
        e["skill"] unless graph && JSON.parse(graph.body_json)["skills"].any? { |s| s["key"] == e["skill"] }
      end
    end

    def viewed_ids
      AppEvent.where(kind: "teacher_viewed_item").pluck(:payload_json).filter_map { |j| JSON.parse(j || "{}")["item_revision_id"]&.to_i }.to_set
    end

    def previewed?(revision)
      student = Student.find_by(key: "preview") or return false
      DiagnosisRun.where(student: student, blueprint_revision: revision).any? { |run| Diagnosis::Conductor.new(run).closed? }
    end
  end
end
