# banco-maps@1: provenance

Built by `bin/build-maps` from the trimmed sources committed in `config/banco/data/geo/source/`
(Natural Earth v5.1.2, World Bank) and the tables `config/banco/data/geo/` and
`config/banco/data/history/`. The build is offline and deterministic; `bin/build-maps --check` (and CI)
say whether this directory equals the build.

## Sources and licences

| Data | Used for | Licence | Upstream |
|---|---|---|---|
| Natural Earth v5.1.2 1:110m and 1:50m (countries, land, lakes, rivers, populated places) and 1:10m admin-1 (Italy, Greece, Turkey) | every base: borders, coasts, lakes, rivers, capitals and cities, the twenty regions of Italy, the units the ancient regions are composed from | public domain, no attribution needed ("Made with Natural Earth" is courteous) | https://www.naturalearthdata.com/about/terms-of-use/ |
| Pleiades gazetteer of ancient places, dump 2026-10-11 | `mediterraneo_antico`: the coordinates of 69 places (`history/places`) | CC BY 3.0: (c) The Contributors of Pleiades, https://pleiades.stoa.org (attribution is on the card: "Luoghi: Pleiades") | https://pleiades.stoa.org/ |
| World Bank World Development Indicators (area AG.SRF.TOTL.K2 from FAO, 2021; population SP.POP.TOTL, 2023) | `geo/countries` (not in the base files) | CC BY 4.0 | https://data.worldbank.org/ |

## Not used, and why

- **Ancient World Mapping Center (AWMC) GeoJSON** (provinces of the Roman Empire in 200 CE and 60 BCE, coastlines).
  Its licence is the Open Database Licence 1.0 (ODbL, share-alike: a derived database must be offered under the
  same licence), and the province files are unnamed polygons and linework, so naming them would be drawing
  them by hand. The regions of `mediterraneo_antico` are instead composed from Natural Earth units
  (`history/regions`), each with its note on what is missing. If the operator wants the AWMC shapes, that is
  a D entry about the licence first.
- The coast of `mediterraneo_antico` is today's coast (Natural Earth 1:50m land), not the ancient one: the
  deltas of the Nile, Po and Rhone and the harbours that have silted up are not drawn.

## Approximate

The regions of `mediterraneo_antico` are approximations: whole modern countries or provinces, or a modern
country cut by a box (`history/regions` says which, with a line on what the region misses). The template
prints "Confini approssimativi" on every such map. A region is checked against a published atlas page by a
second session and by the teacher in the topic review before a lesson depends on it.

## Files

One module per base (`export default {...}`; fill rule evenodd): areas with `d` (path), `anchor` and `bbox`,
groups (continents, Italy), oceans, lakes (`water`), rivers (`lines`), cities (`places`), the graticule
(equator, tropics at 23.4 degrees, polar circles, Greenwich) and the projection (`type`, `scale`, `tx`,
`ty`: x = tx + scale * ex, y = ty - scale * ey; Equal Earth for the world and the continents, Lambert
azimuthal equal-area for the poles). `test/fixtures/maps/projection_vectors.json` holds sample points for the
JavaScript twin of the projection. SHA256SUMS lists every file.
