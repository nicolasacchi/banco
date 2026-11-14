require "test_helper"

class ContractTest < ActiveSupport::TestCase
  test "contract is valid JSON with unique command names" do
    c = Contract.parsed
    assert_equal 1, c["contract_version"]
    names = c["commands"].map { |x| x["name"] }
    assert_equal names.uniq, names
    assert_includes names, "version"
    assert_includes names, "schema"
  end

  test "every non-local command has a method and a path, local ones have neither" do
    Contract.parsed["commands"].each do |cmd|
      if cmd["local"]
        assert_nil cmd["path"], cmd["name"]
      else
        assert cmd["method"].present? && cmd["path"].present?, cmd["name"]
      end
    end
  end

  # D-327: the teacher token's `decide` and its list `decisions` are the only commands that name a decision; the server
  # answers them to a teacher token (and the list to bot_read), never to a content agent's.
  test "no command takes a decision but the teacher token's decide and decisions" do
    names = Contract.parsed["commands"].map { |c| c["name"] }
    assert_equal %w[decide decisions], names.grep(/decision|decide|approve|confirm|release/)
  end

  test "digest changes with the file content" do
    assert_match(/\A\h{64}\z/, Contract.digest)
  end
end
