require "test_helper"

class SyllabusBlockMarkerTest < ActiveSupport::TestCase
  Row = Struct.new(:number, :text, :origin, :marker)

  def rows(*specs)
    specs.each_with_index.map do |(text, marker, origin), i|
      Row.new(i + 1, text, origin || "pdf", marker)
    end
  end

  test "the body under a starred header inherits the star; the next header ends the block" do
    result = Syllabus::BlockMarker.call(rows(
      [ "★ La Costituzione e i principi:", "★" ],
      [ "Origini storiche. Struttura. Analisi dei primi 12 articoli." ],
      [ "Economia" ],
      [ "Nozione di economia. Bisogni economici." ]
    ))
    assert_equal({ 2 => { marker: "★", from: 1 } }, result)
  end

  test "a marked content line opens no block; a blank line closes one" do
    result = Syllabus::BlockMarker.call(rows(
      [ "★ Consumo, risparmio e investimenti: il consumo e la propensione al consumo; il risparmio.", "★" ],
      [ "Costi e ricavi, con un testo lungo che finisce con un punto." ],
      [ "☆ Un titolo breve", "☆" ],
      [ "", nil, "transcript" ],
      [ "Testo dopo la riga vuota." ]
    ))
    assert_equal({}, result)
  end

  test "scopes_for follows the legend" do
    assert_equal %w[integration_studied], Syllabus::BlockMarker.scopes_for("★")
    assert_equal %w[in_progress], Syllabus::BlockMarker.scopes_for("★☆")
    assert_equal %w[studied], Syllabus::BlockMarker.scopes_for(nil)
  end
end
