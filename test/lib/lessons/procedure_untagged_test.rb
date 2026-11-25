require "test_helper"

# A procedure step may have no tag (D-402, round 7): two «Rileggi» in a row would only repeat, so the step has no chip. A tag that is given must still be one
# of the subject's step tags. The page half: app/javascript/lesson/test/procedure_untagged.test.mjs.
class ProcedureUntaggedTest < ActiveSupport::TestCase
  def block(*steps) = { "n" => 2, "type" => "procedure", "title_it" => "Come fare", "steps" => steps }

  def run_check(block, subject: "english")
    findings = Validation::Findings.new
    ctx = Lessons::Blocks::Context.new(subject: subject, findings: findings)
    ctx.at("/cards/2/blocks/1", 7) { Lessons::Blocks::Simple.check(block, ctx) }
    findings.map { |f| [ f.code, f.field ] }
  end

  test "a step without a tag passes the checks, and the schema asks only for its text" do
    steps = [ { "tag" => "reread", "text_it" => "Rileggi il testo." }, { "text_it" => "Rileggi ancora." } ]
    assert_empty run_check(block(*steps))
    required = JSON.parse(Rails.root.join("config/banco/schemas/lesson.json").read).dig("$defs", "b_procedure", "properties", "steps", "items", "required")
    assert_equal [ "text_it" ], required
  end

  test "a tag that is given is still checked" do
    assert_equal [ [ "E-LESSON-BLOCK", "/cards/2/blocks/1/steps/1/tag" ] ], run_check(block({ "tag" => "reread", "text_it" => "Rileggi." }, { "tag" => "nonsense", "text_it" => "Altro." }))
  end
end
