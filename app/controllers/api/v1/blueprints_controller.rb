module Api
  module V1
    # The entry test of a subject (B-07, D-038): open what an author needs to write
    # one, submit one. Validation is synchronous; a blueprint with an error is refused
    # and nothing is stored. The teacher approves a blueprint in the browser; nothing
    # here does.
    class BlueprintsController < Api::BaseController
      before_action :load_subject

      # GET /api/v1/subjects/:subject/blueprint
      # The latest blueprint (if any), the graph to build on, the skills the descent
      # can reach from its starting skills (to pin or declare), and the item
      # revisions that can be pinned (the latest validated revision of each item).
      def open
        latest = BlueprintRevision.where(subject: @subject).order(:seq).last
        graph = SkillGraphRevision.where(subject: @subject).order(:seq).last
        document = latest && JSON.parse(latest.body_json)
        render json: {
          subject: @subject.key, name_it: @subject.name_it,
          revision: latest && { revision_id: latest.id, seq: latest.seq, graph_revision_id: latest.skill_graph_revision_id, blueprint: document },
          graph_revision_id: graph&.id, approved_graph_revision_id: SubjectStage.approved_graph(@subject)&.id,
          document: document,
          descent_targets: document && graph ? Validation::BlueprintChecks.descent_targets(document, JSON.parse(graph.body_json)) : nil,
          items: pinnable_items, brief: brief_row("blueprint"),
          next: graph ? "write a banco.blueprint/1 document (start from `document`, the latest one alone) and run banco blueprint submit --subject #{@subject.key} FILE --dry-run" : "submit the skill graph first: banco skill-graph submit --subject #{@subject.key} FILE"
        }
      end

      # POST /api/v1/subjects/:subject/blueprint {blueprint}
      def submit
        body = parse_json_body or return
        doc = body["blueprint"]
        return refuse("E-FILES", "blueprint", "send the blueprint as {blueprint: {...}}", "banco blueprint submit --subject KEY FILE", 422) unless doc.is_a?(Hash)

        shape = Validation::Findings.new
        unless Validation::SchemaCheck.call("blueprint", doc, shape)
          return if refuse_findings(shape, "fix the blueprint (see banco brief show blueprint)", dry_run: dry_run?)
        end
        graph = SkillGraphRevision.find_by(id: doc["graph_revision_id"].to_s, subject: @subject)
        return refuse("E-NOT-FOUND", "graph_revision_id", "#{@subject.key} has no graph revision #{doc['graph_revision_id'].inspect}", "banco skill-graph open --subject #{@subject.key}", 404) unless graph

        findings = Validation::BlueprintChecks.call(doc, graph: JSON.parse(graph.body_json), subject: @subject.key,
                                                     context: Validation::CourseContext.for(@subject), items: Validation::ItemInfo.lookup)
        return if refuse_findings(findings, "fix the blueprint and run banco blueprint submit --subject #{@subject.key} FILE --dry-run again", dry_run: dry_run?)

        warnings = findings.warnings.map(&:to_h)
        return render json: { dry_run: true, status: "passed", codes: [], warnings: warnings } if dry_run?

        ok, author = optional_author_session
        return unless ok

        store(doc, graph, warnings, author)
      end

      private

      def store(doc, graph, warnings, author)
        text = JSON.generate(doc)
        # Read inside the transaction (D-073): a concurrent identical submit replays.
        latest = nil
        revision = BlueprintRevision.transaction do
          latest = BlueprintRevision.where(subject: @subject).order(:seq).last
          next if latest && latest.body_json == text

          BlueprintRevision.create!(subject: @subject, skill_graph_revision: graph, seq: (latest&.seq || 0) + 1, body_json: text, author_session: author,
                                    brief_sha256: Brief.find("blueprint")&.sha256)
        end
        return render json: { revision_id: latest.id, seq: latest.seq, replayed: true, warnings: warnings } unless revision

        render json: { revision_id: revision.id, seq: revision.seq, replayed: false, warnings: warnings,
                       next: "banco status (stage: #{SubjectStage.for(@subject)[:stage]})" }, status: :created
      end

      def pinnable_items
        Item.diagnosis.where(subject: @subject).order(:key).filter_map do |item|
          rev = item.latest_revision
          next unless rev

          doc = JSON.parse(rev.body_json)
          { item: item.key, revision_id: rev.id, status: rev.latest_validation&.display_status || "validating",
            skills: doc["kind"] == "testlet" ? Array(doc["sub_items"]).map { |s| s["skill"] } : [ doc["skill"] ],
            component: doc["component"], instances: rev.instances.count }
        end
      end

      def load_subject
        @subject = Subject.find_by(key: params[:subject].to_s)
        refuse("E-NOT-FOUND", "subject", "no subject #{params[:subject].to_s.first(40).inspect}", "banco status", 404) unless @subject
      end

      def brief_row(name)
        brief = Brief.find(name) or return nil
        { name: brief.name, version: brief.version, sha256: brief.sha256 }
      end
    end
  end
end
