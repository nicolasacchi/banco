require "open3"

# Server-side grading of one answer (X-01, A-01). The server decides every
# verdict; the browser sends a raw answer and never sees the outcome.
#
#   result = Grading.grade(item_instance, raw, source: "mathlive")   # no database writes
#   Grading::Recorder.append(attempt, result, source: "sync")        # short transaction
#
# Grading never runs inside a database transaction: SQLite takes the write lock
# when a transaction opens, and a wait on the expression worker (up to 2 s) would
# make other writers fail under load. Grade first, then append.
module Grading
  # The raw answer of "Non lo so" / "Non l'ho ancora studiato" (decision D-030).
  DONT_KNOW_RAW = '{"dont_know":true}'.freeze

  VERDICTS = %w[correct typical_error wrong dont_know wrong_form near_miss undetermined short_answer invalid].freeze

  class TransactionOpen < StandardError; end

  class << self
    # Grades +raw+ (the stored text of attempts.raw, or an already decoded value)
    # against an item instance. id_map maps the ids shown to the student back to
    # the canonical ids (X-01 shuffles and re-keys). Raises
    # Grading::Expression::Unavailable when the expression worker does not answer:
    # no verdict is written then.
    def grade(item_instance, raw, source: "text", id_map: nil)
      grade_spec(Spec.from_instance(item_instance), raw, source: source, id_map: id_map)
    end

    def grade_spec(spec, raw, source: "text", id_map: nil)
      assert_no_transaction!
      value = decode(spec.component, raw)
      return Result.new(verdict: "dont_know", grader: "closed") if dont_know?(value)

      case spec.component
      when "expression" then Expression.grade(spec, value, source: source)
      when "short_answer" then Result.new(verdict: "short_answer", grader: "closed")
      when "testlet" then Testlet.grade(spec, value, source: source, id_map: id_map)
      else Closed.grade(spec, value, id_map: id_map)
      end
    end

    # Evidence key (X-03) of a stored grading row for the item it was made on.
    def evidence(grading, item_instance)
      Evidence.for_grading(grading, Spec.from_instance(item_instance))
    end

    def git_sha
      @git_sha ||= ENV["BANCO_GIT_SHA"].presence || read_git_sha
    end

    def assert_no_transaction!
      return unless ActiveRecord::Base.connection_pool.active_connection?

      tx = ActiveRecord::Base.connection.current_transaction
      raise TransactionOpen, "grading must not run inside a database transaction" if tx.open? && tx.joinable?
    end

    private

    # Structured components arrive as JSON text; plain components as the typed text.
    def decode(component, raw)
      return raw unless raw.is_a?(String)

      stripped = raw.strip
      if stripped.start_with?("{", "[") && (parsed = parse_json(stripped))
        return parsed if %w[fraction ordering matching testlet].include?(component) || dont_know?(parsed)
      end
      raw
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError
      nil
    end

    def dont_know?(value)
      value.is_a?(Hash) && value.size == 1 && value["dont_know"] == true
    end

    def read_git_sha
      out, status = Open3.capture2e("git", "-C", Rails.root.to_s, "rev-parse", "--short=12", "HEAD")
      status.success? ? out.strip : "unknown"
    rescue SystemCallError
      "unknown"
    end
  end
end
