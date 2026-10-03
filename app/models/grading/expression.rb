module Grading
  # Grading::Expression (A-01): expressions are graded by our checker
  # (app/javascript/grader/checker.mjs) in a persistent Node process, the worker.
  # The worker is started on first use and belongs to the Rails process that
  # started it (keyed by Process.pid): Puma and every forked Solid Queue process get
  # their own. It is never started in an initializer.
  #
  # When the worker does not answer within TIMEOUT seconds, or dies, no grading is
  # written: Expression::Unavailable is raised and GradePendingJob retries.
  module Expression
    GRADER = "expression".freeze
    TIMEOUT = 2.0
    # Loading Compute Engine takes about a second; the host can be heavily loaded.
    STARTUP_TIMEOUT = 20.0
    WORKER_SCRIPT = Rails.root.join("app/javascript/grader/worker.mjs").to_s.freeze

    class Unavailable < StandardError; end
    class TimedOut < Unavailable; end

    # Codes of the checker's invalid answers, as the registry names them
    # (config/banco/error_codes.yml, grader_codes). Anything else is unparseable.
    INVALID_CODES = {
      "empty" => "empty", "incomplete_placeholder" => "empty", "empty_root" => "empty",
      "ambiguous_exponent" => "ambiguous_exponent",
      "ambiguous_mixed_number" => "ambiguous_mixed_number", "ambiguous_digit_space" => "ambiguous_mixed_number"
    }.freeze

    LOCK = Mutex.new
    @workers = {}

    class << self
      def grade(spec, value, source: "mathlive")
        return Closed.invalid("unparseable") unless value.is_a?(String)

        response = worker.request("op" => "check", "item" => item_payload(spec), "answer" => value, "source" => source)
        to_result(response)
      end

      # Problems the checker finds in an item instance (the generator's well-formedness).
      def problems(spec)
        worker.request("op" => "compile", "item" => item_payload(spec))["problems"]
      end

      # Checker item from the instance's key: answer is LaTeX, or
      # {latex, unknown, domain}; each error value likewise.
      def item_payload(spec)
        latex, unknown, domain = parts(spec.answer)
        {
          "expected" => latex,
          "form" => spec.form,
          "errors" => spec.error_values.map { |code, value| { "code" => code, "latex" => parts(value).first } },
          "unknown" => unknown,
          "domain" => domain || {}
        }
      end

      # The worker of this process, started on first use.
      def worker
        LOCK.synchronize do
          # Entries of the parent after a fork: drop our copies of its pipes, never
          # touch its process.
          @workers.delete_if { |pid, w| pid != Process.pid && (w.abandon! || true) }
          @workers[Process.pid] ||= begin
            at_exit_hook
            Worker.new
          end
        end
      end

      def shutdown
        LOCK.synchronize { @workers.delete(Process.pid)&.stop }
      end

      private

      def parts(answer)
        answer.is_a?(Hash) ? [ answer["latex"], answer["unknown"], answer["domain"] ] : [ answer.to_s, nil, nil ]
      end

      def at_exit_hook
        return if @hooked_pid == Process.pid

        @hooked_pid = Process.pid
        at_exit { Grading::Expression.shutdown }
      end

      def to_result(response)
        verdict = response["verdict"]
        common = { grader: GRADER, checker_version: response["checker_version"], ce_version: response["ce_version"] }
        case verdict
        when "invalid"
          # The key itself cannot be read: not the student's mistake.
          return Result.new(verdict: "undetermined", reason: "item_broken", **common) if response["code"] == "item_broken"

          Result.new(verdict: "invalid", invalid_code: INVALID_CODES.fetch(response["code"], "unparseable"),
                     reason: response["code"], **common)
        when "undetermined"
          Result.new(verdict: "undetermined", reason: response["reason"], grading_method: method_of(response), **common)
        else
          Result.new(verdict: verdict, error_codes: response["error_codes"] || [],
                     form_violations: response["form_violations"] || [], normalized: response["normalized"],
                     grading_method: method_of(response), **common)
        end
      end

      # attempt_gradings.method is exact or float: sampling at exact rational points
      # is exact; anything that touched floating point is not.
      def method_of(response)
        m = response["method"].to_s
        return nil if m.empty?

        m.start_with?("exact") ? "exact" : "float"
      end
    end
  end
end
