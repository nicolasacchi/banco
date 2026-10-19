require "test_helper"
require_relative "../support/validation_servers"
require_relative "../support/chrome_helper"
require_relative "../support/lesson_render_world"

# The render check draws every state of a card the student can reach (D-311): every exercise of «Prova tu» (the pager shows one
# at a time, and the check once drew only the first), what sits behind a reveal, a mistake and a "more" (open as in print), the
# closed disclosures opened (a <details>, the hidden text of a listening check, a glossary bubble), the oral's own form; and a
# box's text held inside its box (a mirror piece with an icon role ran out of its box at 390 px). Small invented lessons, parsed
# from lesson/2 Markdown as an author writes them. Needs Chrome (BROWSER_PATH); skips without.
class LessonRenderStatesTest < ActiveSupport::TestCase
  include ChromeHelper
  include LessonRenderWorld

  PHONE = "390x844-cream"

  setup do
    require_chrome!
    @shots_dir = Dir.mktmpdir("lesson-shots")
    ENV["BANCO_LESSON_SHOTS_DIR"] = @shots_dir
  end

  teardown do
    ENV.delete("BANCO_LESSON_SHOTS_DIR")
    FileUtils.rm_rf(@shots_dir)
  end

  def front(subject, key)
    <<~MD
      ---
      schema: banco.lesson/2
      key: ripasso.#{subject}.#{key}
      kind: ripasso
      subject: #{subject}
      title_it: "Prova degli stati di una scheda"
      goals_it:
        - "**Vedere** ogni esercizio"
        - "**Aprire** ogni parte chiusa"
      skills: [#{subject}.#{key}]
      refs:
        - {source: prima-2025-26, line: 21, fragment: "una prova", role: taught_in}
      scope: studied
      minutes: 20
      calculator: false
      why_it: "Ogni parte della scheda si legge anche sul telefono. Il contenuto è inventato."
      ---
    MD
  end

  def render_md(subject, md)
    findings = Validation::Findings.new
    parsed = Lessons::Parser2.call(front(subject, "render-states-#{SecureRandom.hex(2)}") + "\n" + md, findings, allow_reserved: true)
    assert parsed&.body, "the lesson does not parse: #{findings.map(&:message).first(3)}"
    revision = store_lesson2!(parsed.body)
    Validation::LessonRenderCheck.new(revision).call
    LessonRender.where(lesson_revision_id: revision.id).order(:id).last
  end

  def dump(row)
    row.result["errors"].map { |e| "#{e['code']} card #{e['card']} #{e['state'] || '-'} #{e['viewport']} #{e['where']}: #{e['message']}" }.join("\n")
  end

  # A word no line can break: wider than a phone's card, narrower than a desktop's.
  def long(word) = word + ("o" * (44 - word.size))

  def number_line_yaml
    marks = (-5..5).map { |i| "      - {at: '#{i}', kind: dot, label_it: \"una etichetta davvero molto lunga #{i}\"}" }
    <<~YAML.chomp
      diagram:
          type: number_line
          alt_it: "Retta dei numeri da meno cinque a cinque con molte etichette lunghe."
          min: '-5'
          max: '5'
          step: '1'
          labels: all
          marks:
      #{marks.join("\n")}
    YAML
  end

  test "every exercise of Prova tu is drawn and measured in turn, and pictured at 390 px" do
    md = <<~MD
      ## Prova tu {try}

      ::: try
      intro_it: "Quattro esercizi."
      exercises:
        - text_it: "Primo esercizio: leggi la frase e scrivi la risposta sul quaderno."
          solution_it: "Una risposta."
        - text_it: "Secondo esercizio: guarda la retta."
          #{number_line_yaml.gsub("\n", "\n    ")}
          solution_it: "Una risposta."
        - text_it: "Terzo esercizio: costruisci la frase."
          check:
            component: tiles
            prompt_it: "Metti in fila le parole."
            tiles:
              - {id: a, text_en: "I"}
              - {id: b, text_en: "#{long('Supercalifragilistic')}"}
              - {id: c, text_en: "today"}
            answer: [a, b, c]
          solution_it: "Una risposta."
        - text_it: "Quarto esercizio: un esercizio senza niente di speciale."
          solution_it: "Una risposta."
      :::
    MD
    row = render_md("english", md)
    errors = row.result["errors"]
    try_card = 1
    # the first exercise is the card as drawn, and it is clean; the second draws its number line, the third its tiles
    assert_empty errors.select { |e| e["state"].nil? && e["card"] == try_card }, dump(row)
    assert errors.any? { |e| e["state"] == "ex2" && e["code"] == "E-DIAGRAM-LAYOUT" && e["viewport"] == PHONE }, dump(row)
    assert errors.any? { |e| e["state"] == "ex3" && e["code"] == "E-LESSON-OVERFLOW" && e["viewport"] == PHONE && e["where"].to_s.include?("Le tessere") }, dump(row)
    assert_empty errors.select { |e| e["state"] == "ex4" }, dump(row)
    # the card at every viewport; each further exercise at the phone, and also wherever it found something
    shots = row.shots.select { |s| s["card"] == try_card }
    assert_equal 3, shots.count { |s| s["state"].nil? }
    assert_equal [ PHONE ], shots.select { |s| s["state"] == "ex4" }.map { |s| s["viewport"] }
    assert_includes shots.select { |s| s["state"] == "ex3" }.map { |s| s["viewport"] }, PHONE
    ex2 = shots.select { |s| s["state"] == "ex2" }.map { |s| s["viewport"] }
    assert_equal errors.select { |e| e["state"] == "ex2" }.map { |e| e["viewport"] }.uniq.sort, ex2.sort
    assert row.result["timings"].any? { |t| t["state"] == "ex3" && t["viewport"] == PHONE }
  end

  test "what sits behind a reveal, a mistake and a more is measured, and a closed details and a listening text are opened" do
    md = <<~MD
      ## Pensaci, poi gira {idea icon=lightbulb}

      ::: reveal
      prompt_it: "Che cosa c'è dietro?"
      answer_it: "#{long('Rivelato')}"
      :::

      ## Errori da evitare {mistakes}

      ::: mistake
      group_it: "Parole"
      wrong_it: "Una frase sbagliata."
      right_it: "#{long('Giratoo')}"
      why_it: "Perché sì."
      code: english_demo_wrong
      :::

      ## Ancora una cosa {idea icon=lightbulb}

      Una frase della scheda.

      :::: more "Un dubbio"
      #{long('Approfondito')}
      ::::

      ## Le parole della legge {idea icon=landmark}

      ::: source
      kind: legal
      title_it: "Codice di prova, art. 1"
      ref: codice-di-prova
      parts:
        - text_it: "Il venditore consegna la merce nel luogo e nel giorno indicati nel contratto."
      guide:
        - {span_it: "Il venditore", note_it: "#{long('Guidato')}"}
      :::

      ## Ascolta e rispondi {idea icon=lightbulb}

      ::: check choice
      prompt_it: "Che cosa dice la frase?"
      listen: {text_en: "#{long('Listened')}"}
      options:
        - {id: a, text_it: "Una cosa"}
        - {id: b, text_it: "Un'altra cosa"}
      answer: a
      :::
    MD
    row = render_md("english", md)
    errors = row.result["errors"].select { |e| e["code"] == "E-LESSON-OVERFLOW" && e["viewport"] == PHONE }
    found = ->(card, marker) { errors.find { |e| e["card"] == card && e["where"].to_s.include?(marker) } }
    # open as in print: the card as drawn already shows them
    { 1 => "Rivelato", 2 => "Giratoo", 3 => "Approfondito" }.each do |card, marker|
      error = found.call(card, marker)
      assert error, "card #{card} (#{marker}):\n#{dump(row)}"
      assert_nil error["state"], dump(row)
    end
    # a closed <details>: Chrome lays out its content when asked (content-visibility), so the card as drawn measures it already;
    # the open state pictures it
    assert found.call(4, "Guidato"), dump(row)
    assert row.result["timings"].any? { |t| t["card"] == 4 && t["state"] == "open" }, "the source's guide is opened"
    # the text of a listening check is hidden (display: none) until "Mostra il testo": found only with the card open
    assert_empty errors.select { |e| e["card"] == 5 && e["state"].nil? }, dump(row)
    assert errors.any? { |e| e["card"] == 5 && e["state"] == "open" }, dump(row)
    # an open state is pictured where it found something, and only there
    open_shots = row.shots.select { |s| s["state"] == "open" }
    assert_equal row.result["errors"].select { |e| e["state"] == "open" }.map { |e| [ e["card"], e["viewport"] ] }.uniq.sort, open_shots.map { |s| [ s["card"], s["viewport"] ] }.sort
  end

  test "a glossary bubble opened over its paragraph is not an overflow, and the card stays clean in every state" do
    md = <<~MD
      ## Una parola nuova {idea icon=lightbulb}

      Una frase lunga che porta la parola in fondo alla riga, perché la bolla si apra vicino al bordo della scheda: [[g:subordinata]].

      Un'altra frase, per avere un paragrafo dopo la parola.
    MD
    findings = Validation::Findings.new
    parsed = Lessons::Parser2.call(front("english", "render-gloss") + "\n" + md, findings, allow_reserved: true)
    body = parsed.body.merge("glossary" => [ { "term_it" => "subordinata", "def_it" => "Una parte della frase che non sta in piedi da sola, e ha bisogno di un'altra parte." } ])
    revision = store_lesson2!(body)
    Validation::LessonRenderCheck.new(revision).call
    row = LessonRender.where(lesson_revision_id: revision.id).order(:id).last
    assert_equal "passed", row.status, dump(row)
    assert row.result["timings"].any? { |t| t["state"] == "open" && t["card"] == 1 }, "the card's open state was looked at"
  end

  def mirror_md(piece_it, piece_es)
    <<~MD
      ## Lo specchio {idea icon=languages}

      Come in italiano.

      ::: diagram mirror
      alt_it: "Italiano sopra, spagnolo sotto: ci diventa nos, e la desinenza del verbo cambia."
      rows:
        - pieces_it: ['Ci', '#{piece_it}']
          pieces_es: ['Nos', '#{piece_es}']
          links: [[0, 0, shift], [1, 1, shift]]
          notes:
            - {side: es, piece: 0, note_it: "ci diventa nos"}
            - {side: es, piece: 1, note_it: "la desinenza cambia"}
          roles:
            - {side: it, piece: 1, role: verb}
            - {side: es, piece: 1, role: verb}
      :::
    MD
  end

  test "a mirror piece whose text runs out of its box at 390 px is E-DIAGRAM-LAYOUT; short pieces with the same roles pass" do
    # a word wider than the whole box (a word never wraps): D-310 puts the two pieces of a pair one under the other and a word that wide
    # still crosses its box (and leaves the figure: the author shortens the piece)
    row = render_md("spanish", mirror_md("svegliavamoooooooooooooooooooooooooooooo", "vemos"))
    mine = row.result["errors"].select { |e| e["message"].include?("svegliavamo") }
    assert mine.any? { |e| e["code"] == "E-DIAGRAM-LAYOUT" && e["viewport"] == PHONE && e["message"].match?(/touches or crosses the border of its box/) }, dump(row)
    row = render_md("spanish", mirror_md("vediamo", "vemos"))
    assert_empty row.result["errors"].select { |e| e["code"] == "E-DIAGRAM-LAYOUT" }, dump(row)
    # a long word the old list let cross its box now fits: the icon above the text, or the pair one under the other (D-310, D-311)
    row = render_md("spanish", mirror_md("svegliavamo", "vemos"))
    assert_empty row.result["errors"].select { |e| e["code"] == "E-DIAGRAM-LAYOUT" }, dump(row)
  end

  test "the oral is drawn as the student answers it (the outline's form), not as the printed list" do
    md = <<~MD
      ## Dillo tu {idea icon=lightbulb}

      ::: oral
      question_it: "Spiega come si arriva dal lordo al totale di una fattura."
      outline:
        - {id: o1, text_it: "Parto dal lordo della merce"}
        - {id: o2, text_it: "Tolgo gli sconti e ho il netto"}
        - {id: o3, text_it: "Aggiungo le spese e calcolo l'IVA"}
      answer: [o1, o2, o3]
      connectives: ["prima", "poi", "infine"]
      terms: ["lordo", "netto"]
      model_it: "Parto dal lordo. Poi tolgo gli sconti e ho il netto. Infine aggiungo le spese e calcolo l'IVA."
      :::
    MD
    findings = Validation::Findings.new
    body = Lessons::Parser2.call(front("business", "render-oral") + "\n" + md, findings, allow_reserved: true).body
    revision = store_lesson2!(body)
    token = Validation::Harness.issue("lrev", revision.id)
    drawn = Validation::ChromeRunner.session do |session|
      session.context do |ctx|
        page = ctx.create_page
        page.command("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: false)
        page.go_to(Validation::Harness.lesson_page_url(token))
        page.evaluate_async("window.bancoLessonRender.ready.then(arguments[0])", 30)
        page.evaluate_async("window.bancoLessonRender.inspect(1).then(arguments[0])", 10)
        page.evaluate("[!!document.querySelector('#scheda-1 .oral-form'), !!document.querySelector('#scheda-1 .oral-outline-plain'), document.querySelectorAll('#scheda-1 .oral-form li, #scheda-1 .oral-form [role=listitem]').length]")
      end
    end
    form, plain, items = drawn
    assert form, "the oral's form is drawn"
    assert_not plain, "the printed outline is not"
    assert_operator items, :>=, 3
  end
end
