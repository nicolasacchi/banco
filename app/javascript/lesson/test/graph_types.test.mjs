// The graph family (WAVE2 2.1, T4b), the browser's half of the vector files test/fixtures/diagrams/{types/network,types/chain,flow_line}.json
// (Ruby runs the same: test/lib/lessons/graph_types_test.rb): refused figures give { error } with the code and path of Ruby's finding,
// good ones draw at 320, 390, 768 and 1280 px and 18, 20 and 26 px in every state and with every control, and what each state prints and
// offers as select targets is what Ruby computed.
import "./setup.mjs"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../../../../", import.meta.url)
const doc = (path) => JSON.parse(readFileSync(new URL(path, root), "utf8"))
const MODULES = {
  network: await import("lesson/diagrams/graph/network"),
  chain: await import("lesson/diagrams/graph/chain"),
  flow: await import("lesson/diagrams/flow")
}
const FILES = ["test/fixtures/diagrams/types/network.json", "test/fixtures/diagrams/types/chain.json", "test/fixtures/diagrams/flow_line.json"]
const WIDTHS = [320, 390, 768, 1280]
const SIZES = [18, 20, 26]

// every control of a figure, in the values the tests try: nothing chosen, each value alone, all of them
function controlSets(mod, data) {
  const list = mod.controls ? mod.controls(data) : []
  if (!list.length) return [{}]
  const sets = [{}]
  for (const c of list) {
    for (const v of c.values) sets.push({ [c.id]: [v.value] })
    sets.push({ [c.id]: c.values.map((v) => v.value) })
  }
  return sets
}

const edgeKey = (key) => key.replace(/^e:/, "")
const targetIds = (type, set, list) => list.map((t) => (set === "edges" ? edgeKey(t.key) : t.key.replace(/^[ns]:/, "")))

for (const file of FILES) {
  const { vectors } = doc(file)
  for (const v of vectors) {
    const mod = MODULES[v.data.type]
    const refused = v.schema === "invalid" || v.semantic !== "ok"
    test(`${refused ? "refuses" : "draws"} ${v.name}`, () => {
      if (refused) {
        const result = mod.layout(v.data, { width: 390, fontPx: 20, subject: v.subject })
        assert.ok(result.error, `expected an error, got a scene`)
        if (v.schema === "valid") {
          assert.equal(result.error.code, v.semantic, `code (${result.error.path}: ${result.error.message})`)
          assert.equal(result.error.path, v.path, result.error.message)
        }
        return
      }
      const states = Math.max(1, v.data.states?.length ?? 1)
      for (const controls of controlSets(mod, v.data)) {
        for (let state = 0; state < states; state++) {
          assert.ok(mod.describe(v.data, { state, controls }).length > 20, "a description")
          for (const width of WIDTHS) {
            for (const fontPx of SIZES) {
              const scene = mod.layout(v.data, { width, fontPx, subject: v.subject, state, controls })
              const where = `${v.name} ${width}/${fontPx}/state ${state}/${JSON.stringify(controls)}`
              assert.ok(!scene.error, `${where}: ${scene.error?.message}`)
              assert.equal(scene.width, width)
              assert.ok(scene.height > 0, where)
              for (const l of scene.labels) {
                assert.ok(l.px >= fontPx, `${where}: label size`)
                assert.ok(l.x >= -0.5 && l.x + l.w <= width + 0.5, `${where}: label inside (${l.text_it})`)
              }
              for (const s of scene.shapes) if (s.kind === "icon") assert.ok(s.x >= -1 && s.x + s.size <= width + 1, `${where}: icon inside`)
            }
          }
        }
      }
      // what each state prints and what a select check can aim at: the numbers Ruby computed
      for (let state = 0; state < states; state++) assert.deepEqual(mod.printed(v.data, state), v.expect.printed[state], `${v.name}: printed, state ${state}`)
      for (const [set, ids] of Object.entries(v.expect.targets)) {
        const mine = mod.targets(v.data, set)
        assert.deepEqual(targetIds(v.data.type, set, mine), ids, `${v.name}: targets ${set}`)
        for (const t of mine) assert.ok(t.bbox && t.bbox.w > 0 && t.neutral_it, `${v.name}: ${t.key} has a box and a neutral description`)
      }
    })
  }
}

