# contract/examples/<command>.<variant>.json: one request and its answer per command,
# written by the integration tests (E-05). With UPDATE_CONTRACT=1 the files are
# written; without it they are compared, so a change of the API that the examples do
# not show fails the test, and CI fails on a dirty diff after an update run. The Go
# tests read the same files (cli/examples_test.go).
#
# Volatile values (database ids, times, digests) are replaced by placeholders, the
# nth distinct id by the number n, so the files are the same on every run.
module ContractExamples
  DIR = Rails.root.join("contract/examples")
  ID_KEYS = /(\A|_)(id|base|revision)\z|_ids?\z/
  TIME = /\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d/

  module_function

  # request/response: the integration test's own objects.
  def record(test, command, variant, request:, response:)
    document = build(command, request, response)
    file = DIR.join("#{command.tr(' ', '-')}.#{variant}.json")
    text = "#{JSON.pretty_generate(document)}\n"
    if ENV["UPDATE_CONTRACT"] == "1"
      FileUtils.mkdir_p(DIR)
      File.write(file, text)
    else
      test.assert File.exist?(file), "contract example #{file.basename} is missing: run the tests with UPDATE_CONTRACT=1"
      test.assert_equal File.read(file), text, "contract example #{file.basename} is out of date: run the tests with UPDATE_CONTRACT=1"
    end
  end

  def build(command, request, response)
    ids = {}
    body = request.raw_post.to_s.empty? ? nil : JSON.parse(request.raw_post)
    req = { "method" => request.request_method, "path" => request.path }
    req["query"] = request.query_string if request.query_string.present?
    req["dry_run"] = true if request.headers["X-Banco-Dry-Run"] == "1"
    req["body"] = scrub(body, ids) if body
    {
      "command" => command,
      "request" => req,
      "response" => { "status" => response.status, "body" => scrub(JSON.parse(response.body), ids) }
    }
  end

  def scrub(node, ids, key = nil)
    case node
    when Hash then node.to_h { |k, v| [ k, scrub(v, ids, k) ] }
    when Array then node.map { |v| scrub(v, ids, key) }
    when Integer
      if key.to_s.match?(ID_KEYS)
        ids[node] ||= ids.size + 1
      else
        node
      end
    when String
      if node.match?(/\A\h{64}\z/) then "<sha256>"
      elsif node.match?(TIME) then "<time>"
      elsif key.to_s == "chrome_version" then "<chrome-version>"
      elsif key.to_s == "grader_version" then "<grader-version>"
      else node
      end
    else node
    end
  end
end

class ActionDispatch::IntegrationTest
  # Records the last request and response as the example of +command+.
  def record_example(command, variant)
    ContractExamples.record(self, command, variant, request: request, response: response)
  end
end
