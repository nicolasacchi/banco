require "test_helper"
require_relative "../support/decision_world"
require_relative "../support/multi_user"
require_relative "../support/arbiter_rows"

# D-222: the third reviewer on the teacher's pages: the card with its two opinions, "Segui il
# parere" for one finding and for all the clear ones, and the minor findings as a derived state.
class ThirdReviewerPagesTest < ActionDispatch::IntegrationTest
  include DecisionWorld
  include MultiUser
  include ArbiterRows

  SKILL_PAGE = "/teacher/subjects/math/test/skills/math.normalized-text".freeze

  setup do
    build_decision_world
    @revision = @world[:revisions]["normalized_text"]
  end

  def page(path, headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  def finding!(severity: "major", field: "stem", problem: "Ambiguo.")
    ReviewFinding.create!(item_revision: @revision, source: "review", severity: severity, field: field, quote: "x", problem_it: problem, fix_it: "Chiarisci.")
  end

  def decisions = Decision.where(kind: "dispose_finding")

  test "the card says what the finding is about and whether S sees it, with neutral buttons" do
    sources = finding!(field: "sources/1")
    odd = finding!(field: "weird_new_thing")
    page SKILL_PAGE
    assert_select "#finding-#{sources.id} .field-line", /Riguarda:\s*le fonti: le righe di programma collegate alla domanda\. S non le vede\./
    assert_select "#finding-#{odd.id} .field-line", /Riguarda:.*weird_new_thing.*Non so dire se S la vede/
    assert_select "#finding-#{odd.id} button[value=dismissed]", "Va bene così: scarta il rilievo"
    assert_select "#finding-#{odd.id} button[value=fix_requested]", "Va sistemato: chiedi la correzione"
  end

  test "two agreeing opinions are shown as clear, both notes labelled, with Segui il parere prefilled" do
    f = finding!
    assess!(f, "author_right", session: arbiter_session(ArbiterRows::FIRST_MODEL), note: "Il testo è chiaro: una sola lettura.")
    assess!(f, "author_right", session: arbiter_session(ArbiterRows::SECOND_MODEL), note: "Non vedo ambiguità.")
    page SKILL_PAGE
    assert_select "#finding-#{f.id} .opinions[data-opinion-state=clear][data-opinion-verdict=author_right]", /Concordi: terzo revisore e secondo parere/
    assert_select "#finding-#{f.id} [data-opinion=first]", /Terzo revisore, primo parere:.*ha ragione l'autore.*una sola lettura/m
    assert_select "#finding-#{f.id} [data-opinion=second]", /Secondo parere:.*Non vedo ambiguità/m
    assert_select "#finding-#{f.id} button[data-follow=author_right]", "Segui il parere"
    assert_select "#finding-#{f.id} input[name=reason_it][value='Seguo il parere del terzo revisore.']"
    assert_select "#finding-#{f.id} input[name=disposition][value=dismissed]"
    assert_equal 0, decisions.count
  end

  test "a lone opinion waits, a split is flagged, neither can be followed" do
    waiting = finding!
    split = finding!(problem: "Altro.")
    assess!(waiting, "finding_right", session: arbiter_session(ArbiterRows::FIRST_MODEL))
    assess!(split, "author_right", session: arbiter_session(ArbiterRows::FIRST_MODEL))
    assess!(split, "finding_right", session: arbiter_session(ArbiterRows::SECOND_MODEL))
    page SKILL_PAGE
    assert_select "#finding-#{waiting.id} .opinions[data-opinion-state=waiting]", /In attesa del secondo parere/
    assert_select "#finding-#{split.id} .opinions[data-opinion-state=split]", /Pareri discordanti/
    assert_select "#finding-#{split.id} [data-opinion=first][data-assessment=author_right]"
    assert_select "#finding-#{split.id} [data-opinion=second][data-assessment=finding_right]"
    assert_select "[data-follow]", 0
    page "/teacher/subjects/math/test"
    assert_select "#open-findings h2", "Rilievi da decidere: 2, di cui nessuno con un parere chiaro."
    assert_select "#follow-opinions-form", 0
  end

  test "following one clear opinion records the usual decision with every guard" do
    f = finding!
    assess_both!(f, "finding_right")
    page SKILL_PAGE
    assert_select "#finding-#{f.id} button[data-follow=finding_right]"
    assert_select "#finding-#{f.id} input[name=disposition][value=fix_requested]"
    decide("/teacher/findings/#{f.id}/disposition", { disposition: "fix_requested", reason_it: "Seguo il parere del terzo revisore." })
    assert_response :success
    assert_equal [ "fix_requested", "Seguo il parere del terzo revisore." ], decisions.map { |d| JSON.parse(d.payload_json).values_at("disposition", "reason_it") }.sole
    decide("/teacher/findings/#{finding!.id}/disposition", { disposition: "dismissed", reason_it: "Prova." }, csrf: false)
    assert_response :forbidden
    assert_equal 1, decisions.count
  end

  test "the overview counts the open findings and those with a clear opinion, and one button follows them all" do
    a = finding!
    b = finding!(problem: "Due.")
    finding!(problem: "Tre.")
    assess_both!(a, "author_right")
    assess_both!(b, "finding_right")
    page "/teacher/subjects/math/test"
    assert_select "#open-findings h2", "Rilievi da decidere: 3, di cui 2 con un parere chiaro."
    assert_select "#clear-list li[data-clear-finding]", 2
    assert_select "#clear-list li[data-clear-finding='#{a.id}']", /ha ragione l'autore/
    assert_select "#follow-opinions-form button", "Segui il parere su questi 2"
    assert_select "#follow-opinions-form input[name='pairs[]'][value='#{a.id}:author_right']"
    assert_select "#follow-opinions-form input[name='pairs[]'][value='#{b.id}:finding_right']"
  end

  test "the bulk button records one decision per finding; stale, decided, changed and minor ones are skipped and said" do
    a = finding!
    b = finding!(problem: "Due.")
    decided = finding!(problem: "Tre.")
    changed = finding!(problem: "Quattro.")
    minor = finding!(severity: "minor", problem: "Lieve.")
    [ a, decided, changed, minor ].each { |f| assess_both!(f, "author_right") }
    assess_both!(b, "finding_right")
    pairs = [ a, b, decided, changed, minor ].map { |f| "#{f.id}:#{f.opinion.verdict}" }
    Decision.create!(kind: "dispose_finding", subject: @subject, payload_json: { finding_id: decided.id, disposition: "fix_requested", reason_it: "Già." }.to_json,
                     request_id: SecureRandom.uuid, teacher_login: "nik", groups: "banco-teacher", remote_addr: EDGE)
    assess!(changed, "finding_right", session: arbiter_session(ArbiterRows::SECOND_MODEL))
    pairs << "#{a.id + 10_000}:author_right" << "garbage"
    decide("/teacher/subjects/math/follow-opinions", { pairs: pairs })
    assert_response :success, response.body
    assert_equal [ 2, 5 ], json.values_at("decided", "skipped")
    followed = decisions.where.not(id: decisions.first.id).map { |d| JSON.parse(d.payload_json).values_at("finding_id", "disposition", "reason_it") }
    assert_equal [ [ a.id, "dismissed", "Seguo il parere del terzo revisore." ], [ b.id, "fix_requested", "Seguo il parere del terzo revisore." ] ].sort, followed.sort
    assert_equal 3, decisions.count
    assert_equal decisions.count, decisions.distinct.count(:request_id)
    assert_match(/già deciso/, json["lines"].join(" "))
    assert_match(/non è più chiaro/, json["lines"].join(" "))
    assert_match(/non è un rilievo grave/, json["lines"].join(" "))
    assert_nil minor.reload.disposition
    # The same request again records nothing new: the findings are decided now.
    decide("/teacher/subjects/math/follow-opinions", { pairs: pairs.first(2) })
    assert_equal [ 0, 2 ], json.values_at("decided", "skipped")
    assert_equal 3, decisions.count
  end

  test "the bulk route refuses a missing token, a student and a guest, and writes nothing" do
    a = finding!
    assess_both!(a, "author_right")
    body = { pairs: [ "#{a.id}:author_right" ] }
    decide("/teacher/subjects/math/follow-opinions", body, csrf: false)
    assert_response :forbidden
    decide("/teacher/subjects/math/follow-opinions", body, headers: GUEST, remote_addr: EDGE)
    assert_response :forbidden
    decide("/teacher/subjects/math/follow-opinions", body, headers: { "Remote-User" => "student", "Remote-Groups" => "banco-student" })
    assert_response :forbidden
    assert_equal 0, decisions.count
    page "/teacher/subjects/math/test", headers: GUEST
    assert_response :success
    assert_select "form", 0
    assert_select "#clear-list li", 1
    page SKILL_PAGE, headers: GUEST
    assert_select "[data-finding='#{a.id}'] .opinions"
    assert_select "[data-finding] form", 0
  end

  test "a minor finding with two agreeing opinions is closed or to fix as a derived state, in a collapsed list, never counted" do
    closed = finding!(severity: "minor", problem: "Lieve uno.")
    to_fix = finding!(severity: "minor", problem: "Lieve due.")
    open_minor = finding!(severity: "minor", problem: "Lieve tre.")
    assess_both!(closed, "author_right")
    assess_both!(to_fix, "finding_right")
    assess!(open_minor, "author_right", session: arbiter_session(ArbiterRows::FIRST_MODEL))
    before = Decision.count
    page SKILL_PAGE
    assert_select "details.minor-findings[data-minor-findings='3'] summary", "Rilievi lievi (3): non serve decidere"
    assert_select "details.minor-findings #finding-#{closed.id} .closure[data-closure=closed]", "Chiuso dal terzo revisore"
    assert_select "details.minor-findings #finding-#{closed.id} [data-opinion=first]"
    assert_select "details.minor-findings #finding-#{to_fix.id} .closure[data-closure=to_fix]", "Da sistemare: lo dice il terzo revisore"
    assert_select "details.minor-findings #finding-#{open_minor.id} .closure", 0
    assert_select "details.minor-findings #finding-#{open_minor.id} form button[value=dismissed]"
    assert_select "[data-follow]", 0
    page "/teacher/subjects/math/test"
    assert_select "#open-findings h2", "Rilievi da decidere: nessuno."
    assert_equal before, Decision.count
    assert_empty Teacher::TestReview.new(@subject).open_finding_list
  end

  test "a teacher decision on a minor finding wins over the opinions" do
    f = finding!(severity: "minor")
    assess_both!(f, "author_right")
    decide("/teacher/findings/#{f.id}/disposition", { disposition: "fix_requested", reason_it: "No, va sistemato." })
    assert_response :success
    page SKILL_PAGE
    assert_select "#finding-#{f.id}[data-disposition=fix_requested] .closure", 0
    assert_select "#finding-#{f.id} .decided", /correzione/
  end

  test "opinions never change the review gate or the approval gate" do
    f = finding!
    gate = -> { [ Review::Gate.check(@revision).to_h, Approval::BlueprintGate.check(@blueprint).to_h ] }
    before = gate.call
    assess_both!(f, "author_right")
    assert_equal before, gate.call
    assert_nil f.reload.disposition
  end
end
