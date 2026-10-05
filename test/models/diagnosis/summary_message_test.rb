require "test_helper"

class SummaryMessageTest < ActiveSupport::TestCase
  Rev = Struct.new(:body_json)
  Serve = Struct.new(:item_instance)
  Inst = Struct.new(:item_revision)

  def revision(skill, message)
    Rev.new({ skill: skill, error_catalogue: [ { code: "shared", message_it: message } ] }.to_json)
  end

  test "the recover message comes from the item where the error happened (D-089)" do
    summary = Diagnosis::Summary.allocate
    a = Serve.new(Inst.new(revision("s.a", "message A")))
    b = Serve.new(Inst.new(revision("s.b", "message B")))
    ea = Struct.new(:id).new(1)
    eb = Struct.new(:id).new(2)
    summary.define_singleton_method(:served) { [ [ ea, a ], [ eb, b ] ] }
    summary.define_singleton_method(:codes_of) { |event| event.id == 1 ? [ "shared" ] : [] }
    assert_equal "message A", summary.send(:recover_message, { skill: "s.a", error_codes: [ "shared" ] })
    # the last served item no longer wins
    assert_equal "message A", summary.send(:recover_message, { skill: "s.b", error_codes: [ "shared" ] })
    summary.define_singleton_method(:codes_of) { |event| [ "shared" ] }
    assert_equal "message B", summary.send(:recover_message, { skill: "s.b", error_codes: [ "shared" ] })
  end
end
