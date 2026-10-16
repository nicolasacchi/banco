require "test_helper"

# The lexical engine on its own scope-free ground: a small invented corpus built by hand, searched through the staff's scope.
class SearchEngineTest < ActiveSupport::TestCase
  DOCS = [
    [ "lesson_card", "ripasso.math.potenze", "Le potenze", "Una potenza è una moltiplicazione ripetuta: tre alla seconda fa nove.", "math" ],
    [ "lesson_card", "ripasso.math.equazioni", "Le equazioni di primo grado", "Un'equazione è una bilancia in equilibrio. Si risolve con le operazioni inverse.", "math" ],
    [ "lesson_card", "lezione.law.costituzione", "La Costituzione", "La costituzione italiana è entrata in vigore nel 1948. La città e i suoi diritti.", "law_economics" ],
    [ "glossary_term", "lezione.law.costituzione", "Repubblica", "Forma di Stato in cui il capo dello Stato non è un re.", "law_economics" ],
    [ "item", "math-frazioni-1", "Calcola la somma di due frazioni", "Frazioni con denominatore diverso: denominatore comune.", "math" ],
    [ "skill", "math.powers-properties", "Proprietà delle potenze", "Moltiplicare e dividere potenze della stessa base.", "math" ],
    [ "reference_article", "costituzione-test", "Costituzione · Art. 3", "Tutti i cittadini hanno pari dignità sociale e sono eguali davanti alla legge.", nil ]
  ].freeze

  setup do
    Search::Index.replace_group("lessons", DOCS.each_with_index.map do |(kind, key, title, body, subject), i|
      Search::Doc.build(kind: kind, key: key, title: title, body: body, subject: subject, status: "draft", unique: i)
    end)
    @engine = Search::Engine.new(scope: Search::Scope::Staff.new)
  end

  def titles(query, **options) = @engine.call(query, **options).hits.map(&:title)

  test "a stem matches the plural and the singular, both ways" do
    assert_includes titles("equazioni"), "Le equazioni di primo grado"
    assert_includes titles("equazione"), "Le equazioni di primo grado"
    assert_includes titles("potenza"), "Le potenze"
    assert_includes titles("potenze"), "Le potenze"
  end

  test "Snowball decides: frazionaria does not find frazioni because their stems differ" do
    assert_not_equal Search::Text.stem("frazionaria", "it"), Search::Text.stem("frazioni", "it")
    assert_not_includes titles("frazionaria"), "Calcola la somma di due frazioni"
    assert_includes titles("frazioni"), "Calcola la somma di due frazioni"
    assert_includes titles("frazione"), "Calcola la somma di due frazioni"
  end

  test "accents never matter" do
    assert_includes titles("citta"), "La Costituzione"
    assert_includes titles("città"), "La Costituzione"
    assert_includes titles("equazione e"), "Le equazioni di primo grado"
  end

  test "a typo is corrected against the words the scope can see" do
    result = @engine.call("equazone")
    assert_equal "Le equazioni di primo grado", result.hits.first.title
    assert_equal :typo, result.hits.first.match
    assert_includes result.variants, "equazione"
    assert_includes titles("costituzone"), "La Costituzione"
    assert_includes titles("potnze"), "Le potenze"
  end

  test "a short word is not guessed" do
    assert_empty titles("zq")
  end

  test "the last word is a prefix while the question is being typed" do
    assert_includes titles("equaz"), "Le equazioni di primo grado"
    assert_includes titles("moltiplic"), "Le potenze"
  end

  test "all the words first, then any of them" do
    assert_equal [ "Le potenze" ], titles("potenza moltiplicazione").first(1)
    widened = titles("bilancia equilibrio costituzione")
    assert_includes widened, "Le equazioni di primo grado"
    assert_includes widened, "La Costituzione"
  end

  test "a question in words is searched by its content words" do
    assert_includes titles("come si fa la potenza di un numero").first(3), "Le potenze"
  end

  test "the title weighs more than the body" do
    Search::Index.replace_group("extra", [ Search::Doc.build(kind: "lesson_card", key: "a", title: "Altro argomento", body: "zzparola zzparola zzparola zzparola"),
                                           Search::Doc.build(kind: "lesson_card", key: "b", title: "Zzparola", body: "un testo") ])
    assert_equal [ "Zzparola", "Altro argomento" ], titles("zzparola")
  end

  test "an exact key comes first, whatever its case" do
    assert_equal "Proprietà delle potenze", titles("math.powers-properties").first
    assert_equal "Proprietà delle potenze", titles("MATH.Powers-Properties").first
    assert_equal :key, @engine.call("math.powers-properties").hits.first.match
  end

  test "filters: subject, kind, status, and the limit" do
    assert_equal [ "Costituzione · Art. 3" ], titles("costituzione", kind: "reference_article")
    assert_empty titles("costituzione", subject: "math")
    assert_equal [ "La Costituzione" ], titles("costituzione", subject: "law_economics", kind: %w[lesson_card])
    assert_empty titles("potenze", status: "approved")
    assert_equal 1, @engine.call("potenze", limit: 1).hits.size
  end

  test "a kind the scope does not have is refused, not dropped" do
    assert_raises(Search::Engine::BadKind) { @engine.call("x", kind: "student_answer") }
    assert_raises(Search::Engine::BadKind) { @engine.call("x", kind: "nonsense") }
  end

  test "hostile text is only words" do
    [ %q("), %q(equazioni" OR "x), "a* AND NOT b", "{title}:x", "(((", "NEAR(a b)", "'; DROP TABLE search_documents; --", "\u0000" ].each do |text|
      assert_nothing_raised { @engine.call(text) }
    end
    assert_operator Search::Index.count, :>, 0
  end

  test "an empty or wordless question has no hits and says whether the index is built" do
    result = @engine.call("   ")
    assert_empty result.hits
    assert result.indexed
    assert_empty @engine.call("???").hits
    assert_equal false, result.semantic
  end

  test "the snippet marks the matching words" do
    result = @engine.call("equazioni")
    hit = result.hits.first
    assert_equal "Un'equazione è una bilancia in equilibrio. Si risolve con le operazioni inverse.", hit.snippet(result.terms)
    assert_includes hit.segments(result.terms).select(&:last).map(&:first), "equazione"
  end
end
