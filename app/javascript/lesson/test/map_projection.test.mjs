import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import { TYPES, project, rawProject } from "../lib/map_projection.js"

const vectors = JSON.parse(readFileSync(new URL("../../../../test/fixtures/maps/projection_vectors.json", import.meta.url), "utf8"))

function check(label, projection, points) {
  for (const [lon, lat, x, y] of points) {
    const [px, py] = project(projection, lon, lat)
    assert.ok(Math.abs(px - x) <= 0.01, `${label} ${lon},${lat}: x ${px} vs ${x}`)
    assert.ok(Math.abs(py - y) <= 0.01, `${label} ${lon},${lat}: y ${py} vs ${y}`)
  }
}

test("every base's own projection agrees with the Ruby vectors", () => {
  for (const [name, v] of Object.entries(vectors.bases)) check(name, v.projection, v.points)
})

test("the fixed projections cover all three types and both poles", () => {
  assert.deepEqual([...new Set(vectors.projections.map((p) => p.projection.type))].sort(), [...TYPES].sort())
  assert.deepEqual(vectors.projections.filter((p) => p.projection.type === "lambert_azimuthal").map((p) => p.projection.pole).sort(), ["north", "south"])
  for (const v of vectors.projections) check(v.projection.type + (v.projection.pole || ""), v.projection, v.points)
})

test("an unknown type or a lambert_azimuthal without a pole is refused", () => {
  assert.throws(() => rawProject("robinson", 0, 0), /unknown projection/)
  assert.throws(() => rawProject("lambert_azimuthal", 0, 0), /pole/)
})

test("north is up on mercator and the pole is the centre of the azimuthal view", () => {
  const m = { type: "mercator", scale: 100, tx: 0, ty: 0 }
  assert.ok(project(m, 0, 50)[1] < project(m, 0, 10)[1])
  const [x, y] = project({ type: "lambert_azimuthal", pole: "north", scale: 100, tx: 500, ty: 500 }, 77, 90)
  assert.ok(Math.abs(x - 500) < 1e-9 && Math.abs(y - 500) < 1e-9)
})
