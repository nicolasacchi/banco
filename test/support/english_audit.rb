require "set"

# The audit of the student's pages with the interface in English (D-364), for the system tests that walk them in Chrome. A page is looked at
# the way the student sees it: its visible words, its labels (aria-label, placeholder, title, alt), the options of its selects and its title.
# `check_page(where)` adds to `@findings` (it never stops the walk, so one run lists everything it found):
#
# - `translation missing`, an `%{interpolation}` left in a text, `undefined`, `[object Object]`;
# - Italian chrome: a string of the Italian locale files of the student's interface that shows on a page while English is on (the lesson and the
#   exercise content, the figures' vocabulary and the teacher's words are not in those files; the strings that the English files also hold are left out);
# - the JavaScript errors, console errors and CSP violations the page reported;
# - on a phone (390 px): a button, a pill, a label, a heading whose text is wider than its box, and any element that leaves the window; on every
#   window: a page that scrolls sideways;
# - `<html lang>` is not `en`.
#
# The test includes this module in an ApplicationSystemTestCase; `@phone` says that the window is a phone's.
module EnglishAudit
  LOCALES = Rails.root.join("config/locales")

  # The Italian file of the student's interface => its English twin (the pairs of test/lib/locale_parity_test.rb, and the subjects' names).
  TWINS = {
    "it.yml" => "en.yml", "course.it.yml" => "course.en.yml", "comments.it.yml" => "comments.en.yml", "search.it.yml" => "search.en.yml",
    "lesson_pages.it.yml" => "lesson_pages.en.yml", "lesson_docs.it.yml" => "lesson_docs.en.yml", "lesson.it.yml" => "lesson.en.yml", "lesson_text.it.yml" => "lesson_text.en.yml",
    "lesson_checks.it.yml" => "lesson_checks.en.yml", "grading.it.yml" => "grading.en.yml", "privacy.it.yml" => "privacy.en.yml",
    "subjects.it.yml" => "subjects.en.yml", "schemas.it.yml" => "schemas.en.yml"
  }.freeze

  # Italian subtrees that are not chrome: the refusal pages (no student language), the teacher's words, the samples that each voice says in its language.
  NOT_CHROME = %w[errors. teacher. activity. lesson2.voices.sentences.].freeze

  PROBLEM_TEXT = /translation[ _]missing|%\{|\bundefined\b|\[object Object\]/

  WATCH = <<~JS.freeze
    (() => {
      window.__problems = [];
      const note = (kind, text) => window.__problems.push(kind + ": " + text);
      const consoleError = console.error.bind(console);
      console.error = (...args) => { note("console.error", args.map(String).join(" ")); consoleError(...args); };
      window.addEventListener("error", (e) => note("error", (e.message || "") + " " + (e.filename || "")));
      window.addEventListener("unhandledrejection", (e) => note("unhandledrejection", String(e.reason && e.reason.stack || e.reason)));
      document.addEventListener("securitypolicyviolation", (e) => note("csp", e.violatedDirective + " " + e.blockedURI));
    })();
  JS

  # What the page holds that is chrome, and where it does not fit. Parts of a page that are the lesson's or the exercise's own words (a card's
  # title, a callout's title, the lesson map's titles, a search hit's title and snippet, a comment's own text) are left out of the words.
  AUDIT = <<~JS.freeze
    (() => {
      const CONTENT = ".card-head, .l2-titles, .map-text, .cover-cards, .block-callout, .block-diagram, figure, [role=img], [class*='dg-'], [data-lesson-markup], .markup, .search-hit .search-title, .search-snippet, .search-definition p, .cm-text, .cm-quote-text, .voice-name, svg, .katex, math-field, script, style, template"
      const visible = (el) => (el.checkVisibility ? el.checkVisibility({ checkVisibilityCSS: true }) : el.offsetParent !== null)
      const strings = new Set()
      const loose = new Set()
      const clean = (text) => (text || "").replace(/\\s+/g, " ").trim()
      const add = (text, outsideCards) => {
        const s = clean(text)
        if (!s || s.length > 400) return
        strings.add(s)
        if (outsideCards) loose.add(s)
      }
      add(document.title, true)
      // the whole text of an element that is chrome through and through: a control, a label, a heading with nothing of the content inside it
      const CHROME = /^(SUMMARY|BUTTON|A|LABEL|LEGEND|H1|H2|H3|H4|TH|OPTION)$/
      for (const el of document.body.querySelectorAll("*")) {
        if (el.closest(CONTENT) || !visible(el)) continue
        const outsideCards = !el.closest(".l2-card, .card-body")
        let own = ""
        for (const node of el.childNodes) if (node.nodeType === 3) own += node.nodeValue
        add(own, outsideCards)
        if (CHROME.test(el.tagName) && el.children.length > 0 && !el.querySelector(CONTENT)) {
          const whole = clean(el.innerText)
          if (whole.length <= 120) add(whole, outsideCards)
        }
        for (const name of ["aria-label", "placeholder", "title", "alt"]) add(el.getAttribute(name), outsideCards)
      }
      for (const select of document.querySelectorAll("select")) if (visible(select)) for (const option of select.options) add(option.textContent, true)

      const describe = (el) => `${el.tagName.toLowerCase()}${el.id ? "#" + el.id : ""}${el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\\s+/).slice(0, 2).join(".") : ""} «${(el.innerText || el.textContent || "").replace(/\\s+/g, " ").trim().slice(0, 40)}»`
      const vw = window.innerWidth
      const root = document.documentElement
      const wholePage = []
      if (root.scrollWidth > vw + 1) wholePage.push(`the page scrolls sideways (${root.scrollWidth} px in a ${vw} px window)`)
      const scrolls = (el) => {
        for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) {
          const o = getComputedStyle(p).overflowX
          if (o === "auto" || o === "scroll") return true
        }
        return false
      }
      const SKIP = "svg, .katex, math-field, .table-wrap, .dg-stage, figure.dg, .code-box, .code-screen, pre, .sr-only, dialog:not([open])"
      const BOXES = "button, a.button, summary, legend, label, .pill, .tag, h1, h2, h3, .topbar-title, .subject-name, .topic-title, .exercise-link, .cm-tab, .row-stretch, .option"
      const boxes = []
      for (const el of document.querySelectorAll(BOXES)) {
        if (el.closest(SKIP) || !visible(el)) continue
        const r = el.getBoundingClientRect()
        if (r.width < 1 || r.height < 1) continue
        if (el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1) boxes.push(`${describe(el)}: the text is wider than its box (${el.scrollWidth} px in ${el.clientWidth} px)`)
        if (!scrolls(el) && (r.right > vw + 1 || r.left < -1)) boxes.push(`${describe(el)}: it is outside the window (${Math.round(r.left)} to ${Math.round(r.right)} px of ${vw})`)
      }
      return { strings: [...strings], loose: [...loose], text: document.body.innerText, lang: root.lang, whole_page: wholePage, boxes }
    })()
  JS

  def self.leaves(node, path = [], out = {})
    case node
    when Hash then node.each { |key, value| leaves(value, path + [ key.to_s ], out) }
    when Array then node.each_with_index { |value, index| leaves(value, path + [ index.to_s ], out) }
    else out[path.join(".")] = node
    end
    out
  end

  # { exact: { "Oggi" => key }, patterns: [[/\AEsercizio .+?\z/, key]], fragments: { "Una frase lunga" => key }, fragment_re: Regexp } of the Italian texts of the
  # student's interface that differ from their English twin. Made once.
  def self.italian
    @italian ||= begin
      english = Set.new
      pairs = []
      TWINS.each do |it_file, en_file|
        it = leaves(YAML.load_file(LOCALES.join(it_file)).fetch("it"))
        en = leaves(YAML.load_file(LOCALES.join(en_file)).fetch("en"))
        en.each_value { |value| english << value.to_s.gsub(/<[^>]+>/, "").squish if value.is_a?(String) }
        it.each do |key, value|
          next unless value.is_a?(String) && en[key].is_a?(String) && value != en[key]
          next if NOT_CHROME.any? { |prefix| key.start_with?(prefix) }

          pairs << [ key, value ]
        end
      end
      exact = {}
      patterns = []
      fragments = {}
      pairs.each do |key, value|
        plain = value.gsub(/<[^>]+>/, "").squish
        next if english.include?(plain) || plain.scan(/\p{L}/).size < 3

        pieces = value.split(/%\{\w+\}|<[^>]+>/).map(&:squish)
        pieces.select { |piece| piece.length >= 14 && !english.include?(piece) }.each { |piece| fragments[piece] ||= key }
        next if value.include?("<")

        if value.include?("%{")
          source = value.strip.split(/(%\{\w+\})/).map { |part| part.start_with?("%{") ? ".+?" : Regexp.escape(part.gsub(/\s+/, " ")) }.join # the spaces around a name stay: «%{count} ore» is not «more»
          patterns << [ Regexp.new("\\A#{source}\\z"), key ] if pieces.any? { |piece| piece.length >= 3 }
        else
          exact[plain] ||= key
        end
      end
      { exact: exact, patterns: patterns, fragments: fragments, fragment_re: fragments.empty? ? /(?!)/ : Regexp.union(fragments.keys.sort_by { |piece| -piece.length }) }
    end
  end

  # The English text of a key, never the Italian one by fallback, and an error when the key is missing.
  def en(key, **options) = I18n.t(key, **options, locale: :en, raise: true)

  # ---- the watch ----------------------------------------------------------------------------------------------------------------------------

  def audit_setup
    @findings = []
    @log_problems = []
    @phone = false
    @watch_id = page.driver.browser.page.command("Page.addScriptToEvaluateOnNewDocument", source: WATCH)["identifier"]
    page.driver.browser.page.on("Log.entryAdded") do |params|
      entry = params["entry"] || {}
      next unless %w[error warning].include?(entry["level"]) && entry["source"] != "deprecation" && entry["text"].to_s !~ /favicon/

      @log_problems << "log #{entry['level']}: #{entry['text']} #{entry['url']}"
    end
  end

  def audit_teardown
    page.driver.browser.page.command("Page.removeScriptToEvaluateOnNewDocument", identifier: @watch_id) if @watch_id
  rescue StandardError
    nil
  end

  def finding(where, text) = @findings << "#{where}: #{text}"

  # A part of the walk. What goes wrong inside it (a button that is not there, an assertion) is a finding, and the walk goes on with the next part.
  def section(name)
    yield
  rescue Minitest::Assertion, StandardError => e
    finding(name, "the walk stopped here: #{e.class}: #{e.message.lines.first(4).join.strip}")
  end

  def assert_no_findings
    assert_empty @findings, "the English walk found #{@findings.size} problem(s):\n#{@findings.map { |line| "  - #{line}" }.join("\n")}"
  end

  # ---- the page -----------------------------------------------------------------------------------------------------------------------------

  # strings: the whole texts of chrome elements (exact and with %{names}); loose: the ones outside a lesson card, where a long piece of an Italian text
  # is looked for too (inside a card the words are the lesson's, and only a whole text of the locale files is chrome).
  # The words of a lesson (every string of its body) are content, even when one is the same as a chrome string («Attenzione», «Prova tu», «primo membro»):
  # a test that opens a lesson tells the audit which one.
  def allow_content(body)
    @allowed ||= Set.new
    walk = lambda do |node|
      case node
      when String then @allowed << node.gsub(/\s+/, " ").strip
      when Hash then node.each_value(&walk)
      when Array then node.each(&walk)
      end
    end
    walk.call(body)
  end

  # The text without the words of the lesson (a chrome string can hold a card's title: «Card 8 of 10: Errori da evitare»); nil when nothing of it is left.
  def without_content(text)
    return text if @allowed.blank?

    @allowed_re ||= Regexp.union(@allowed.select { |word| word.length >= 4 }.sort_by { |word| -word.length })
    rest = text.gsub(@allowed_re, " ").squish
    return nil if rest.empty? || @allowed.include?(text)

    rest == text ? text : rest
  end

  def italian_leaks(strings, loose = [])
    index = EnglishAudit.italian
    strings = strings.map { |text| without_content(text) }.compact
    loose = loose.map { |text| without_content(text) }.compact
    found = strings.filter_map do |text|
      key = index[:exact][text] || index[:patterns].find { |pattern, _| pattern.match?(text) }&.last
      "«#{text.truncate(90)}» is the Italian of #{key}" if key
    end
    found += loose.filter_map do |text|
      next unless (match = index[:fragment_re].match(text))

      "«#{text.truncate(90)}» holds «#{match[0]}», the Italian of #{index[:fragments][match[0]]}"
    end
    found.uniq
  end

  def check_page(where)
    sleep 0.3 # the scripts that draw lists and dialogs have run
    report = page.evaluate_script(AUDIT)
    finding(where, "<html lang> is #{report['lang'].inspect}, not \"en\"") unless report["lang"] == "en"
    if (match = report["text"][PROBLEM_TEXT])
      finding(where, "the page shows #{match.inspect}: #{report['text'][/.{0,50}#{Regexp.escape(match)}.{0,50}/m].to_s.squish}")
    end
    italian_leaks(report["strings"], report["loose"]).each { |leak| finding(where, "Italian chrome: #{leak}") }
    report["whole_page"].each { |line| finding(where, "layout: #{line}") }
    report["boxes"].each { |line| finding(where, "layout: #{line}") } if @phone
    problems = @log_problems.dup + Array(page.evaluate_script("window.__problems || []"))
    @log_problems.clear
    page.execute_script("window.__problems = []")
    problems.uniq.each { |problem| finding(where, "the browser reported #{problem}") }
  rescue Ferrum::Error => e
    finding(where, "the page could not be audited: #{e.class}: #{e.message.lines.first.to_s.strip}")
  end

  def phone!
    @phone = true
    page.driver.resize(390, 844)
  end

  def desktop!
    @phone = false
    page.driver.resize(1280, 900)
  end

  def wait_until(seconds = 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    loop do
      value = yield
      return value if value

      flunk "not true within #{seconds} s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
  end
end