test("select mode: every candidate looks the same, carries a target, and no text of the figure", () => {
  for (const file of FILES) {
    for (const v of doc(file).vectors.filter((x) => x.schema === "valid" && x.semantic === "ok")) {
      const mod = MODULES[v.data.type]
      const scene = mod.layout(v.data, { width: 700, fontPx: 20, subject: v.subject, mode: "select" })
      assert.ok(!scene.error, `${v.name}: ${scene.error?.message}`)
      const targets = scene.shapes.filter((s) => s.target)
      assert.ok(targets.length >= 2, `${v.name}: targets`)
      assert.equal(new Set(targets.map((s) => s.target)).size, targets.length)
      const nodesOnly = targets.filter((s) => s.kind === "rect" || s.kind === "circle")
      if (nodesOnly.length > 1) {
        assert.equal(new Set(nodesOnly.map((s) => `${s.cls}|${s.w ?? s.r}|${s.h ?? ""}`)).size, 1, `${v.name}: candidates in one style`)
      }
      const texts = JSON.stringify(scene.labels.map((l) => l.text_it))
      for (const own of JSON.stringify(v.data).match(/"[^"]{6,}"/g) ?? []) if (/^"[A-Z]/.test(own) && !own.includes("zzz")) assert.ok(!texts.includes(own.slice(1, -1)), `${v.name}: ${own} drawn in select mode`)
      assert.equal(scene.labels.filter((l) => !/^\d+$/.test(l.text_it)).length, 0, `${v.name}: no label at all, only numbers`)
    }
  }
})

test("Togli una causa: the nodes left without a cause are greyed, the sentence appears, and putting the cause back undoes it", () => {
  const fan = doc("test/fixtures/diagrams/types/chain.json").vectors.find((v) => v.name === "chain-fan-remove-states").data
  const draw = (remove) => MODULES.chain.layout(fan, { width: 900, fontPx: 20, subject: "history", state: 2, controls: { remove } })
  const classes = (scene, id) => scene.shapes.find((s) => s.key === `n:${id}`).cls
  const none = draw([])
  assert.ok(!/grey|removed/.test(classes(none, "ev")))
  assert.ok(!none.labels.some((l) => l.cls.includes("dg-chain-note")))
  const one = draw(["c4"])
  assert.ok(/removed/.test(classes(one, "c4")))
  assert.ok(!/grey/.test(classes(one, "ev")), "the event keeps its other cause")
  assert.ok(one.labels.some((l) => l.text_it.startsWith("Ogni fatto ha ancora una causa")))
  const both = draw(["c4", "c5"])
  assert.ok(/grey/.test(classes(both, "ev")) && /grey/.test(classes(both, "e1")))
  assert.ok(/removed/.test(classes(both, "c5")))
  assert.ok(!/grey|removed/.test(classes(both, "c3")), "a cause that stays")
  assert.ok(both.labels.some((l) => l.text_it.includes("è un'ipotesi")))
  assert.ok(both.live.startsWith("Ora hai tolto"))
  assert.deepEqual(draw([]).shapes.map((s) => s.cls), none.shapes.map((s) => s.cls), "putting the causes back gives the first picture")
  assert.ok(!draw(["ev"]).error, "a node that is not a cause cannot be taken away; it is ignored")
  assert.ok(!/removed/.test(classes(draw(["ev"]), "ev")))
})

test("a state's show decides which nodes are drawn; the places do not move", () => {
  const fan = doc("test/fixtures/diagrams/types/chain.json").vectors.find((v) => v.name === "chain-fan-remove-states").data
  const at = (state) => MODULES.chain.layout(fan, { width: 900, fontPx: 20, subject: "history", state })
  const first = at(0)
  const last = at(2)
  assert.ok(first.shapes.some((s) => s.key === "n:c1") && !first.shapes.some((s) => s.key === "n:c2"))
  assert.deepEqual(first.shapes.find((s) => s.key === "n:c1"), last.shapes.find((s) => s.key === "n:c1"))
  assert.ok(!MODULES.chain.describe(fan, { state: 0 }).includes("Latifondi") && MODULES.chain.describe(fan, { state: 2 }).includes("Il consiglio blocca"))
})

