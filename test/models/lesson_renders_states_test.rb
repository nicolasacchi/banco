require "test_helper"

# The further states of a lesson card the render check pictures (D-311, D-402): exN, open, exN-open, and the card with every translation open (tr, exN-tr).
class LessonRendersStatesTest < ActiveSupport::TestCase
  test "the translation states rank after the card as drawn and sit with their exercise" do
    ranks = [ nil, "open", "tr", "ex1", "ex1-open", "ex1-tr", "ex2" ].map { |state| LessonRenders.state_rank(state) }
    assert_equal ranks.sort, ranks, "the card as drawn, opened, with the translation open, then each exercise and its states, in this order"
    assert_equal ranks.uniq, ranks
    assert_equal [ 0, 0 ], LessonRenders.state_rank(nil)
  end

  test "each state has its words in Italian, the translation ones included" do
    assert_nil LessonRenders.state_words(nil)
    assert_equal "esercizio 2", LessonRenders.state_words("ex2")
    assert_equal "con le parti chiuse aperte", LessonRenders.state_words("open")
    assert_equal "con la traduzione in italiano aperta", LessonRenders.state_words("tr")
    assert_equal "esercizio 3, con la traduzione in italiano aperta", LessonRenders.state_words("ex3-tr")
    assert_equal "strano", LessonRenders.state_words("strano")
  end
end
