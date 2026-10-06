# A synthetic subject for the student's pages: one skill per component, each with
# a revision of its own and several instances inserted directly (M5 builds the
# validation in parallel; nothing here depends on it). Nothing about a real
# student or a real course: the items are arithmetic and word games.
module StudentUiRows
  COMPONENTS = %w[number fraction choice ordering matching normalized_text expression testlet short_answer].freeze
  INSTANCES = 5

  # Builds the subject, its graph, items and blueprint. Returns a Hash:
  # {subject:, student:, preview:, blueprint:, revisions: {component => revision}}.
  def build_ui_subject(key: "math", name: "Matematica", components: COMPONENTS, depends_on: [], position: 1, sitting_minutes: 30, approve: true)
    session = AgentSession.find_or_create_by!(label: "ui-author", role: "author")
    subject = Subject.find_or_create_by!(key: key) { |s| s.name_it = name; s.position = position }
    student = Student.find_or_create_by!(key: "student") { |s| s.kind = "student" }
    preview = Student.find_or_create_by!(key: "preview") { |s| s.kind = "preview" }
    skills = components.map { |c| skill_key(key, c) }
    graph = SkillGraphRevision.create!(
      subject: subject, seq: (SkillGraphRevision.where(subject: subject).maximum(:seq) || 0) + 1, author_session: session,
      body_json: { schema: "banco.skill_graph/1", subject: key,
                   skills: skills.map { |k| { key: k, label_it: "Abilità #{k.split('.').last}", layer: "core", scope: "studied",
                                              prerequisites: [], refs: [], errors: [] } } }.to_json
    )
    revisions = components.to_h { |c| [ c, build_ui_revision(subject, session, c, skill_key(key, c)) ] }
    # A testlet counts one outcome per passage, so the second outcome of its skill
    # has to come from another item (B-02): the pool has a second testlet.
    extra = components.include?("testlet") ? { "testlet" => build_ui_revision(subject, session, "testlet", skill_key(key, "testlet")) } : {}
    blueprint = BlueprintRevision.create!(
      subject: subject, skill_graph_revision: graph, author_session: session,
      seq: (BlueprintRevision.where(subject: subject).maximum(:seq) || 0) + 1,
      body_json: { schema: "banco.blueprint/1", schema_version: 1, subject: key, graph_revision_id: graph.id.to_s,
                   entries: components.map { |c| { skill: skill_key(key, c), items: [ revisions[c].id, extra[c]&.id ].compact.map(&:to_s) } },
                   budget: { sitting_minutes: sitting_minutes, sittings: 2 }, depends_on_subjects: depends_on, calculator: "no",
                   intro_note_it: "Nota di prova per chi comincia.", not_measured_it: "Non misura la scrittura a mano." }.to_json
    )
    approve_ui_subject!(subject, graph, blueprint) if approve
    { subject: subject, student: student, preview: preview, blueprint: blueprint, revisions: revisions }
  end

  # What the teacher's two approvals leave behind; a student's run pins the approved
  # blueprint, so every subject of the student's tests is approved unless asked not.
  def approve_ui_subject!(subject, graph, blueprint)
    { "approve_skill_graph" => graph, "approve_blueprint" => blueprint }.each do |kind, revision|
      Decision.create!(kind: kind, subject: subject, payload_json: { revision_id: revision.id }.to_json, request_id: SecureRandom.uuid,
                       teacher_login: "teacher", groups: "banco-teacher", remote_addr: "127.0.0.1")
    end
  end

  def skill_key(subject_key, component) = "#{subject_key}.#{component.tr('_', '-')}"

  def release_diagnosis!
    Decision.create!(kind: "release_diagnosis", payload_json: "{}", request_id: SecureRandom.uuid, teacher_login: "teacher",
                     remote_addr: "127.0.0.1")
  end

  def build_ui_revision(subject, session, component, skill)
    kind = { "testlet" => "testlet", "short_answer" => "short_answer" }.fetch(component, "diagnosis_item")
    body = { schema: "banco.item/1", schema_version: 1, kind: kind, subject: subject.key, skill: skill, component: component,
             expected_seconds: 60 }
    body.delete(:component) if component == "testlet"
    body[:prompt] = { stem_it: ui_stem(component) } unless component == "testlet"
    body[:form] = [ "lowest_terms" ] if component == "fraction"
    body[:unit] = "cm" if component == "number"
    case component
    when "testlet"
      body[:passage_it] = "Un **brano** di prova. Dice che il numero $x$ vale 4."
      body[:expected_seconds] = 300
      body[:sub_items] = (1..5).map { |n| sub_body(skill, n) }
    when "short_answer"
      body[:passage_it] = "Un breve testo da riassumere."
      body[:rubric] = { points: [ { id: "a", weight: 1, expected_it: "Dice una cosa." }, { id: "b", weight: 1, expected_it: "Ne dice un'altra." } ],
                        threshold: 0.6, model_answer_it: "Una risposta." }
    end
    item = Item.create!(subject: subject, key: "ui-#{component}-#{SecureRandom.hex(3)}", kind: kind)
    revision = ItemRevision.create!(item: item, seq: 1, body_json: body.to_json, author_session: session,
                                    file_sessions_json: "{}", brief_sha256: "0" * 64)
    ItemValidation.create!(item_revision: revision, seq: 1, status: "passed")
    INSTANCES.times { |i| build_ui_instance(revision, component, i) }
    revision
  end

  def sub_body(skill, n)
    { id: "q#{n}", skill: skill, component: "choice", prompt: { stem_it: "Domanda #{n} sul brano." },
      error_catalogue: [ { code: "misreads", description_it: "x", message_it: "Rileggi il brano.", implicates: [] } ] }
  end

  def ui_stem(component)
    {
      "number" => "Calcola e scrivi il risultato.",
      "fraction" => "Calcola la somma e scrivila come frazione ridotta.",
      "choice" => "Quale numero è pari?",
      "ordering" => "Metti i numeri in ordine, dal più piccolo al più grande.",
      "matching" => "Abbina ogni numero alla sua parola.",
      "normalized_text" => "Scrivi la parola **casa** al plurale.",
      "expression" => "Semplifica l'espressione.",
      "short_answer" => "Scrivi due frasi sul brano."
    }.fetch(component, "Domanda.")
  end

  def build_ui_instance(revision, component, i)
    spec = ui_instance_spec(component, i)
    ItemInstance.create!(
      item_revision: revision, seed: i + 1, display_json: spec[:display].to_json, answer_json: spec[:answer].to_json,
      errors_json: spec[:errors].to_json, solution_json: spec[:solution]&.to_json,
      fingerprint: Digest::SHA256.hexdigest("#{revision.id}-#{i}-#{spec[:display].to_json}")
    )
  end

  def ui_instance_spec(component, i)
    solution = { steps: [ { text_it: "Si fa il conto." } ], final: "Vedi il passaggio." }
    case component
    when "number"
      { display: { stem_it: "$#{i + 2}+4$" }, answer: "#{i + 6}", errors: [ { code: "adds_wrong", value: "99" } ], solution: solution }
    when "fraction"
      { display: { stem_it: "$\\frac{#{i + 1}}{7}+\\frac{0}{7}$" }, answer: { n: i + 1, d: 7 }, errors: [], solution: solution }
    when "choice"
      options = (0..3).map { |n| { id: "o#{n + 1}", text: (n == i % 4 ? 10 + 2 * i : 11 + 2 * n + 4 * i).to_s } }
      { display: { options: options }, answer: "o#{(i % 4) + 1}",
        errors: [ { code: "odd_pick", value: "o#{((i + 1) % 4) + 1}" } ], solution: solution }
    when "ordering"
      values = [ 3 + i, 7 + i, 9 + i, 12 + i ]
      { display: { elements: values.each_with_index.map { |v, n| { id: "e#{n + 1}", text: v.to_s } } },
        answer: %w[e1 e2 e3 e4], errors: [], solution: solution }
    when "matching"
      words = %w[uno due tre quattro cinque]
      { display: { left: (1..4).map { |n| { id: "l#{n}", text: (n + i).to_s } },
                   right: words.first(5).each_with_index.map { |w, n| { id: "r#{n + 1}", text: "#{w}#{i}" } } },
        answer: { "l1" => "r1", "l2" => "r2", "l3" => "r3", "l4" => "r4" }, errors: [], solution: solution }
    when "normalized_text"
      { display: { stem_it: "Caso #{i + 1}." }, answer: "case", errors: [], solution: solution }
    when "expression"
      { display: { stem_it: "$2(x+#{i + 1})$" }, answer: "2x+#{2 * (i + 1)}", errors: [], solution: solution }
    when "testlet"
      subs = (1..5).map do |n|
        { id: "q#{n}", display: { options: (1..4).map { |o| { id: "o#{o}", text: "Risposta #{n}-#{o}-#{i}" } } } }
      end
      { display: { sub_items: subs }, answer: (1..5).to_h { |n| [ "q#{n}", "o#{(n % 4) + 1}" ] }, errors: {}, solution: solution }
    when "short_answer"
      { display: { stem_it: "Brano numero #{i + 1}." }, answer: {}, errors: [], solution: nil }
    end
  end

  # The correct answer of a served item, in the terms of what the student sees:
  # reads the stored key and the logged shuffle, so tests can answer through the page.
  def correct_view_answer(event)
    served = ItemServed.find_by!(diagnosis_event_id: event.id)
    instance = served.item_instance
    body = JSON.parse(instance.item_revision.body_json)
    display = JSON.parse(instance.display_json)
    answer = JSON.parse(instance.answer_json)
    map = JSON.parse(served.id_map_json)
    shown_of = map.invert # stored id => shown id
    { body: body, display: display, answer: answer, shown_of: shown_of, map: map, instance: instance }
  end
end
