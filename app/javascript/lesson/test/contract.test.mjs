// W2-0: the component contract v2 (WAVE2 1.2), the generated registries, the stub modules, the shared interfaces (graph router, chart
// axis, grid api, speech) and the library signatures. The builders replace the stubs; these tests say what must stay true.
import "./setup.mjs"
import test from "node:test"
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"

const root = new URL("../../../../", import.meta.url)
const json = (path) => JSON.parse(readFileSync(new URL(path, root), "utf8"))
const registry = await import("lesson/diagrams/registry")
const checks = await import("lesson/checks/registry")
const { checkModule, checkControls, defaultSpeak, OPTIONAL_EXPORTS } = await import("lesson/diagrams/contract")
const { validate } = await import("lesson/schema")
const { NotBuilt } = await import("lesson/lib/not_built")

test("the registry knows 38 diagram types: 9 available and 29 behind a lazy loader, each with a module that keeps the contract", async () => {
  assert.equal(Object.keys(registry.STATUS).length, 38)
  assert.equal(Object.keys(registry.TYPES).length, 9)
  for (const [type, status] of Object.entries(registry.STATUS)) {
    const mod = await registry.load(type)
    assert.ok(mod, `${type} loads`)
    assert.deepEqual(checkModule(mod), [], type)
    if (status === "available") assert.equal(registry.TYPES[type], mod, `${type} is eager`)
  }
  assert.equal(await registry.load("venn"), null)
})

test("a stub answers the contract's error and an empty description, and never throws", async () => {
  for (const type of Object.keys(registry.STATUS)) {
    if (registry.STATUS[type] === "available") continue
    const mod = await registry.load(type)
    const scene = mod.layout({ type }, { width: 390, fontPx: 18 })
    assert.equal(scene.error.code, "E-LESSON-DIAGRAM", type)
    assert.equal(mod.describe({ type }), "", type)
    assert.equal(mod.type, type)
  }
})

test("the layout of an unloaded type falls to the unknown-type error, a loaded stub to its own", async () => {
  assert.equal(registry.layout({ type: "network" }, { width: 390, fontPx: 18, subject: "law_economics" }).error?.code, "E-LESSON-DIAGRAM")
  await registry.preload(["network"])
  assert.ok(registry.moduleFor("network"))
})

test("home palettes, held-back views and families come from the registry file", () => {
  assert.equal(registry.HOME_PALETTE.balance, "math")
  assert.equal(registry.HOME_PALETTE.register, "computer_science")
  assert.equal(registry.HOME_PALETTE.strand, "biology")
  assert.equal(registry.HOME_PALETTE.formula, "chemistry")
  assert.equal(registry.HOME_PALETTE.network, undefined)
  assert.equal(registry.HELD_BACK.flow.layout.line, "reserved")
  assert.equal(registry.FAMILY.network, "graph")
})

test("the schema of every wave 2 type accepts its example and refuses the case with an unknown field (the schema column of the vectors)", async () => {
  const dir = new URL("test/fixtures/diagrams/types/", root)
  const files = readdirSync(dir).filter((f) => f.endsWith(".json"))
  assert.equal(files.length, 26)
  for (const file of files) {
    const doc = JSON.parse(readFileSync(new URL(file, dir), "utf8"))
    const mod = await registry.load(doc.type)
    for (const v of doc.vectors) {
      const bad = validate(mod.schema, v.data)
      if (v.schema === "valid") assert.equal(bad, null, `${v.name}: ${JSON.stringify(bad)}`)
      else assert.ok(bad, `${v.name} should be refused`)
    }
  }
})

test("the check registry lists every component with its status and a loader for the new ones", async () => {
  assert.equal(Object.keys(checks.COMPONENTS).length, 12)
  assert.equal(checks.isAvailable("choice"), true)
  assert.equal(checks.isAvailable("select"), false)
  assert.equal(await checks.load("choice"), null)
  for (const name of ["select", "tiles", "ordering", "amount_words", "cell_formula", "trace"]) {
    const mod = await checks.load(name)
    assert.equal(mod.type, name)
    assert.equal(typeof mod.render, "function")
  }
  assert.equal(checks.OPTIONS.listen.status, "reserved")
})

test("controls: a slider declares its range and step, every control a label, kinds are the contract's", () => {
  assert.deepEqual(checkControls([{ id: "n", kind: "stepper", label_it: "Passo" }, { id: "s", kind: "slider", range: ["0", "10"], step: "1", label_it: "Presenti" }]), [])
  assert.match(checkControls([{ id: "s", kind: "slider", label_it: "Presenti" }])[0], /slider declares its range/)
  assert.match(checkControls([{ id: "x", kind: "knob", label_it: "x" }])[0], /unknown kind/)
  assert.match(checkControls([{ id: "x", kind: "tap" }])[0], /no label_it/)
})

