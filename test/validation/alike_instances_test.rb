require "test_helper"
require_relative "../support/validation_fixtures"

# W-INSTANCES-ALIKE (D-297): the cross-instance rule on the rows the student reads.
class AlikeInstancesTest < ActiveSupport::TestCase
  def matching(left, right = %w[Alfa Beta Gamma])
    { "display" => { "stem_it" => "Abbina.", "left" => left.map { |t| { "text" => t } }, "right" => right.map { |t| { "text" => t } } } }
  end

  def choice(options, stem: "Quale?")
    { "display" => { "stem_it" => stem, "options" => options.map { |t| { "text" => t } } } }
  end

  def ordering(elements) = { "display" => { "stem_it" => "Ordina.", "elements" => elements.map { |t| { "text" => t } } } }

  def pairs(component, list) = Validation::AlikeInstances.pairs(component, list)

  test "a matching sharing more than half of the left rows is alike, the right column does not count" do
    a = matching(%w[Roma Atene Sparta Tebe])
    assert_equal [ [ 0, 1 ] ], pairs("matching", [ a, matching(%w[Roma Atene Sparta Corinto]) ])
    assert_empty pairs("matching", [ a, matching(%w[Roma Atene Argo Corinto]) ])
    assert_empty pairs("matching", [ a, matching(%w[Mileto Argo Elis Corinto]) ]), "same right column, different rows"
  end

  test "the comparison is made after the text grader's normalization" do
    assert_equal [ [ 0, 1 ] ], pairs("matching", [ matching(%w[Roma Atene Sparta Tebe]), matching([ " ROMA.", "atene", "Sparta ", "TEBE" ]) ])
  end

  test "a choice is alike only with the same stem and more than half of the options" do
    a = choice(%w[uno due tre quattro])
    assert_equal [ [ 0, 1 ] ], pairs("choice", [ a, choice(%w[uno due tre cinque]) ])
    assert_empty pairs("choice", [ a, choice(%w[uno due tre cinque], stem: "Quale altro?") ])
    assert_empty pairs("choice", [ a, choice(%w[uno sei sette otto]) ])
  end

  test "an ordering shares elements" do
    assert_equal [ [ 0, 2 ] ], pairs("ordering", [ ordering(%w[a b c d]), ordering(%w[x y z w]), ordering(%w[d c b q]) ])
  end

  test "other components are not compared" do
    assert_empty pairs("number", [ { "display" => { "stem_it" => "x" } }, { "display" => { "stem_it" => "x" } } ])
  end

  test "the runner raises the warning" do
    item = ValidationFixtures.choice_item("instances" => [ ValidationFixtures.choice_instance("sette", %w[tredici nove undici]),
                                                           ValidationFixtures.choice_instance("sette", %w[tredici nove dieci]) ])
    codes = Validation::ItemRunner.new(files: ValidationFixtures.files_for(item), context: ValidationFixtures.context).call.findings.map(&:code)
    assert_includes codes, "W-INSTANCES-ALIKE"
  end
end
