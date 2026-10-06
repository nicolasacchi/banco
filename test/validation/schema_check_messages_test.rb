# frozen_string_literal: true

require "test_helper"

# D-170: a wrong or missing root of answers.json is reported in one pass, in plain words.
class SchemaCheckMessagesTest < ActiveSupport::TestCase
  test "every wrong root member of a solve file is named at once" do
    findings = Validation::Findings.new
    Validation::SchemaCheck.call("solve", { "schema" => "x", "schema_version" => "1", "revision" => 379, "answers" => [ { "instance" => 1, "answer" => "1" } ] }, findings)
    messages = findings.to_a.map { |f| f.respond_to?(:message) ? f.message : f[:message] || f["message"] }
    assert_includes messages, "/schema must be exactly \"banco.solve/1\", not \"x\""
    assert_includes messages, "/schema_version must be exactly 1, not \"1\""
    assert_includes messages, "/revision must be a string (in quotes), not 379"
  end

  test "all missing root members are listed together" do
    findings = Validation::Findings.new
    Validation::SchemaCheck.call("solve", { "answers" => [ { "instance" => 1, "answer" => "1" } ] }, findings)
    assert_match(/schema, schema_version, revision/, findings.to_a.map(&:to_s).join)
  end
end
