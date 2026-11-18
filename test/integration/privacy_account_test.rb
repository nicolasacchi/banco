require "test_helper"
require_relative "../support/multi_user"
require_relative "../support/student_ui_rows"

# D-357: the privacy notice (GET /privacy) and the account page (GET /account) for the student (student layout), the teacher and a
# guest; the operator's own words from the environment with neutral defaults; the portal's numbers from config/banco/account.yml;
# the web listener only.
class PrivacyAccountTest < ActionDispatch::IntegrationTest
  include MultiUser
  include StudentUiRows

  PRIVACY_ENV = %w[BANCO_PRIVACY_CONTROLLER_IT BANCO_PRIVACY_CONTACT BANCO_PRIVACY_HOSTING_IT BANCO_PRIVACY_AI_PROVIDER
                   BANCO_PRIVACY_RETENTION_IT BANCO_AUTH_URL].freeze

  setup do
    @saved_privacy_env = ENV.to_h.slice(*PRIVACY_ENV)
    PRIVACY_ENV.each { |k| ENV.delete(k) }
    build_ui_subject
  end

  teardown { PRIVACY_ENV.each { |k| @saved_privacy_env.key?(k) ? ENV[k] = @saved_privacy_env[k] : ENV.delete(k) } }

  def page(headers, path) = on(:web, path, headers: headers, remote_addr: EDGE)

  # ---- who gets the pages ---------------------------------------------------------------------------

  test "the student reads both pages in the student's layout, with the menu link and the current page marked" do
    { "/privacy" => [ "privacy", "Privacy", 11 ], "/account" => [ "account", "Account e password", 7 ] }.each do |path, (key, label, sections)|
      page(OFFICIAL, path)
      assert_response :success, path
      assert_select "body.student"
      assert_select "body.teacher", 0
      assert_select "nav.student-menu a#menu-#{key}[href='#{path}'][aria-current=page]", label
      assert_select "#student-menu a[aria-current=page]", 1
      assert_select "main.page section.info-section", sections
      assert_select "h1", label.start_with?("Privacy") ? "Privacy: come usiamo i tuoi dati" : "Account e password"
    end
    page(OFFICIAL, "/privacy")
    assert_select "#privacy-account-link a[href='/account']"
    page(OFFICIAL, "/account")
    assert_select "#account-privacy-link a[href='/privacy']"
  end

  test "the other student pages carry both links in the menu, and Impostazioni has one line to them" do
    page(OFFICIAL, "/today")
    assert_select "nav.student-menu a#menu-account[href='/account']", "Account e password"
    assert_select "nav.student-menu a#menu-privacy[href='/privacy']", "Privacy"
    page(OFFICIAL, "/settings")
    assert_select "#settings-info-links a[href='/account']", "Account e password"
    assert_select "#settings-info-links a[href='/privacy']", "Privacy"
    assert_select "form#preferences"
  end

  test "the teacher and a guest read both pages in the teacher's layout, privacy is in the teacher's menu, and they get no student cookie" do
    [ TEACHER, GUEST ].each do |who|
      page(who, "/privacy")
      assert_response :success, who["Remote-User"]
      assert_select "body.teacher"
      assert_select "nav#teacher-menu a#menu-privacy[href='/privacy'][aria-current=page]", "Privacy"
      assert_select "nav.student-menu", 0
      assert_select "section.info-section", 11
      assert_not_includes response.headers["Set-Cookie"].to_s, DecisionRecorder::DEVICE_COOKIE, "a teacher's browser must not get the student's device cookie"
      page(who, "/account")
      assert_response :success
      assert_select "body.teacher"
      assert_select "section.info-section", 7
      assert_not_includes response.headers["Set-Cookie"].to_s, DecisionRecorder::DEVICE_COOKIE
    end
    page(TEACHER, "/teacher")
    assert_select "nav#teacher-menu a#menu-privacy[href='/privacy']:not([aria-current])"
  end

  test "the student's device cookie is still set on these pages, and a trial student reads them without it" do
    page(OFFICIAL, "/privacy")
    assert_includes response.headers["Set-Cookie"].to_s, DecisionRecorder::DEVICE_COOKIE
    page(TRIAL, "/account")
    assert_response :success
    assert_not_includes response.headers["Set-Cookie"].to_s, DecisionRecorder::DEVICE_COOKIE
  end

  test "nobody signed in and a login the operator did not configure get a refusal" do
    [ {}, UNMAPPED, { "Remote-User" => "stranger", "Remote-Groups" => "" } ].each do |who|
      %w[/privacy /account].each do |path|
        page(who, path)
        assert_response :forbidden, "#{who} #{path}"
        assert_select "main#privacy-page", 0
        assert_select "main#account-page", 0
      end
    end
  end

  test "the pages exist on the web listener only" do
    %w[/privacy /account].each do |path|
      %i[api harness view].each do |listener|
        on(listener, path, headers: OFFICIAL, remote_addr: EDGE)
        assert_response :not_found, "#{listener} #{path}"
        on(listener, path, headers: TEACHER, remote_addr: EDGE)
        assert_response :not_found, "#{listener} #{path}"
      end
    end
    routes = Rails.application.routes.routes.select { |r| %w[/privacy /account].include?(r.path.spec.to_s.sub("(.:format)", "")) }
    assert_equal 2, routes.size
    assert(routes.all? { |r| r.verb == "GET" })
  end

  # ---- the operator's values -------------------------------------------------------------------------

  test "without the variables the neutral defaults are in the notice" do
    page(OFFICIAL, "/privacy")
    assert_select "#privacy-controller", /Il titolare del trattamento è il docente che gestisce banco\./
    assert_select "#privacy-controller", /scrivi un commento da qualsiasi pagina/
    assert_select "#privacy-where", /I dati stanno su un server gestito dal docente\./
    assert_select "#privacy-who", /Il fornitore è Anthropic \(Claude\)\./
    assert_select "#privacy-retention", /I dati restano per la durata del percorso di preparazione all'esame; alla fine, o prima su richiesta, i dati vengono cancellati\./
    assert_select "#privacy-rights", /Per esercitare un diritto: scrivi un commento da qualsiasi pagina\./
  end

  test "the variables replace the defaults, escaped" do
    ENV["BANCO_PRIVACY_CONTROLLER_IT"] = "Prof. Verdi <b>"
    ENV["BANCO_PRIVACY_CONTACT"] = "scrivi a privacy@example.test"
    ENV["BANCO_PRIVACY_HOSTING_IT"] = "il server della scuola"
    ENV["BANCO_PRIVACY_AI_PROVIDER"] = "Fornitore Esempio"
    ENV["BANCO_PRIVACY_RETENTION_IT"] = "fino al 30 giugno"
    page(TEACHER, "/privacy")
    assert_select "#privacy-controller", /Il titolare del trattamento è Prof\. Verdi <b>\./
    assert_select "#privacy-controller b", 0
    assert_select "#privacy-controller", /Per mettersi in contatto con il titolare: scrivi a privacy@example\.test\./
    assert_select "#privacy-where", /I dati stanno su il server della scuola\./
    assert_select "#privacy-who", /Il fornitore è Fornitore Esempio\./
    assert_select "#privacy-retention", /I dati restano fino al 30 giugno\./
    assert_select "#privacy-rights", /Per esercitare un diritto: scrivi a privacy@example\.test\./
    assert_no_match(/Anthropic|il docente che gestisce banco/, response.body)
  end

  test "a blank variable is the default" do
    ENV["BANCO_PRIVACY_CONTROLLER_IT"] = "   "
    ENV["BANCO_PRIVACY_AI_PROVIDER"] = ""
    page(OFFICIAL, "/privacy")
    assert_select "#privacy-controller", /il docente che gestisce banco/
    assert_select "#privacy-who", /Anthropic \(Claude\)/
  end

  test "the notice says what the data are, what is not done, the Garante and the cookies" do
    page(OFFICIAL, "/privacy")
    assert_select "#privacy-intro", /articolo 13/
    assert_select ".page-header .page-sub", "Versione del 18 novembre 2026"
    assert_select "#privacy-basis", /consenso/
    assert_select "#privacy-data li", 8
    assert_select "#privacy-data", /nome utente/
    assert_select "#privacy-data", /indirizzo di rete \(IP\)/
    assert_select "#privacy-not_done", /Nessuna pubblicità/
    assert_select "#privacy-not_done", /Nessun carattere \(font\)/
    assert_select "#privacy-not_done", /Nessuna chat/
    assert_select "#privacy-who", /sola lettura/
    assert_select "#privacy-who", /non vedono mai i dati/
    assert_select "#privacy-append_only", /si cancellano tutte le righe insieme/
    assert_select "#privacy-rights li", 6
    assert_select "a#garante-link[href='https://www.garanteprivacy.it']"
    assert_select "#privacy-cookies li", 4
    assert_select "script[src*='http'], link[href^='http'], link[href^='//']", 0
  end

  # ---- the account page -------------------------------------------------------------------------------

  test "the account page tells the portal's numbers, which come from config/banco/account.yml" do
    page(OFFICIAL, "/account")
    assert_select "#account-session", /al massimo 12 ore/
    assert_select "#account-session", /Dopo 1 ora senza usare banco/
    assert_select "#account-session", /«Ricordami», resti dentro fino a 1 mese/
    assert_select "#account-lockout", /5 volte in 2 minuti, l'accesso si blocca per 1 ora/
    assert_select "#account-how", /banco non ha password/
    assert_select "#account-how", /soltanto il tuo nome utente/
    assert_select "#account-login", /basta questo passaggio/
    assert_select "#account-login", { text: /secondo passaggio/, count: 0 }
    assert_select "#account-reset ol li", 5
    assert_select "#account-reset", /Reset password/
    assert_select "#account-reset", /scrivi un commento/
    assert_select "#account-care", /Non condividere mai la tua password/
    assert_select "#portal-link", 0
    assert_select "#portal-address", /nome utente e password/
  end

  test "changing the numbers in the file changes the page" do
    settings = Privacy::Portal.settings.merge("session_hours" => 8, "lockout" => { "wrong_passwords" => 3, "within_minutes" => 1, "ban_hours" => 2 })
    Privacy::Portal.stub(:settings, settings) do
      page(OFFICIAL, "/account")
    end
    assert_select "#account-session", /al massimo 8 ore/
    assert_select "#account-lockout", /3 volte in 1 minuto, l'accesso si blocca per 2 ore/
  end

  test "the portal's address and the logout link show when set, and only an http address counts" do
    ENV["BANCO_AUTH_URL"] = "https://auth.example.test"
    ENV["BANCO_LOGOUT_URL"] = "https://auth.example.test/logout"
    page(OFFICIAL, "/account")
    assert_select "a#portal-link[href='https://auth.example.test']"
    assert_select "a#portal-reset-link[href='https://auth.example.test']"
    assert_select "a#account-logout-link[href='https://auth.example.test/logout']", "Esci"
    ENV["BANCO_AUTH_URL"] = "javascript:alert(1)"
    page(TEACHER, "/account")
    assert_select "a#portal-link", 0
    assert_select "a[href^='javascript']", 0
  end

  test "the numbers file has every key the page reads, and the file says it mirrors the portal" do
    raw = Rails.root.join(Privacy::Portal::PATH).read
    assert_match(/MIRROR the portal/, raw)
    settings = Privacy::Portal.settings
    assert_equal Privacy::Portal::KEYS.sort, settings.keys.reject { |k| k == "lockout" }.sort
    assert_equal Privacy::Portal::LOCKOUT_KEYS.sort, settings.fetch("lockout").keys.sort
    assert(settings.values.flat_map { |v| v.is_a?(Hash) ? v.values : [ v ] }.all? { |n| n.is_a?(Integer) && n.positive? })
  end

  # ---- «scrivi un commento da qualsiasi pagina» ------------------------------------------------------------

  test "a comment can be written on the privacy and the account pages, and every page kind has its words" do
    student = Student.find_by!(key: "student")
    { "/privacy" => "privacy", "/account" => "account" }.each do |path, kind|
      assert_equal kind, Comments::Pages.parse(path).kind
      params = ActionController::Parameters.new(client_comment_id: "c-#{SecureRandom.hex(8)}", reason: "other", text_it: "Non mi arriva l'email.", page_path: path)
      result = Comments::Intake.call(student: student, course_view: Course::StudentView.new(student), params: params)
      assert_equal :recorded, result.status, result.error.to_s
      assert_equal [ kind, path ], [ result.comment.page_kind, result.comment.page_path ]
    end
    assert_nil Comments::Pages.parse("/privacy/x")
    Comment::PAGE_KINDS.each do |kind|
      assert I18n.exists?("comments.place.#{kind}", :it), kind
      assert I18n.exists?("teacher.comments.page.#{kind}", :it), kind
    end
    page(OFFICIAL, "/privacy")
    assert_select "[data-controller~=comment], #comment-open-menu"
  end

  # ---- the English text ---------------------------------------------------------------------------------

  test "the English file has the same keys as the Italian one and the units and the defaults read in English" do
    paths = ->(node, prefix = "") { node.is_a?(Hash) ? node.flat_map { |k, v| paths.(v, "#{prefix}.#{k}") } : [ prefix ] }
    it = YAML.safe_load_file(Rails.root.join("config/locales/privacy.it.yml")).fetch("it")
    en = YAML.safe_load_file(Rails.root.join("config/locales/privacy.en.yml")).fetch("en")
    assert_equal paths.(it).sort, paths.(en).sort
    I18n.with_locale(:en) do
      assert_equal "12 hours", Privacy::Portal.phrases[:session]
      assert_equal "1 month", Privacy::Portal.phrases[:remember]
      assert_equal "Privacy: how we use your data", I18n.t("privacy.title")
      assert_equal "the teacher who runs banco", Privacy::Notice.values[:controller]
    end
  end
end
