# Charts and quantities (T6, D-279)

The chart family of lesson/2: `climograph`, `bar_model` (views `parts` and `percent`), `seats`, on one axis engine. `chart` and `scale` are W2-2.
This page is what an author and a reviewer need; the decision entry D-279 has the reasons.

## The axis engine (`app/javascript/lesson/diagrams/chart/axis.js`)

`linear`, `log`, `readCursor`, `legend`, `valueTable` on the frozen signatures; numbers are exact strings (`chart/format.js` writes them the
Italian way). A tick is dropped before a text is drawn smaller (A3). Tests: `app/javascript/lesson/test/chart_axis.test.mjs`.

## `climograph`

```yaml
::: diagram climograph
alt_it: "..."
station: geo/stations.brasilia      # or place_it + lat + temp + precip + source_it, inline
show: [bars, line, arid, range, total]   # default bars + line; one scale at a time in the states
compare: {station: geo/stations.cape_town}   # a second, dashed temperature line
read: true                          # the stepper "Mese" and the live line (never in a try exercise: L7)
states: [{show: [bars], op_it: "Prima la pioggia"}, {show: [bars, line], op_it: "Poi la temperatura"}]
:::
```

- Computed by us, never typed: the arid months (P <= 2T), the total, the range, the warmest and the coldest month.
- Rain above 100 mm is drawn in a marked band with a smaller scale; the legend says so.
- Stations: `config/banco/data/geo/stations.yml` (21), ids in `Lessons::VettedData.table("geo/stations")`. An id that is not there is `E-LESSON-DATA`.
  `rome_ciampino` is not there on purpose (its primary source lacks three months of rain).
- Borderline arid months (a table's flags say which): never make a check depend on them. The checks to avoid for the stations in use are in
  `config/banco/data/geo/stations_expected.yml` (`arid_differs`).

## `bar_model`

```yaml
::: diagram bar_model
view: parts                          # bars: [{label_it, parts: [{value, label_it, role?, hidden?}]}], total: {value, label_it?}
:::
::: diagram bar_model
view: percent                        # exactly one of base and anchor; marks, hide, chain, unit
base: '1860,00'
unit: euro
marks: [{pct: '22', label_it: "IVA", role: tax}]
hide: ['100']                        # the percents whose value is a blank: served as null, drawn "?"
chain: [{pct: '90'}, {pct: '95'}]    # a new line per step, to scale
:::
```

A hidden part needs `total` (its width is the total less the parts that show) and a bar hides one part. A hidden value never reaches the page
(`test/lib/lessons/chart_types_test.rb`, the sentinel property).

## `seats`

```yaml
::: diagram seats
layout: hemicycle                    # or grid (at most 200 seats; 10 or 20 columns)
seats: 400
groups: [{label_it: "Primo gruppo", seats: 120, role: ...}]
present: 300
"yes": 170                           # a bare yes: is read as the field yes (the YAML library would make it true)
thresholds: [legal_number, present_majority]
try: {present: [280, 310], yes: [150, 200]}   # two sliders, each with - and +
:::
```

Integers: numero legale `seats/2 + 1`, maggioranza dei presenti `present/2 + 1` (a tie fails), assoluta `seats/2 + 1`, due terzi `ceil(2 seats/3)`,
tre quinti `ceil(3 seats/5)`. A check never asks a number the readout can show inside the declared ranges (L5): ask another number, or say in
`reachable_ok_it` why the reach does not give it away.

## Rules enforced for the family (`Lessons::Diagrams.answer_leaks`, `Lesson2Checks`)

`W-CHECK-ANSWER-IN-DIAGRAM` (L4), `E-CHECK-ANSWER-BY-SIMULATION` (L5), `E-DIAGRAM-REACHABLE-CAP` (more than 500 values on a card with a check),
L7 as `E-LESSON-BLOCK` (no `read` or `try` in a figure of the try card).

## Files

`app/javascript/lesson/diagrams/chart/*`, `diagrams/controls.js`, `lib/lessons/diagrams/{climograph,bar_model,seats,chart_support}.rb`,
`app/assets/stylesheets/lesson/chart.css`, `config/locales/lesson_chart.it.yml`, `test/fixtures/diagrams/types/{climograph,bar_model,seats}.json`,
`test/fixtures/lesson2/{climate,seats}.json`, `test/fixtures/lesson2/gallery/chart.md`, `test/system/lesson_chart_gallery_test.rb`.
