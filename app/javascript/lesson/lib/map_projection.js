// MapProjection: the JS twin of Maps::Geom (lib/maps/geom.rb), the projection of a banco-maps@1 base (T5, D-271).
// A base's `projection.type` is the authority and is one of equal_earth, lambert_azimuthal (with `pole`: "north" or "south") or
// mercator; x = tx + scale * ex, y = ty - scale * ey. Both twins run test/fixtures/maps/projection_vectors.json (to 0.01).
// No imports: pure, usable in the browser and under node --test.

export const TYPES = ["equal_earth", "lambert_azimuthal", "mercator"]
export const POLES = ["north", "south"]

const EE_A1 = 1.340264
const EE_A2 = -0.081106
const EE_A3 = 0.000893
const EE_A4 = 0.003796
const EE_M = Math.sqrt(3) / 2

const rad = (deg) => (deg * Math.PI) / 180

function equalEarth(lon, lat) {
  const l = rad(lon)
  const t = Math.asin(EE_M * Math.sin(rad(lat)))
  const t2 = t * t
  const t6 = t2 ** 3
  const x = (l * Math.cos(t)) / (EE_M * (EE_A1 + 3 * EE_A2 * t2 + t6 * (7 * EE_A3 + 9 * EE_A4 * t2)))
  const y = t * (EE_A1 + EE_A2 * t2 + t6 * (EE_A3 + EE_A4 * t2))
  return [x, y]
}

// Lambert azimuthal equal-area, polar aspect: 0 degrees points down in the north, up in the south.
function lambertAzimuthal(lon, lat, pole) {
  const l = rad(lon)
  if (pole === "north") {
    const r = 2 * Math.sin(rad(90 - lat) / 2)
    return [r * Math.sin(l), -r * Math.cos(l)]
  }
  const r = 2 * Math.sin(rad(90 + lat) / 2)
  return [r * Math.sin(l), r * Math.cos(l)]
}

// [x, y] with y up, in the projection's own unit.
export function rawProject(type, lon, lat, pole) {
  switch (type) {
    case "equal_earth": return equalEarth(lon, lat)
    case "mercator": return [rad(lon), Math.log(Math.tan(Math.PI / 4 + rad(lat) / 2))]
    case "lambert_azimuthal":
      if (!POLES.includes(pole)) throw new Error("lambert_azimuthal needs a pole (north or south)")
      return lambertAzimuthal(lon, lat, pole)
    default: throw new Error(`unknown projection ${type}`)
  }
}

// projection is a base's `projection` object: { type, scale, tx, ty, pole? }. Returns [x, y] in the viewBox.
export function project(projection, lon, lat) {
  const [px, py] = rawProject(projection.type, lon, lat, projection.pole)
  return [projection.tx + projection.scale * px, projection.ty - projection.scale * py]
}
