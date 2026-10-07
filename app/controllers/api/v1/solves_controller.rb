module Api
  module V1
    # The blind solve of an item revision (A-05): the solver sees the instances as the
    # student does (display only), answers, and the server grades the answers with the
    # same graders as the student's. Every disagreement with the key is stored as a
    # blocker finding (E-BLIND-SOLVE-MISMATCH); the teacher disposes of it.
    class SolvesController < Api::BaseController
      include IndependentRoles

      before_action :load_revision

      # GET /api/v1/revisions/:revision/solve
      def open
        session = require_session("solver", item: @item, next_step: next_session) or return
        return unless independent_role?(session, @item, "solver") && latest?(@revision, @item, step: "solve")

        render json: { revision_id: @revision.id, item: @item.key, subject: @item.subject.key, seq: @revision.seq, component: component,
                       sub_items: sub_items, instances: @text.solver_instances, brief: brief_row("solve"),
                       next: "write banco.solve/1 (banco brief show solve) and run banco solve submit #{@revision.id} --file answers.json" }
      end

      # POST /api/v1/revisions/:revision/solve {solve}
      def submit
        body = parse_json_body or return
        session = require_session("solver", item: @item, next_step: next_session) or return
        return unless independent_role?(session, @item, "solver") && latest_and_passed?(@revision, @item)

        doc = body["solve"]
        return refuse("E-FILES", "solve", "send the answers as {solve: {...}}", "banco solve submit REV --file answers.json", 422) unless doc.is_a?(Hash)

        shape = Validation::Findings.new
        return if !Validation::SchemaCheck.call("solve", doc, shape) && refuse_findings(shape, "fix answers.json (banco brief show solve)", dry_run: dry_run?)
        if doc["revision"].to_s != @revision.id.to_s
          return refuse("E-FILES", "revision", "the file answers revision #{doc['revision'].inspect}; you are submitting to revision #{@revision.id}", "banco solve open #{@revision.id}", 422)
        end
        problem = answer_shape_problem(doc["answers"])
        return refuse("E-FILES", problem[0], problem[1], "banco solve open #{@revision.id}", 422) if problem

        results = grade_all(doc["answers"]) or return
        return render json: { dry_run: true, status: "passed", mismatches: results.count { |r| r[:finding] } } if dry_run?

        solve = store(session, doc, results)
        render json: { solve_id: solve.id, revision_id: @revision.id, instances: results.size,
                       mismatches: solve.findings.count, findings: solve.findings.order(:id).map(&:to_h),
                       next: "stop here: the teacher disposes of the findings in the browser (banco status)" }, status: :created
      rescue Grading::Expression::Unavailable => e
        refuse("E-CHROME-UNAVAILABLE", "grader", "the expression grader did not answer: #{e.message.first(120)}", "retry in 30 s; banco health", 503)
      end

      private

      def component = @text.body["kind"] == "short_answer" ? "short_answer" : (@text.body["component"] || @text.body["kind"])

      def sub_items
        return nil unless @text.body["kind"] == "testlet"

        Array(@text.body["sub_items"]).map { |s| { id: s["id"], component: s["component"] } }
      end

      # One answer per shown instance, no extras, none twice.
      def answer_shape_problem(answers)
        numbers = answers.map { |a| a["instance"] }
        shown = (1..@text.instances.size).to_a
        return [ "answers", "there must be one answer for each of the #{shown.size} instances (instance numbers #{shown.first}-#{shown.last}), none twice" ] unless numbers.sort == shown

        nil
      end

      # [{instance, verdict, finding}] or nil after answering 422 for an answer the grader
      # cannot read (the solver fixes the format; it is not a disagreement). Grading never
      # runs in a transaction (Grading.grade_spec asserts it).
      def grade_all(answers)
        invalid = []
        results = answers.sort_by { |a| a["instance"] }.map do |a|
          verdict = "dont_know"
          unless a["dont_know"]
            graded = Grading.grade(@text.instance_row(a["instance"]), raw_of(a["answer"]), source: "text")
            invalid << [ a["instance"], graded ] if graded.invalid?
            verdict = graded.verdict
          end
          { instance: a["instance"], verdict: verdict, finding: finding_for(a["instance"], verdict) }
        end
        return results if invalid.empty?

        number, graded = invalid.first
        refuse("E-FILES", "answers/#{number}", "the answer to instance #{number} cannot be read (#{graded.invalid_code}): #{graded.message_it}", "banco solve open #{@revision.id}", 422,
               unreadable: invalid.map(&:first))
        nil
      end

      # The raw text of the stored attempts: plain text as is, structured answers as JSON.
      def raw_of(value)
        if component == "testlet" && value.is_a?(Hash)
          JSON.generate(value.transform_values { |v| v.is_a?(String) ? v : JSON.generate(v) })
        elsif value.is_a?(String) then value
        else JSON.generate(value)
        end
      end

      # A mismatch is a blocker; a solver who cannot answer is a major finding; a short
      # answer cannot be graded by the server, so it is recorded and no more.
      def finding_for(number, verdict)
        case verdict
        when "correct", "short_answer" then nil
        when "dont_know"
          { severity: "major", problem: "Il risolutore alla cieca non è riuscito a rispondere all'istanza #{number}.",
            fix: "Controlla che l'item si possa risolvere dal solo testo. Chiarisci la consegna o i dati." }
        else
          { severity: "blocker", problem: "Il risolutore alla cieca ha dato all'istanza #{number} una risposta diversa dalla chiave.",
            fix: "Controlla la chiave e la consegna dell'istanza #{number}. C'è una seconda risposta valida, o la chiave è sbagliata?" }
        end
      end

      def store(session, doc, results)
        BlindSolve.transaction do
          solve = BlindSolve.create!(item_revision: @revision, agent_session: session, answers_json: JSON.generate(doc["answers"]),
                                     results_json: JSON.generate(results.map { |r| r.slice(:instance, :verdict) }), brief_sha256: Brief.find("solve")&.sha256)
          results.each do |r|
            f = r[:finding] or next
            ReviewFinding.create!(item_revision: @revision, source: "blind_solve", blind_solve: solve, severity: f[:severity], code: "E-BLIND-SOLVE-MISMATCH",
                                  instance: r[:instance], field: "instances/#{r[:instance]}", quote: quote_of(r), problem_it: f[:problem], fix_it: f[:fix])
          end
          solve
        end
      end

      # The stem the solver answered, as the quote of the finding.
      def quote_of(result)
        display = JSON.parse(@text.instance_row(result[:instance]).display_json)
        (display["stem_it"] || display["passage_it"] || display.to_json).to_s.first(500)
      end

      def next_session = "banco session new --role solver --agent NAME --model MODEL"

      def load_revision
        @revision = ItemRevision.find_by(id: params[:revision])
        return refuse("E-NOT-FOUND", "revision", "no revision #{params[:revision].to_s.first(20).inspect}", "banco work open ITEM", 404) unless @revision

        @item = @revision.item
        @text = Review::ItemText.new(@revision)
      end
    end
  end
end
