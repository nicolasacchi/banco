require "test_helper"

# Grading::Closed::Text.normalize strips trailing punctuation in linear time:
# a 20 KB answer of "a. . . ." used to hold the process for about 16 s.
class TextNormalizeTest < ActiveSupport::TestCase
  Text = Grading::Closed::Text

  test "trailing punctuation and spaces are stripped" do
    assert_equal "ciao", Text.normalize("Ciao ... ")
    assert_equal "a, b", Text.normalize("a, b ?! ;")
    assert_equal "", Text.normalize(" . , ")
    assert_equal "perché", Text.normalize("Perché…")
    assert_equal "un po'", Text.normalize("un po'.")
  end

  test "a 20 KB answer that pairs a dot with a space is normalized at once" do
    [ "a" + ". " * 9_990, "à" + "? " * 9_990, "a" + "., " * 6_600 ].each do |raw|
      result = nil
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = Text.normalize(raw)
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      assert_equal raw[0], result
      assert_operator seconds, :<, 1.0, "normalize took #{seconds.round(2)} s"
    end
  end
end
