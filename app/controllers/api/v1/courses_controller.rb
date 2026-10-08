module Api
  module V1
    # The course map of a subject (A2.2, A4): the seconda skills beside the graph and the ordered topics.
    # Validation is synchronous; a map with an error is refused and nothing is stored. The teacher opens the
    # course to the official student in the browser (release_course); nothing here does.
    class CoursesController < Api::BaseController
      include SubjectScoped

      before_action :load_subject

      # GET /api/v1/subjects/:subject/course
      def open
        latest = Course::State.latest(@subject)
        render json: {
          subject: @subject.key, name_it: @subject.name_it,
          revision: latest && { revision_id: latest.id, seq: latest.seq, skill_graph_revision_id: latest.skill_graph_revision_id,
                                graph_stale: Course::State.graph_stale?(latest), warnings: Course::State.warnings(latest), course: latest.body },
          released_revision_id: Course::State.released_revision_id(@subject),
          graph_revision_id: Course::State.latest_graph(@subject)&.id,
          brief: brief_row("course"),
          next: latest ? "edit the map (the latest one alone) and run banco course submit --subject #{@subject.key} FILE --dry-run" :
                         "write a banco.course/1 document (see banco brief show course) and run banco course submit --subject #{@subject.key} FILE --dry-run"
        }
      end

      # POST /api/v1/subjects/:subject/course {course}
      def submit
        body = parse_json_body or return
        doc = body["course"]
        return refuse("E-FILES", "course", "send the map as {course: {...}}", "banco course submit --subject KEY FILE", 422) unless doc.is_a?(Hash)

        graph = Course::State.latest_graph(@subject)
        return refuse("E-NOT-FOUND", "graph", "#{@subject.key} has no skill graph yet: a course map is validated against it", "banco skill-graph submit --subject #{@subject.key} FILE", 404) unless graph

        findings = Validation::CourseChecks.call(doc, subject: @subject.key, graph: JSON.parse(graph.body_json), context: Validation::CourseContext.for(@subject, course: false))
        return if refuse_findings(findings, "fix the map and run banco course submit --subject #{@subject.key} FILE --dry-run again", dry_run: dry_run?)

        warnings = findings.warnings.map(&:to_h)
        return render json: { dry_run: true, status: "passed", codes: [], warnings: warnings } if dry_run?

        ok, author = optional_author_session
        return unless ok

        text = JSON.generate(doc)
        # Read inside the transaction (D-073): a concurrent identical submit replays. The same map against a
        # newer graph is a new revision: that is how W-COURSE-GRAPH-STALE is cleared.
        latest = nil
        revision = CourseRevision.transaction do
          latest = CourseRevision.where(subject: @subject).order(:seq).last
          next if latest && latest.body_json == text && latest.skill_graph_revision_id == graph.id

          CourseRevision.create!(subject: @subject, seq: (latest&.seq || 0) + 1, skill_graph_revision: graph, body_json: text,
                                 warnings_json: JSON.generate(warnings), author_session: author, brief_sha256: Brief.find("course")&.sha256)
        end
        return render json: { revision_id: latest.id, seq: latest.seq, replayed: true, skill_graph_revision_id: latest.skill_graph_revision_id, warnings: latest.warnings } unless revision

        render json: { revision_id: revision.id, seq: revision.seq, replayed: false, skill_graph_revision_id: graph.id, warnings: warnings,
                       next: "banco lessons list --subject #{@subject.key}" }, status: :created
      end
    end
  end
end
