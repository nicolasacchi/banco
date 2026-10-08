# Where a subject stands in the content cycle, for `banco status` (B-07, E-05):
#
#   drafting          no graph or no entry test yet, or an item that failed validation
#   validating        an item revision is waiting for, or retrying, its validation
#   in_review         graph and entry test are in, every pinned item passed; the
#                     review and the blind solve have not finished
#   awaiting_teacher  everything the agent does is done: only the teacher is left
#   approved          the teacher approved a graph and an entry test
#
# No command goes past awaiting_teacher: approval is a decision of the teacher in
# the browser (firm rule 2). awaiting_teacher means every pinned revision has an
# expert review and a blind solve; what they found is the teacher's to dispose of.
class SubjectStage
  STAGES = %w[drafting validating in_review awaiting_teacher approved].freeze

  class << self
    # The graph revision the teacher approved last, or nil.
    def approved_graph(subject) = approved(subject, "approve_skill_graph", SkillGraphRevision)

    def approved_blueprint(subject) = approved(subject, "approve_blueprint", BlueprintRevision)

    def for(subject)
      graph = SkillGraphRevision.where(subject: subject).order(:seq).last
      blueprint = BlueprintRevision.where(subject: subject).order(:seq).last
      approved_g = approved_graph(subject)
      approved_b = approved_blueprint(subject)
      items = item_states(subject)
      {
        key: subject.key,
        name_it: subject.name_it,
        stage: stage(subject, graph, blueprint, approved_g, approved_b, items),
        graph: revision_row(graph, approved_g),
        blueprint: revision_row(blueprint, approved_b),
        graph_approved: !approved_g.nil?,
        blueprint_approved: !approved_b.nil?,
        pending_revision: pending?(graph, approved_g) || pending?(blueprint, approved_b),
        items: items.values.tally.then { |t| { total: items.size, passed: t["passed"].to_i, failed: t["failed"].to_i, awaiting_verifier: t["awaiting_verifier"].to_i, validating: t["validating"].to_i, error: t["error"].to_i, older_rules: older_rules(subject), sent_back: sent_back(subject), reserve: Item.reserve(subject).count } }
      }
    end

    private

    def approved(subject, kind, model)
      decision = Decision.where(subject: subject, kind: kind).order(:id).last or return nil
      model.find_by(id: JSON.parse(decision.payload_json)["revision_id"])
    end

    def revision_row(latest, approved)
      return nil unless latest

      row = { revision_id: latest.id, seq: latest.seq, approved_revision_id: approved&.id }
      if latest.is_a?(BlueprintRevision)
        row[:stale_pins] = Approval::BlueprintGate.stale_pins(latest)
        row[:multi_skill_testlets] = Approval::BlueprintGate.multi_skill_testlets(latest)
        row[:older_rules_pins] = Approval::BlueprintGate.older_rules_pins(latest)
      end
      row
    end

    def pending?(latest, approved) = !latest.nil? && !approved.nil? && latest.id != approved.id

    # Items whose latest revision the teacher sent back and nobody has replaced yet.
    def sent_back(subject)
      latest = Item.diagnosis.where(subject: subject).includes(:revisions).filter_map { |i| i.revisions.max_by(&:seq) }
      back = Teacher::SendBacks.by_revision(latest.map(&:id))
      latest.count { |r| back.key?(r.id) }
    end

    # Items whose latest revision passed under an older rules version than the current
    # one (D-147): the rules may have tightened since, so a dry run is worth it.
    def older_rules(subject)
      current = Validation::Rules.version.to_s
      Item.diagnosis.where(subject: subject).includes(revisions: :validations).count do |item|
        v = item.revisions.max_by(&:seq)&.validations&.max_by(&:seq)
        v && v.status == "passed" && v.rules_version.to_s != current
      end
    end

    # {item key => passed|failed|awaiting_verifier|validating|error} for the latest revision of each item.
    def item_states(subject)
      Item.diagnosis.where(subject: subject).includes(:revisions).to_h do |item|
        revision = item.revisions.max_by(&:seq)
        [ item.key, revision ? state_of(revision) : "validating" ]
      end
    end

    def state_of(revision)
      latest = revision.validations.max_by(&:seq)
      return "validating" unless latest

      latest.display_status
    end

    def stage(subject, graph, blueprint, approved_g, approved_b, items)
      return "approved" if approved_g && approved_b
      return "validating" if items.values.any? { |s| %w[validating error].include?(s) }
      return "drafting" unless graph && blueprint
      return "drafting" if pinned_not_passed?(blueprint)

      review_done?(subject, blueprint) ? "awaiting_teacher" : "in_review"
    end

    def pinned_not_passed?(blueprint)
      blueprint.pinned_item_revision_ids.any? { |id| ItemRevision.find_by(id: id)&.validations&.max_by(&:seq)&.status != "passed" }
    end

    # The agents' side of the review is done when every pinned revision has an expert
    # review and a blind solve (Review::Gate.worked?). The findings are the teacher's.
    def review_done?(_subject, blueprint)
      blueprint.pinned_item_revision_ids.all? { |id| (rev = ItemRevision.find_by(id: id)) && Review::Gate.worked?(rev) }
    end
  end
end