test("module checks: layout and describe are required, the optional exports must be functions", () => {
  assert.deepEqual(checkModule({ layout() {}, describe() {} }), [])
  assert.equal(checkModule({ layout() {} }).length, 1)
  assert.deepEqual(OPTIONAL_EXPORTS, ["speak", "controls", "targets", "printed", "recordAtRender", "layout3d"])
  assert.match(checkModule({ layout() {}, describe() {}, speak: 3 })[0], /speak/)
  assert.deepEqual(defaultSpeak(() => "Un testo", {}, {}), [{ lang: "it", text: "Un testo" }])
  assert.deepEqual(defaultSpeak(() => "", {}, {}), [])
})

test("program declares recordAtRender, the only type that does in wave 2, and it returns records and findings", async () => {
  const program = await registry.load("program")
  assert.deepEqual(program.recordAtRender({}), { records: [], findings: [] })
  for (const type of Object.keys(registry.STATUS)) {
    if (type === "program") continue
    assert.equal((await registry.load(type)).recordAtRender, undefined, type)
  }
})

test("the shared interfaces are frozen: the router, the axis and the grid api export their functions, which throw NotBuilt until their track", async () => {
  const router = await import("lesson/diagrams/graph/router")
  const axis = await import("lesson/diagrams/chart/axis")
  const grid = await import("lesson/diagrams/grid/api")
  for (const [mod, names] of [[router, ["place", "route", "flip", "moveList"]], [axis, ["linear", "log", "readCursor", "legend", "valueTable"]], [grid, ["grid", "cellBox", "outline", "stackForPhone", "scrollFrame", "cellTargets"]]]) {
    for (const name of names) assert.throws(() => mod[name](), NotBuilt, name)
  }
  assert.ok(router.LAYOUTS.includes("hub"))
})

test("speech: the voice gate keeps local voices of the language that the operator accepted, and prefers en-GB, es-ES, it-IT", async () => {
  const speech = await import("lesson/speech")
  const voice = (name, lang, localService = true) => ({ name, lang, localService })
  const available = [voice("Daniel", "en-GB"), voice("Samantha", "en-US"), voice("Google US English", "en-US", false), voice("Monica", "es-ES"), voice("Paulina", "es-MX"), voice("Alice", "it-IT")]
  const accepted = { en: ["Samantha", "Daniel", "Google US English"], es: ["Paulina"], it: [] }
  assert.equal(speech.voiceFor("en", available, { accepted }).name, "Daniel", "en-GB first")
  assert.equal(speech.voiceFor("en", available.slice(1), { accepted }).name, "Samantha", "then other English, local only")
  assert.equal(speech.voiceFor("es", available, { accepted }).name, "Paulina", "only the accepted one, not Monica")
  assert.equal(speech.voiceFor("it", available, { accepted }), null, "no accepted Italian voice: no speaker")
  assert.equal(speech.voiceFor("it", available, { accepted, preview: true }).name, "Alice", "the teacher's preview may try any local voice")
  assert.equal(speech.voiceFor("fr", available, { preview: true }), null)
  assert.equal(speech.voiceFor("en", [voice("Google US English", "en-US", false)], { accepted, preview: true }), null, "a network voice is never used")
  assert.equal(speech.rateFor("it"), 1.0)
  assert.equal(speech.rateFor("it", true), 0.8)
  assert.equal(speech.rateFor("en", true), 0.75)
  assert.equal(speech.rateFor("es", true), 0.7)
  assert.throws(() => speech.speak([]), NotBuilt)
})

test("the library signatures: the JS twin of each library has the functions its vector file lists, and they throw NotBuilt", async () => {
  const dir = new URL("test/fixtures/lesson2/", root)
  const vectors = { chrono: "chrono.json", dates: "dates.json", num_words: "amount_words.json", money: "money.json", chem: "chem_formulas.json", words: "spanish_words.json", verbs: "verbs.json", bits: "bits.json", program: "program.json", sheet: "sheet.json" }
  for (const [name, file] of Object.entries(vectors)) {
    const doc = JSON.parse(readFileSync(new URL(file, dir), "utf8"))
    const lib = await import(`lesson/lib/${name}`)
    assert.deepEqual(Object.keys(lib.SIGNATURES).sort(), Object.keys(doc.functions).sort(), name)
    for (const [fn, spec] of Object.entries(doc.functions)) {
      assert.equal(lib.SIGNATURES[fn], spec.js, `${name}.${fn}`)
      const jsName = spec.js.split("(")[0]
      assert.throws(() => lib[jsName](), NotBuilt, `${name}.${jsName}`)
      for (const c of spec.cases) assert.ok(Array.isArray(c.args) && "result" in c, `${name}.${fn} case`)
    }
  }
})
