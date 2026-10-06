module Api
  module V1
    # The skill graph of a subject (B-07, C-01): open the latest revision, submit a new
    # one, read the coverage of the previous year's programme. Validation is
    # synchronous; a graph with an error is refused and nothing is stored (it is not an
    # item revision). The teacher approves a graph in the browser; nothing here does.
    class SkillGraphsController < Api::BaseController
      before_action :load_subject

      # GET /api/v1/subjects/:subject/skill-graph
      def open
        latest = SkillGraphRevision.where(subject: @subject).order(:seq).last
        render json: {
          subject: @subject.key, name_it: @subject.name_it,
          revision: latest && { revision_id: latest.id, seq: latest.seq, graph: JSON.parse(latest.body_json) },
          approved_revision_id: SubjectStage.approved_graph(@subject)&.id,
          sources: SyllabusSource.order(:key).map { |s| { key: s.key, lines: s.line_count } },
          range: Validation::Rules.get(:coverage, :ranges)[@subject.key],
          brief: brief_row("skill-graph"),
          next: latest ? "edit the graph and run banco skill-graph submit --subject #{@subject.key} FILE --dry-run" : "write a banco.skill_graph/1 document (see banco brief show skill-graph)"
        }
      end

      # POST /api/v1/subjects/:subject/skill-graph {graph}
      def submit
        body = parse_json_body or return
        graph = body["graph"]
        return refuse("E-FILES", "graph", "send the graph as {graph: {...}}", "banco skill-graph submit --subject KEY FILE", 422) unless graph.is_a?(Hash)

        findings = Validation::GraphChecks.call(graph, subject: @subject.key, context: Validation::CourseContext.for(@subject))
        return if refuse_findings(findings, "fix the graph and run banco skill-graph submit --subject #{@subject.key} FILE --dry-run again", dry_run: dry_run?)

        warnings = findings.warnings.map(&:to_h)
        return render json: { dry_run: true, status: "passed", codes: [], warnings: warnings } if dry_run?

        ok, author = optional_author_session
        return unless ok

        text = JSON.generate(graph)
        # Read inside the transaction (D-073): a concurrent identical submit replays.
        latest = nil
        revision = SkillGraphRevision.transaction do
          latest = SkillGraphRevision.where(subject: @subject).order(:seq).last
          next if latest && latest.body_json == text

          SkillGraphRevision.create!(subject: @subject, seq: (latest&.seq || 0) + 1, body_json: text, author_session: author, brief_sha256: Brief.find("skill-graph")&.sha256)
        end
        return render json: { revision_id: latest.id, seq: latest.seq, replayed: true, warnings: warnings } unless revision

        render json: { revision_id: revision.id, seq: revision.seq, replayed: false, warnings: warnings,
                       next: "banco skill-graph coverage --subject #{@subject.key}" }, status: :created
      end

      # GET /api/v1/subjects/:subject/skill-graph/coverage
      def coverage
        data = SkillGraphCoverage.call(@subject)
        return refuse("E-NOT-FOUND", "subject", "#{@subject.key} has no skill graph yet", "banco skill-graph submit --subject #{@subject.key} FILE", 404) unless data

        render json: data
      end

      private

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
