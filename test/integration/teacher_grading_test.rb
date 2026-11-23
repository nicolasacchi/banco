require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/grading_review_world"

# D-368: «Contestazioni», the teacher's read-only page of where the grader may be wrong: the exercises with their tries, not-right rate and manual
# corrections, the ones «da controllare», and the not-right tries with their signals. The teacher reads what the student typed; a guest and a view link
# never do; the student and nobody else do not read it; nothing is written.
class TeacherGradingTest < ActionDispatch::IntegrationTest
  include MultiUser
  include GradingReviewWorld

  VIEW_ENV = { "BANCO_VIEW_LINKS_ENABLED" => "1", "BANCO_VIEW_URL" => "https://api.banco.scc.im" }.freeze

  setup do
    @saved_view_env = ENV.to_h.slice(*VIEW_ENV.keys)
    VIEW_ENV.each { |k, v| ENV[k] = v }
    build_grading_review_world
  end

  teardown { VIEW_ENV.each_key { |k| @saved_view_env.key?(k) ? ENV[k] = @saved_view_env[k] : ENV.delete(k) } }

  def page(path = "/teacher/grading", headers: TEACHER) = on(:web, path, headers: headers, remote_addr: EDGE)

  # The exercises of the list, the flagged table first and then the closed fold of the others.
  def item_keys = css_select("#grading-items tbody tr, #grading-items-rest tbody tr").map { |tr| tr["data-item"] }

  def try_refs = css_select("#grading-tries tbody tr").map { |tr| tr["data-ref"] }

  test "the page lists the exercises, the flagged ones first, with their tries, not-right and corrections" do
    page
    assert_response :success
    assert_select "h1", "Contestazioni"
    assert_equal [ "diag-text-1", SENTENCE, WORD, "demo-item-2" ], item_keys
    assert_select "#grading-items tr[data-item=?][data-flagged=true]", WORD do
      assert_select "td[data-tries='5']"
      assert_select "td[data-not-right='5']", text: "5 (100%)"
      assert_select "td[data-manual='0']", text: "0 (0%)"
      assert_select ".pill", text: "Da controllare"
      assert_select ".hint", text: "più della metà non giusti"
    end
    assert_select "#grading-items tr[data-item=?][data-flagged=true]", SENTENCE do
      assert_select "td[data-not-right='3']", text: "3 (75%)"
      assert_select "td[data-manual='1']", text: "1 (25%)"
      assert_select ".hint", text: "corretto a mano"
    end
    assert_select "#grading-items tr[data-item=?]", "demo-item-2", 0 # not flagged: in the fold of the others
    assert_select "details#grading-items-others:not([open]) #grading-items-rest tr[data-item=?][data-flagged=false]", "demo-item-2" do
      assert_select "td[data-tries='6']"
      assert_select ".pill", 0
    end
  end

  test "the totals line up with the review" do
    page
    { "tries" => "Tentativi: 17.", "not_right" => "Non giusti: 13.", "written" => "Risposte scritte non giuste: 10 su 11.", "manual" => "Correzioni a mano: 2.",
      "resends" => "Reinvii identici: 1.", "contested" => "«Per me va bene così»: 1.", "flagged" => "Esercizi da controllare: 3.",
      "superseded" => "Tentativi su revisioni vecchie, non letti: 1." }.each do |key, text|
      assert_select "#grading-totals li[data-total=?]", key, text: text
    end
  end

  test "the not-right tries that have a signal are listed with the signal in words and what the student typed" do
    page
    refs = try_refs
    assert_includes refs, "practice-#{@resolved_try.id}"
    assert_includes refs, "diagnosis-#{@diag_resolved.id}"
    assert_not_includes refs, "practice-#{@plain_try.id}", "no signal, no line"
    assert_not_includes refs, "practice-#{@right_try.id}"
    assert_select "#grading-try-practice-#{@near_try.id}[data-signals='near_text']" do
      assert_select "li[data-signal=near_text]", text: "a una lettera dalla chiave"
      assert_select "q[data-student-text]", text: "neighbourhod"
    end
    assert_select "#grading-try-practice-#{@sentence_try.id}" do
      assert_select "li[data-signal=full_sentence]", text: "frase intera con le parole della chiave"
      assert_select "q[data-student-text]", text: "My parents don't really eat meat"
    end
    assert_select "#grading-try-practice-#{@resolved_try.id}" do
      assert_select "li[data-signal=resolved_right]", text: "resa giusta dal docente"
      assert_select ".hint", text: "Corretto a mano: giusta"
    end
    assert_select "#grading-try-practice-#{@resend.id} li[data-signal=resend]", text: "reinvio identico"
    assert_select "#grading-try-practice-#{@contested_try.id} li[data-signal=contested]", text: "«Per me va bene così»"
    assert_select "#grading-try-practice-#{@commented_try.id} li[data-signal=comment]"
    assert_select "#grading-try-diagnosis-#{@diag_resolved.id} li[data-signal=full_sentence]"
  end

  test "the filters: a subject, a day; a bad value is left out, not an error" do
    Subject.create!(key: "english", name_it: "Inglese", position: 2) # a subject that exists and has no try
    page("/teacher/grading?subject=english")
    assert_response :success
    assert_select "#grading-empty"
    assert_select "#grading-items", 0
    assert_select "#grading-empty", text: "Nessun tentativo con questi filtri."
    assert_select "#grading-filters-clear"
    page("/teacher/grading?since=#{@base.to_date}&subject=math")
    assert_response :success
    assert_equal [ SENTENCE, WORD, "demo-item-2" ], item_keys, "the entry test's answers are of the day before"
    assert_select "#grading-since[value=?]", @base.to_date.iso8601
    page("/teacher/grading?since=#{@base.to_date + 1}")
    assert_select "#grading-empty"
    page("/teacher/grading?since=yesterday&subject=nope")
    assert_response :success
    assert_equal 4, item_keys.size
    assert_select "#grading-filters-clear", 0
  end

  test "another student: a trial student's page has none of the official student's tries" do
    page("/teacher/grading?student=prova-1")
    assert_response :success
    assert_select "#grading-empty"
    page("/teacher/grading?student=nobody-1")
    assert_response :not_found
  end

  # A matching the student answered with a row-to-pair map, sent twice (the second is a resend, so it has a signal), and a reading test answered per question.
  def make_structured_tries
    revision = make_revision("pair-1", SKILL, component: "matching", instances: 0)
    display = { left: [ { id: "l1", text: "cane" }, { id: "l2", text: "gatto" } ], right: [ { id: "r1", text: "abbaia" }, { id: "r2", text: "miagola" } ] }
    instance = ItemInstance.create!(item_revision: revision, seed: 1, display_json: JSON.generate(display), answer_json: JSON.generate("l1" => "r1", "l2" => "r2"),
                                    fingerprint: Digest::SHA256.hexdigest("pair-1-0"))
    at = @text_t + 9000
    serve = make_serve(@official, @topic_revision, instance, skill_key: SKILL, at: at)
    raw = JSON.generate("l1" => "r2", "l2" => "r1")
    @pair_tries = [ make_try(serve, try_number: 1, raw: raw, verdict: "wrong", at: at + 60), make_try(serve, try_number: 2, raw: raw, verdict: "wrong", at: at + 120) ]
  end

  test "the words of the page are Italian: the outcome, the hand correction and the subject's name, never a code or a key" do
    page
    assert_select "#grading-try-practice-#{@resolved_try.id} [data-outcome=?]", "unrecognised", text: "sbagliata"
    assert_select "#grading-try-diagnosis-#{@diag_resolved.id} [data-outcome=?]", "wrong", text: "sbagliata"
    assert_select "#grading-tries [data-outcome]" do |spans|
      spans.each { |span| assert_not_includes %w[wrong undetermined correct unrecognised], span.text.strip, "a raw code" }
    end
    assert_select "#grading-try-diagnosis-#{@diag_resolved.id} .hint", text: "Corretto a mano: giusta"
    names = css_select("#grading-items td[data-label=Materia], #grading-items-rest td[data-label=Materia]").map { |td| td.text.strip }.uniq
    assert_equal [ Subject.find_by!(key: "math").name_it ], names
    %w[undetermined near_miss contested typical_error].each { |code| assert I18n.exists?("teacher.grading.outcome.#{code}", :it), code }
    (Practice::AttemptLog::OUTCOMES + Grading::VERDICTS).each { |code| assert I18n.exists?("teacher.grading.outcome.#{code}", :it), "no words for #{code}" }
  end

  test "a structured answer reads as the words the student saw, as on the corrections page, not as JSON" do
    make_structured_tries
    page
    assert_select "#grading-try-practice-#{@pair_tries.last.id} q[data-student-text]", text: "cane – miagola; gatto – abbaia"
    assert_not_includes response.body, "&quot;l1&quot;"
    assert_not_includes response.body, '{"l1"'
  end

  test "the tries sit under their exercise: the flagged ones open, the others closed, each with its count" do
    make_structured_tries
    page
    assert_select "#grading-tries details.grading-group[data-item=?][data-flagged=true][open]", WORD
    assert_select "#grading-tries details.grading-group[data-item=?][data-flagged=false]:not([open])", "pair-1" do
      assert_select "summary", text: /1 tentativo con un segnale/ # the second send is the resend; the first has no signal
      assert_select "tr[data-ref]", 1
    end
    groups = css_select("#grading-tries details.grading-group").map { |d| d["data-flagged"] }
    assert_equal groups.sort.reverse, groups, "the flagged exercises come first"
    assert_equal css_select("#grading-tries tbody tr").size, css_select("#grading-tries tbody tr[data-ref]").size
  end

  test "the student picker keeps the subject and the day; the empty page says there is no try when no filter is set" do
    page("/teacher/grading?subject=math&since=#{@base.to_date}")
    link = css_select("#student-picker a[data-student=prova-1]").first
    assert_not_nil link
    query = Rack::Utils.parse_query(URI(link["href"]).query)
    assert_equal({ "subject" => "math", "since" => @base.to_date.iso8601, "student" => "prova-1" }, query)
    page("/teacher/grading?student=prova-1&subject=math")
    assert_select "#grading-empty", text: "Nessun tentativo con questi filtri."
    link = css_select("#student-picker a").first
    assert_equal({ "subject" => "math" }, Rack::Utils.parse_query(URI(link["href"]).query), "back to the official student: no student parameter")
    page("/teacher/grading?student=prova-1")
    assert_select "#grading-empty", text: "Nessun tentativo."
  end

  test "the menu has the entry and marks it on the page" do
    page("/teacher")
    assert_select "#teacher-menu a#menu-grading[href=?]", "/teacher/grading", text: "Contestazioni"
    page
    assert_select "#teacher-menu a#menu-grading[aria-current=page]"
    assert_select "#teacher-menu [aria-current]", 1
  end

  test "a guest reads the numbers and never the student's words; the student, an unmapped login and nobody do not read it" do
    page(headers: GUEST)
    assert_response :success
    assert_select "#read-only-notice"
    assert_equal 4, item_keys.size
    assert_select "[data-student-text]", 0
    assert_select "#grading-tries [data-hidden-text]", text: "testo visibile solo all'insegnante"
    [ "neighbourhod", "My parents don't really eat meat", "kitchen", "xyz", "banana", "1 mela", "Era giusta." ].each do |words|
      assert_not_includes response.body, words
    end

    page(headers: OFFICIAL)
    assert_response :forbidden
    assert_not_includes response.body, "neighbourhod"
    page(headers: UNMAPPED)
    assert_response :forbidden
    page(headers: {})
    assert_response :forbidden
  end

  test "a view link opens the page on the view listener without the student's words" do
    raw = ApiToken.issue!(role: "bot_read", label: "view grading", expires_at: 30.days.from_now)
    token = ApiToken.find_by!(public_id: Banco::TokenAuth::FORMAT.match(raw)[1])
    _, secret = ViewLinks.create!(token: token, path: "/teacher/grading?subject=math", minutes: 30)
    on(:view, "/v?view_token=#{secret}", remote_addr: EDGE)
    assert_response :see_other
    assert_equal "/teacher/grading?subject=math", URI(response.location).request_uri
    on(:view, "/teacher/grading?subject=math", remote_addr: EDGE)
    assert_response :success
    assert_equal 4, item_keys.size
    assert_select "[data-student-text]", 0
    assert_not_includes response.body, "neighbourhod"
    assert_no_difference [ "Decision.count", "PracticeAttempt.count" ] do
      on(:view, "/teacher/grading", method: :post, remote_addr: EDGE)
      assert_response :forbidden
    end
  end

  test "reading the page writes nothing" do
    assert_no_difference [ "AppEvent.count", "Decision.count", "PracticeAttempt.count", "PracticeContest.count", "Comment.count", "Student.count" ] do
      page
      page(headers: GUEST)
      page("/teacher/grading?student=prova-1")
    end
  end
end
