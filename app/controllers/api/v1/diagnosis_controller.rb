module Api
  module V1
    # POST /api/v1/diagnosis/simulate: a dry run of the pure engine. Nothing is
    # written. Body (JSON): {script: "all-correct"|"all-wrong"|"mixed"|{...}} and
    # either {bundle: <blueprint, or {blueprint, graph?, pool?, ...}>} or
    # {subject: "math"} (the latest blueprint revision of that subject).
    # Answer: the trace (events), the final states, the time account and the end
    # reason (see Diagnosis::Derivation.result).
    class DiagnosisController < Api::BaseController
      def simulate
        body = parse_body
        return unless body

        @warnings = []
        plan = plan_from(body)
        return unless plan

        student = Diagnosis::ScriptedStudent.new(body.fetch("script", "all-wrong"))
        out = Diagnosis::Simulator.run(plan, student)
        result = out[:result].except(:skills).merge(states: out[:result][:skills])
        render json: result.merge(dry_run: true, script: student.name, warnings: @warnings, trace: out[:trace])
      rescue Diagnosis::ScriptedStudent::UnknownScript => e
        refuse("E-SIMULATE-INPUT", "script", e.message, "banco diagnosis simulate --script all-correct|all-wrong|mixed|FILE")
      rescue Diagnosis::Plan::CycleError => e
        refuse("E-GRAPH-CYCLE", "graph", e.message, "remove one prerequisite edge of the cycle")
      rescue KeyError => e
        refuse("E-SIMULATE-INPUT", "script", "unknown verdict or missing key: #{e.message.first(80)}", "see Rules::V1::EVIDENCE for the verdicts")
      rescue Diagnosis::Plan::Invalid, Diagnosis::Simulator::Stuck, TypeError => e
        refuse("E-SIMULATE-INPUT", "blueprint", e.message, "banco diagnosis simulate --blueprint FILE")
      end

      private

      def parse_body
        body = JSON.parse(request.raw_post)
        return body if body.is_a?(Hash)

        refuse("E-SIMULATE-INPUT", "body", "the request body must be a JSON object", "banco diagnosis simulate --blueprint FILE")
        nil
      rescue JSON::ParserError => e
        refuse("E-SIMULATE-INPUT", "body", "the request body is not JSON: #{e.message.first(80)}", "banco diagnosis simulate --blueprint FILE")
        nil
      end

      def plan_from(body)
        if body["subject"]
          subject = Subject.find_by(key: body["subject"].to_s)
          revision = subject && BlueprintRevision.where(subject: subject).order(:seq).last
          unless revision
            render json: { code: "E-BLUEPRINT-UNKNOWN", field: "subject", message: "no blueprint for #{body['subject'].to_s.first(40).inspect}",
                           next: "banco diagnosis simulate --blueprint FILE" }, status: :not_found
            return nil
          end
          Diagnosis::PlanLoader.for_blueprint_revision(revision)
        else
          bundle = body["bundle"]
          plan = Diagnosis::Plan.from_bundle(bundle) # validates the document
          bare = bundle.is_a?(Hash) && !bundle.key?("blueprint") && !bundle.key?("graph") && !bundle.key?("pool")
          bare ? faithful_plan(bundle) || flat_warning(plan) : plan
        end
      end

      # A bare blueprint: its pinned graph revision and items, when stored (D-099).
      def faithful_plan(blueprint)
        plan, missing = Diagnosis::PlanLoader.for_document(blueprint)
        return nil unless plan

        if missing.any?
          @warnings << { code: "E-SIMULATE-INPUT", field: "blueprint.items",
                         message: "no passed stored revision for item(s) #{missing.first(10).join(', ')}: synthetic instances stand in for them",
                         next: "submit and validate those items, then simulate again" }
        end
        plan
      end

      def flat_warning(plan)
        @warnings << { code: "E-SIMULATE-INPUT", field: "blueprint.graph_revision_id",
                       message: "the graph revision is not stored: the dry run is flat (every skill studied, no descent, synthetic items)",
                       next: "submit the graph, or simulate with --subject after submitting the blueprint" }
        plan
      end

      def refuse(code, field, message, next_step)
        render json: { code: code, field: field, message: message, next: next_step }, status: :unprocessable_entity
        nil
      end
    end
  end
end