test("network: the kind chips keep only those arrows; a hidden node is not drawn and keeps its place", () => {
  const hub = doc("test/fixtures/diagrams/types/network.json").vectors.find((v) => v.name === "network-hub-filter").data
  const drawn = (controls) => MODULES.network.layout(hub, { width: 900, fontPx: 20, subject: "law_economics", controls })
  const all = drawn({}).shapes.filter((s) => s.kind === "path" && s.cls.startsWith("dg-net-edge")).length
  const only = drawn({ kinds: ["elects"] }).shapes.filter((s) => s.kind === "path" && s.cls.startsWith("dg-net-edge")).length
  assert.equal(all, 5)
  assert.equal(only, 1)
  assert.equal(MODULES.network.controls(hub)[0].values.length, 5)
  assert.match(MODULES.network.describe(hub, { controls: { kinds: ["elects"] } }), /Da Popolo a Senato: elegge\./)
  assert.doesNotMatch(MODULES.network.describe(hub, { controls: { kinds: ["elects"] } }), /trusts|fiducia/)
  const power = doc("test/fixtures/diagrams/types/network.json").vectors.find((v) => v.name === "network-everyone-holds-hide").data
  const wide = (state) => MODULES.network.layout(power, { width: 900, fontPx: 20, subject: "law_economics", state })
  assert.ok(wide(1).shapes.some((s) => s.key === "n:con"))
  assert.ok(!wide(2).shapes.some((s) => s.key === "n:con"))
  assert.deepEqual(wide(0).shapes.find((s) => s.key === "n:re"), wide(2).shapes.find((s) => s.key === "n:re"), "the king does not move")
})

test("network: a phone gets the stacked nodes and the numbered moves, a crowded figure the numbers on its arrows", () => {
  const pair = doc("test/fixtures/diagrams/types/network.json").vectors[0].data
  const narrow = MODULES.network.layout(pair, { width: 360, fontPx: 20, subject: "law_economics", state: 1 })
  assert.equal(narrow.mode, "list")
  assert.ok(narrow.labels.some((l) => l.text_it === "Da Anna a Paolo: consegna la bicicletta"))
  assert.equal(narrow.shapes.filter((s) => s.kind === "path").length, 0, "no arrow on a phone")
  const wide = MODULES.network.layout(pair, { width: 1000, fontPx: 20, subject: "law_economics", state: 1 })
  assert.equal(wide.mode, "arrows")
  assert.ok(wide.labels.some((l) => l.text_it === "consegna la bicicletta"))
  assert.ok(wide.shapes.some((s) => s.kind === "icon" && s.cls === "dg-net-what"))
})

test("flow line: horizontal when the words fit, vertical on a phone, the token follows the state, the arcs are the returns", () => {
  const letter = doc("test/fixtures/diagrams/flow_line.json").vectors.find((v) => v.name === "flow-line-letter").data
  const lay = (width, state) => MODULES.flow.layout(letter, { width, fontPx: 20, subject: "law_economics", state })
  const ys = (scene) => scene.shapes.filter((s) => s.cls?.startsWith("dg-flow-station")).map((s) => s.cy)
  assert.equal(new Set(ys(lay(1000, 0))).size, 2, "two lanes across")
  assert.equal(new Set(ys(lay(390, 0))).size, ys(lay(390, 0)).length, "one station under another on a phone")
  // the states of the letter put the token at the office, the sorting, the postman, and back to the sorting
  const at = (state) => lay(1000, state).shapes.find((s) => s.key === "token").cx
  const station = (state, id) => lay(1000, state).shapes.find((s) => s.key === `s:${id}`).cx
  assert.ok(at(2) > at(0), "the token moved on")
  assert.equal(at(0), station(0, "uff"))
  assert.equal(at(3), station(3, "smi"), "a return takes the token back")
  assert.ok(at(3) < at(2))
  assert.ok(lay(1000, 3).shapes.some((s) => s.key === "ret:por>smi"))
  assert.ok(lay(390, 3).labels.some((l) => l.text_it.startsWith("Da Portalettere a Smistamento")))
  assert.ok(lay(1000, 2).live.includes("Portalettere"))
})

test("the tree flow is untouched by the line layout", () => {
  const tree = { type: "flow", alt_it: "Schema: due passi, poi una domanda con due risposte.", nodes: [{ id: "a", kind: "step", text_it: "Primo" }, { id: "b", kind: "step", text_it: "Secondo" }, { id: "q", kind: "decision", text_it: "Domanda?" }, { id: "s", kind: "end", text_it: "Sì" }, { id: "n", kind: "end", text_it: "No" }], edges: [["a", "b"], ["b", "q"], ["q", "s", "sì"], ["q", "n", "no"]] }
  assert.ok(!MODULES.flow.layout(tree, { width: 760, fontPx: 20, subject: "math" }).error)
  assert.ok(MODULES.flow.describe(tree).startsWith("Uno schema a domande"))
  assert.deepEqual(MODULES.flow.printed(tree), ["Primo", "Secondo", "Domanda?", "Sì", "No", "sì", "no"])
})
