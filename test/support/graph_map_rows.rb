require_relative "student_ui_rows"

# A production-like skill graph (about 30 skills, five or six levels, composites, a deferred
# cross-subject edge, programme lines of the first and second year) for the map's tests and
# screenshots. The two skills of the UI subject that a test pins stay in it.
module GraphMapRows
  include StudentUiRows

  # key suffix => [name, scope, prerequisites, taught_in lines, needed_by seconda lines]
  SKILLS = {
    "number" => [ "Operazioni con i numeri interi", "studied", [], [ 1 ], [] ],
    "choice" => [ "Potenze e proprietà delle potenze", "studied", [ "number" ], [ 1 ], [ 1 ] ],
    "divisibility" => [ "Multipli, divisori e scomposizione in fattori primi", "studied", [ "number" ], [ 2 ], [] ],
    "mcm" => [ "Minimo comune multiplo e massimo comun divisore", "integration_studied", [ "divisibility" ], [ 2 ], [] ],
    "fractions" => [ "Frazioni e operazioni con le frazioni", "studied", [ "number", "mcm" ], [ 3 ], [ 2 ] ],
    "decimals" => [ "Numeri decimali e percentuali", "middle_school", [ "fractions" ], [], [] ],
    "proportions" => [ "Rapporti e proporzioni", "studied", [ "fractions" ], [ 4 ], [ 3 ] ],
    "rational" => [ "Numeri razionali sulla retta", "in_progress", [ "fractions", "decimals" ], [ 3 ], [] ],
    "monomials" => [ "Monomi e operazioni con i monomi", "studied", [ "choice" ], [ 5 ], [ 4 ] ],
    "polynomials" => [ "Polinomi: somma, differenza e prodotto", "studied", [ "monomials" ], [ 5 ], [ 4 ] ],
    "notable" => [ "Prodotti notevoli", "in_progress", [ "polynomials" ], [ 6 ], [ 5 ] ],
    "factoring" => [ "Scomposizione di polinomi", "in_progress", [ "notable", "mcm" ], [ 6 ], [ 5 ] ],
    "linear-eq" => [ "Equazioni di primo grado", "studied", [ "rational", "polynomials" ], [ 7 ], [ 6 ] ],
    "word-problems" => [ "Problemi che si risolvono con un'equazione", "integration_studied", [ "linear-eq", "proportions" ], [ 7 ], [] ],
    "inequalities" => [ "Disequazioni di primo grado", "not_in_prima", [ "linear-eq" ], [], [ 7 ] ],
    "fractional-eq" => [ "Equazioni con le frazioni algebriche", "not_in_prima", [ "linear-eq", "factoring" ], [], [ 8 ] ],
    "points-plane" => [ "Punti e distanze nel piano cartesiano", "studied", [ "rational" ], [ 8 ], [ 9 ] ],
    "lines" => [ "La retta: equazione e grafico", "studied", [ "points-plane", "linear-eq" ], [ 8 ], [ 9 ] ],
    "systems" => [ "Sistemi di due equazioni lineari", "in_progress", [ "lines" ], [ 9 ], [ 10 ] ],
    "geometry-basics" => [ "Enti geometrici fondamentali", "middle_school", [], [], [] ],
    "angles" => [ "Angoli e loro misura", "studied", [ "geometry-basics" ], [ 10 ], [] ],
    "triangles" => [ "Triangoli e criteri di congruenza", "studied", [ "angles" ], [ 11 ], [ 11 ] ],
    "parallel" => [ "Rette parallele e angoli formati da una trasversale", "studied", [ "angles" ], [ 10 ], [] ],
    "quadrilaterals" => [ "Quadrilateri e loro proprietà", "studied", [ "triangles", "parallel" ], [ 12 ], [ 11 ] ],
    "perimeter" => [ "Perimetro e area delle figure piane", "studied", [ "quadrilaterals", "decimals" ], [ 12 ], [] ],
    "pythagoras" => [ "Il teorema di Pitagora", "in_progress", [ "perimeter", "number" ], [ 13 ], [ 12 ] ],
    "similarity" => [ "Similitudine e teorema di Talete", "not_in_prima", [ "proportions", "triangles" ], [], [ 12 ] ],
    "circle" => [ "Circonferenza e cerchio", "studied", [ "perimeter" ], [ 13 ], [] ],
    "statistics" => [ "Medie e frequenze di un'indagine", "middle_school", [ "decimals" ], [], [] ],
    "probability" => [ "Probabilità di un evento semplice", "integration_studied", [ "fractions", "statistics" ], [ 14 ], [ 13 ] ],
    "geometry-algebra" => [ "Geometria e algebra insieme", "in_progress", [ "perimeter", "linear-eq" ], [ 14 ], [] ]
  }.freeze

  COMPOSITES = { "geometry-algebra" => [ "perimeter", "linear-eq", "angles" ] }.freeze

  def seed_syllabus_lines!
    prima = SyllabusSource.find_or_create_by!(key: "prima-2025-26") { |s| s.line_count = 20; s.sha256 = "0" * 64 }
    seconda = SyllabusSource.find_or_create_by!(key: "seconda-2026-27") { |s| s.line_count = 20; s.sha256 = "1" * 64 }
    (1..14).each { |n| SyllabusLine.find_or_create_by!(syllabus_source: prima, number: n) { |l| l.text = "Riga di prova numero #{n} del programma di prima: argomento #{n}."; l.origin = "pdf" } }
    (1..13).each { |n| SyllabusLine.find_or_create_by!(syllabus_source: seconda, number: n) { |l| l.text = "Riga di prova #{n} del programma di seconda: contenuto che richiede le basi di #{n}."; l.origin = "pdf" } }
  end

  # Replaces the UI subject's graph by a big one (a new revision) and returns it. Skills keep the keys "math.<suffix>".
  def build_big_graph!(world, subject: world[:subject], deferred: true, extra: {})
    seed_syllabus_lines!
    session = AgentSession.find_or_create_by!(label: "ui-author", role: "author")
    skills = SKILLS.map do |suffix, (name, scope, pre, taught, needed)|
      refs = taught.map { |n| { source: "prima-2025-26", line: n, role: "taught_in" } } + needed.map { |n| { source: "seconda-2026-27", line: n, role: "needed_by" } }
      row = { key: "#{subject.key}.#{suffix}", label_it: name, layer: %w[core core sec opt][suffix.size % 4] || "core", scope: scope,
              scope_reason_it: (scope == "studied" ? nil : "Motivo di prova per #{name}."),
              prerequisites: pre.map { |p| "#{subject.key}.#{p}" }, refs: refs,
              errors: [ { code: "E-#{suffix.upcase[0, 6]}", description_it: "Errore tipico di prova su #{name}.", implicates: [] } ] }
      row[:composite_of] = COMPOSITES[suffix].map { |p| "#{subject.key}.#{p}" } if COMPOSITES[suffix]
      row[:layer] = "core" unless %w[core sec opt].include?(row[:layer])
      row
    end
    if deferred
      skills.find { |s| s[:key].end_with?(".probability") }[:deferred_prerequisites] = [ { skill: "science.data", reason_it: "Serve saper leggere un grafico." } ]
    end
    skills.each { |s| s.merge!(extra[s[:key]] || {}) }
    SkillGraphRevision.create!(subject: subject, seq: SkillGraphRevision.where(subject: subject).maximum(:seq) + 1, author_session: session,
                               body_json: { schema: "banco.skill_graph/1", subject: subject.key, skills: skills }.to_json)
  end

  WIDE_TOPICS = %w[Lettura Ortografia Lessico Sintassi Testo Grammatica Verbo Nome Aggettivo Pronome Frase Periodo].freeze

  # A second shape for the screenshots: 36 skills in six levels, every skill needing two of the level before and now and then one two levels back.
  def build_wide_graph!(world, subject: world[:subject], levels: 6)
    session = AgentSession.find_or_create_by!(label: "ui-author", role: "author")
    scopes = %w[studied studied integration_studied in_progress middle_school not_in_prima]
    skills = (0...(levels * 6)).map do |i|
      level, j = i.divmod(6)
      prerequisites = level.zero? ? [] : [ (level - 1) * 6 + j, (level - 1) * 6 + (j + 1) % 6 ]
      prerequisites << (level - 2) * 6 + (j + 3) % 6 if level >= 2 && (i % 7).zero?
      { key: "#{subject.key}.w#{i}", label_it: "#{WIDE_TOPICS[i % 12]}: capire come si usa il caso numero #{i + 1}", layer: "core", scope: scopes[(i * 5) % 6],
        prerequisites: prerequisites.uniq.map { |n| "#{subject.key}.w#{n}" }, errors: [],
        refs: [ { source: "prima-2025-26", line: 1 + i % 14, role: "taught_in" } ] * (i % 5 == 4 ? 0 : 1) }
    end
    seed_syllabus_lines!
    SkillGraphRevision.create!(subject: subject, seq: SkillGraphRevision.where(subject: subject).maximum(:seq) + 1, author_session: session,
                               body_json: { schema: "banco.skill_graph/1", subject: subject.key, skills: skills }.to_json)
  end
end
