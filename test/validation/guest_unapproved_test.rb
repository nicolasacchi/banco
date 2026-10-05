require "test_helper"

# D-129: a guest starting skill from a graph that is not approved yet is accepted in a
# draft (warning), and refused at approval.
class GuestUnapprovedTest < ActiveSupport::TestCase
  def run_entry(context, skill: "italian.reading", guest: "italian")
    f = Validation::Findings.new
    Validation::BlueprintChecks.guest_entry({ "skill" => skill }, "/entries/0", guest, context, f)
    f.map(&:code)
  end

  def context(approved: nil, draft: nil)
    Validation::Context.new(subject: "math", approved_skill: ->(k) { k == approved ? { "key" => k } : nil },
                            draft_skill: ->(k) { k == draft ? { "key" => k } : nil })
  end

  test "approved: quiet; draft only: warning; nowhere or wrong subject: error" do
    assert_empty run_entry(context(approved: "italian.reading"))
    assert_equal %w[W-GUEST-UNAPPROVED], run_entry(context(draft: "italian.reading"))
    assert_equal %w[E-SKILL-UNKNOWN], run_entry(context)
    assert_equal %w[E-SKILL-UNKNOWN], run_entry(context(draft: "law.x"), skill: "law.x")
  end

  test "the gate lists a guest skill whose graph is not approved" do
    subject = Subject.create!(key: "italian", name_it: "Italiano", position: 3)
    graph = SkillGraphRevision.create!(subject: subject, seq: 1, body_json: { "skills" => [ { "key" => "italian.reading" } ] }.to_json)
    math = Subject.create!(key: "math", name_it: "Matematica", position: 1)
    mgraph = SkillGraphRevision.create!(subject: math, seq: 1, body_json: { "skills" => [] }.to_json)
    bp = BlueprintRevision.create!(subject: math, skill_graph_revision: mgraph, seq: 1,
                                   body_json: { "entries" => [ { "skill" => "italian.reading", "guest_of_subject" => "italian", "items" => [] } ] }.to_json)
    assert_includes Approval::BlueprintGate.check(bp).reasons, "the guest skill italian.reading is not in an approved graph of its subject"
    assert graph
  end
end
