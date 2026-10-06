require "test_helper"

# D-121: closed items pinned on the skill of the short answer are never served.
class ShortSkillClosedTest < ActiveSupport::TestCase
  def info(id, kind)
    Validation::BlueprintChecks::ItemInfo.new(id: id, skills: %w[law.apply], passed: true, kind: kind,
                                              instances: (1..4).map { |i| { fingerprint: "#{id}-#{i}", low_guess: true } })
  end

  def run_entry(entry, infos)
    f = Validation::Findings.new
    infos = Validation::BlueprintChecks.closed_beside_short(entry, infos, "/entries/0", f)
    Validation::BlueprintChecks.pool_for_redo(entry, infos, "/entries/0", f)
    f.map(&:code)
  end

  test "closed items beside the short answer warn and do not count for the redo pool" do
    entry = { "skill" => "law.apply", "items" => %w[91 89 90] }
    assert_equal %w[W-SHORT-SKILL-CLOSED E-POOL-REDO], run_entry(entry, [ info("91", "short_answer"), info("89", "diagnosis_item"), info("90", "diagnosis_item") ])
  end

  test "a short answer alone with redo_reserve false is quiet, and without a short answer nothing changes" do
    assert_empty run_entry({ "skill" => "law.apply", "items" => %w[91], "redo_reserve" => false }, [ info("91", "short_answer") ])
    assert_empty run_entry({ "skill" => "law.apply", "items" => %w[1 2] }, [ info("1", "diagnosis_item"), info("2", "diagnosis_item") ])
  end
end
