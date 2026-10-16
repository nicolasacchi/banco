require "test_helper"

class SearchTextTest < ActiveSupport::TestCase
  T = Search::Text

  test "Snowball stems of the three languages" do
    assert_equal T.stem("equazioni", "it"), T.stem("equazione", "it")
    assert_equal "equazion", T.stem("equazioni", "it")
    assert_equal T.stem("potenza", "it"), T.stem("potenze", "it")
    assert_not_equal T.stem("frazione", "it"), T.stem("fratello", "it")
    assert_equal T.stem("niños", "es"), T.stem("niño", "es")
    assert_equal "run", T.stem("running", "en")
    assert_equal T.stem("equations", "en"), T.stem("equation", "en")
    assert_equal "3", T.stem("3", "it"), "numbers are left alone"
  end

  test "the stems of a word over the languages" do
    assert_includes T.stems("equazioni"), "equazion"
    assert_equal [ "run" ], T.stems("running", %w[en])
  end

  test "folding removes accents and case" do
    assert_equal "perche citta", T.fold("Perché CITTÀ")
    assert_equal %w[l equazione di primo grado], T.tokens("L'equazione di primo grado")
  end

  test "agents' markup becomes plain words" do
    markup = "La **soluzione** di $x + 1 = 2$ è [[g:numero]] e [[en:hello]] e [[role|it:parole]] (vedi [la scheda](scheda:a-b))."
    assert_equal "La soluzione di è numero e hello e parole (vedi la scheda).", T.plain(markup)
  end

  test "strings reads the values that carry words and skips the machinery" do
    node = { "type" => "text", "n" => 1, "text_it" => "Una **bella** frase.", "options" => [ { "id" => "o1", "text_it" => "Prima" } ], "answer" => "SEGRETO", "icon" => "x" }
    assert_equal [ "Una bella frase.", "Prima" ], T.strings(node)
  end

  test "stop words are dropped from a question, never from one word" do
    assert_equal %w[calcola potenza numero], T.content_terms(T.query_terms("come si calcola la potenza di un numero"))
    assert_equal %w[di], T.content_terms(%w[di])
  end

  test "edit distance and the tolerance of a word" do
    assert_equal 1, T.distance("equazone", "equazione")
    assert_operator T.distance("equazone", "frazione", 2), :>, 2
    assert_equal 0, T.tolerance("sei")
    assert_equal 1, T.tolerance("sesto")
    assert_equal 2, T.tolerance("equazione")
  end

  test "the snippet marks the words that matched, by stem and by prefix, and cuts around the first" do
    body = "Una lunga introduzione che non dice nulla. " * 5 + "Le equazioni servono in quasi ogni problema."
    segments = T.snippet(body, %w[equazione probl], width: 120)
    assert_includes segments.select(&:last).map(&:first), "equazioni"
    assert_includes segments.select(&:last).map(&:first), "problema"
    assert_operator segments.map(&:first).join.length, :<, 200
    assert_equal [], T.snippet("", %w[x])
  end
end
