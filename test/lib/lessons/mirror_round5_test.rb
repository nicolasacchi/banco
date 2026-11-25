require "test_helper"

# D-402, round 5 of the bilingual tooling, the Ruby half of the mirror: the link kind `meaning` (drawn «stesso significato», no note needed, not the same as `same`)
# and plain text (markup in a note or an alt is refused with a message that says what to write). The browser half: app/javascript/lesson/test/mirror_round5.test.mjs.
class MirrorRound5Test < ActiveSupport::TestCase
  M = Lessons::Diagrams::Mirror
  ALT = "Una frase italiana sopra la stessa frase nell'altra lingua, pezzo per pezzo, con le coppie.".freeze

  def figure(links: [ [ 1, 0, "meaning" ], [ 2, 1, "same" ] ], notes: [ { "side" => "it", "piece" => 0, "note_it" => "l'articolo non c'è in spagnolo" } ], **top)
    { "type" => "mirror", "alt_it" => ALT, "rows" => [ { "pieces_it" => %w[I miei cugini], "pieces_es" => %w[mis primos], "links" => links, "notes" => notes } ] }.merge(top.stringify_keys)
  end

  def found(data) = Lessons::Diagrams.check(data, subject: "spanish").map { |f| [ f.code, f.path ] }

  test "a meaning link is in the schema, drawn «stesso significato», and needs no note; same stays «uguale»" do
    assert_empty Banco::Schemas.validate("diagram", figure).map(&:to_h)
    assert_empty found(figure)
    assert_equal "stesso significato", M.kind_word("meaning")
    assert_equal "uguale", M.kind_word("same")
    assert_includes M.printed(figure, 0), "stesso significato"
    assert_includes M.describe(figure), "miei e mis: stesso significato."
  end

  test "a shift still needs its note, and a figure whose links are all meaning links is not the all-same refusal" do
    assert_equal [ [ "E-LESSON-DIAGRAM", "/rows/0/notes" ] ], found(figure(links: [ [ 1, 0, "shift" ], [ 2, 1, "same" ] ]))
    assert_empty found(figure(links: [ [ 1, 0, "meaning" ], [ 2, 1, "meaning" ] ]))
    assert_equal [ [ "E-LESSON-DIAGRAM", "/same_ok" ] ], found(figure(same_ok: true))
  end

  test "markup in a note or in the alt is refused: plain text, a quoted word is written in «…»" do
    note = figure(notes: [ { "side" => "it", "piece" => 0, "note_it" => "scrivi [[es:los]], non l'articolo" } ])
    assert_equal [ [ "E-LESSON-DIAGRAM", "/rows/0/notes/0/note_it" ] ], found(note)
    assert_match(/«…»/, Lessons::Diagrams.check(note, subject: "spanish").first.message)
    alt = figure(alt_it: "Una frase italiana sopra la stessa frase in [[es:español]], pezzo per pezzo, con le coppie.")
    assert_equal [ [ "E-LESSON-ALT", "/alt_it" ] ], found(alt)
    assert_empty found(figure(notes: [ { "side" => "it", "piece" => 0, "note_it" => "scrivi «los», non l'articolo" } ]))
  end

  test "W-MIRROR-ORDER: crossing links warn once per row, with a message that says to pick parallel sentences; the parallel order does not (D-402, round 7)" do
    crossed = figure(links: [ [ 0, 1, "meaning" ], [ 1, 0, "same" ], [ 2, 1, "same" ] ], notes: [])
    crossed["rows"][0]["pieces_it"] = %w[Ieri mangio pesce]
    crossed["rows"][0]["pieces_es"] = %w[comí ayer]
    assert_equal [ [ "W-MIRROR-ORDER", "/rows/0/links" ] ], found(crossed)
    warning = Lessons::Diagrams.check(crossed, subject: "spanish").find { |f| f.code == "W-MIRROR-ORDER" }
    assert_match(/pick parallel sentences/, warning.message)
    assert_equal "warning", Validation::Codes.severity("W-MIRROR-ORDER")
    # the Italian order and the target order agree, a piece linked twice or a piece with no link does not make a crossing
    assert_empty found(figure)
    assert_empty found(figure(links: [ [ 1, 0, "meaning" ], [ 2, 0, "same" ], [ 2, 1, "same" ] ]).tap { |f| f["rows"][0]["notes"] = [ { "side" => "it", "piece" => 0, "note_it" => "l'articolo non c'è in spagnolo" } ] })
  end
end
