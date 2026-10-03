require "test_helper"
require "rake"

class ApiTokenTest < ActiveSupport::TestCase
  test "issue returns a token in the D-05 format and stores only the sha256 of the secret" do
    token = ApiToken.issue!(role: "agent_claude", label: "test")
    m = Banco::TokenAuth::FORMAT.match(token)
    assert m, "token format"
    row = ApiToken.find_by!(public_id: m[1])
    assert_equal Digest::SHA256.hexdigest(m[2]), row.secret_sha256
    assert_not_includes row.attributes.values.map(&:to_s), m[2]
    assert_not_includes row.attributes.values.map(&:to_s), token
  end

  test "two tokens differ and a role outside the list is refused" do
    assert_not_equal ApiToken.issue!(role: "ci", label: "a"), ApiToken.issue!(role: "ci", label: "a")
    assert_raises(ActiveRecord::RecordInvalid) { ApiToken.issue!(role: "operator", label: "x") }
  end

  test "lookup knows a live token and forgets a revoked one" do
    token = ApiToken.issue!(role: "agent_omp", label: "x")
    id = Banco::TokenAuth::FORMAT.match(token)[1]
    assert_equal "agent_omp", ApiToken.lookup(id)[:role]
    ApiTokenRevocation.create!(api_token: ApiToken.find_by!(public_id: id), reason: "test")
    assert_nil ApiToken.lookup(id)
    assert_nil ApiToken.lookup("zzzzzzzz")
  end

  test "authentication through the registry accepts the right secret and refuses a wrong one" do
    token = ApiToken.issue!(role: "agent_claude", label: "x")
    assert_equal "agent_claude", Banco::TokenAuth.authenticate("Bearer #{token}").role
    assert_nil Banco::TokenAuth.authenticate("Bearer #{token.sub(/.\z/) { |c| c == 'a' ? 'b' : 'a' }}")
  end

  test "the registry is append-only" do
    ApiToken.issue!(role: "ci", label: "x")
    assert_raises(ActiveRecord::StatementInvalid) { ApiToken.last.update_columns(label: "y") }
    assert_raises(ActiveRecord::StatementInvalid) { ApiToken.last.delete }
  end

  test "banco:token:issue prints the token once and stores no plaintext" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:token:issue")
    task = Rake::Task["banco:token:issue"]
    task.reenable
    out = nil
    with_env("ROLE" => "agent_claude", "LABEL" => "rake test") do
      out, = capture_io { task.invoke }
    end
    token = out.strip
    assert_match Banco::TokenAuth::FORMAT, token
    assert_equal 1, out.lines.size
    assert ApiToken.lookup(Banco::TokenAuth::FORMAT.match(token)[1])
  end

  test "banco:token:issue refuses a missing or unknown role" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("banco:token:issue")
    task = Rake::Task["banco:token:issue"]
    [ nil, "root" ].each do |role|
      task.reenable
      with_env("ROLE" => role) do
        assert_raises(SystemExit) { capture_io { task.invoke } }
      end
    end
  end
end
