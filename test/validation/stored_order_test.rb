require "test_helper"
require_relative "../support/validation_fixtures"

# W-SOLUTION-STORED-ORDER (D-335): a solution step, final or hint of a choice, matching or ordering instance that
# names an option by its place, letter or id points at a list the student sees shuffled.
class StoredOrderTest < ActiveSupport::TestCase
  F = ValidationFixtures
  CODE = "W-SOLUTION-STORED-ORDER".freeze

  def unit(component, body = {})
    Validation::Units::Unit.new(path: "", skill: F::SKILL, component: component, body: { "kind" => "diagnosis_item" }.merge(body), generator: false, instances: [])
  end

  def findings(component, display, solution: nil, hints: nil, body: {})
    inst = { "display" => display, "answer" => answer_for(component, display), "errors" => [], "solution" => solution || { "steps" => [ { "text_it" => "Ragiona." } ], "final" => "Fatto." } }
    inst["hints_it"] = hints if hints
    Validation::InstanceChecks.new(unit(component, body), context: F.context).call(inst, label: "/instances/0").select { |f| f.code == CODE }
  end

  def answer_for(component, display)
    case component
    when "choice" then display["options"].first["id"]
    when "ordering" then display["elements"].map { |e| e["id"] }
    else display["left"].zip(display["right"]).to_h { |l, r| [ l["id"], r["id"] ] }
    end
  end

  CHOICE = { "stem_it" => "Quale evento viene prima?", "options" => [ { "id" => "o1", "text" => "La prima guerra mondiale" }, { "id" => "o2", "text" => "La seconda" }, { "id" => "o3", "text" => "La terza" } ] }.freeze
  LETTERS = { "stem_it" => "Quale?", "options" => [ { "id" => "a", "text" => "Roma" }, { "id" => "b", "text" => "Milano" }, { "id" => "c", "text" => "Torino" } ] }.freeze
  ORDERING = { "stem_it" => "Ordina.", "elements" => [ { "id" => "e1", "text" => "Linea" }, { "id" => "e2", "text" => "Colonna" }, { "id" => "e3", "text" => "Cella" } ] }.freeze
  MATCHING = { "stem_it" => "Abbina.", "left" => [ { "id" => "l1", "text" => "Roma" }, { "id" => "l2", "text" => "Parigi" } ],
               "right" => [ { "id" => "r1", "text" => "Italia" }, { "id" => "r2", "text" => "Francia" }, { "id" => "r3", "text" => "Spagna" } ] }.freeze

  def final(text) = { "steps" => [ { "text_it" => "Ragiona." } ], "final" => text }
  def step(text) = { "steps" => [ { "text_it" => text } ], "final" => "Fatto." }

  test "positions of the stored order fire, in the final, in a step and in a hint" do
    [ "Dall'alto: Linea, Colonna, Cella.", "Nell'ordine delle righe: Linea, Colonna.", "La prima frase è quella giusta.", "Vale l'ultima opzione.",
     "Guarda la seconda riga.", "Scegli la terza risposta.", "Il primo è in alto nell'elenco.", "La riga a destra è giusta.",
     "Scrivi «dall’alto» come vedi.", "È l'opzione b.", "Scelta: risposta B." ].each do |text|
      assert_equal 1, findings("ordering", ORDERING, solution: final(text)).size, text
      assert_equal 1, findings("ordering", ORDERING, solution: step(text)).size, text
    end
    assert_equal 1, findings("choice", CHOICE, hints: [ "Pensa.", "Guarda la prima opzione." ], body: { "kind" => "practice_item" }).size
    assert_equal "/instances/0/hints_it/1", findings("choice", CHOICE, hints: [ "Pensa.", "Guarda la prima opzione." ], body: { "kind" => "practice_item" }).first.field
  end

  test "the item-level hints of a practice item are read when the instance has none" do
    got = findings("choice", CHOICE, body: { "kind" => "practice_item", "hints_it" => [ "Pensa.", "Dall'alto, la seconda." ] })
    assert_equal [ "/hints_it/1" ], got.map(&:field)
  end

  test "internal ids fire as bare tokens of this instance's own list" do
    assert_equal 1, findings("ordering", ORDERING, solution: final("Ordine: e1, e2, e3.")).size
    assert_equal 1, findings("matching", MATCHING, solution: final("l1 con r1, l2 con r2.")).size
    assert_equal 1, findings("choice", CHOICE, solution: final("La risposta è o1.")).size
    assert_equal 1, findings("choice", LETTERS, solution: step("Vedi a) e poi b).")).size
    assert_empty findings("matching", MATCHING, solution: final("l12, l1x e r4 non sono id di questa riga."))
    assert_empty findings("choice", CHOICE, solution: final("Una pagina a) senza id di lettera."))
  end

  test "normal prose is quiet" do
    assert_empty findings("choice", CHOICE, solution: final("La prima guerra mondiale iniziò nel 1914."))
    assert_empty findings("choice", CHOICE, solution: step("La seconda guerra mondiale e la terza fase del piano."))
    assert_empty findings("choice", CHOICE, solution: final("Prima di tutto, rispondi a questa domanda; poi a destra e a sinistra della retta."))
    assert_empty findings("choice", CHOICE, solution: final("Nella prima frase del testo l'autore parla di pace; l'ultima riga del brano lo conferma."))
    assert_empty findings("ordering", ORDERING, solution: final("Metti i passi nell'ordine corretto: Linea, Colonna, Cella."))
    assert_empty findings("choice", LETTERS, solution: final("La risposta a questa domanda è Roma, e $f(a)$ vale 2; la lettera a cambia."))
    assert_empty findings("choice", CHOICE, solution: final("La cella B3 e o1x non sono ids."))
  end

  test "a solution that names the option's text is quiet" do
    assert_empty findings("choice", CHOICE, solution: final("La risposta giusta è «La prima guerra mondiale»."))
    assert_empty findings("ordering", ORDERING, solution: final("Prima la Linea, poi la Colonna e infine la Cella."))
  end

  test "other components are not read" do
    display = { "stem_it" => "Quanto?" }
    inst = { "display" => display, "answer" => "7", "errors" => [], "solution" => final("Dall'alto, la prima opzione.") }
    got = Validation::InstanceChecks.new(unit("number"), context: F.context).call(inst, label: "/instances/0")
    assert_not got.include_code?(CODE)
  end

  test "the warning comes out of a whole item run, and never fails it" do
    bad = F.choice_instance("sette", %w[tredici nove undici]).tap { |i| i["solution"]["steps"] = [ { "text_it" => "Dall'alto, la prima opzione." } ] }
    item = F.choice_item("instances" => [ bad, F.choice_instance("otto", %w[quattro sei dieci]) ])
    result = Validation::ItemRunner.new(files: F.files_for(item), context: F.context).call
    finding = result.findings.find { |f| f.code == CODE }
    assert finding
    assert_equal "warning", finding.severity
    assert_equal "/instances/0/solution/steps/0/text_it", finding.field
    assert_equal "passed", result.status
  end
end
