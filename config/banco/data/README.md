# Vetted data tables (D-270)

Facts of the world that a lesson shows (melting points, element symbols, climate normals, cell sizes, irregular verbs, Spanish
forms, Italian place names, the gazetteer of the ancient Mediterranean) are not typed by the author of a lesson: the author names a
row (`ref: bio/sizes.hair`, `station: brasilia`) and our code draws what the table holds. A table is a file `DOMAIN/NAME.yml` with its
JSON Schema `DOMAIN/NAME.schema.json` beside it.

Rules of a table (WAVE2-COMPONENTS 1.9):

- Every value has its source, in the row (`source`) or in a comment: a book, a standard, a dataset with its year. No value from memory.
- A second table is typed separately by another session; a unit test compares the two and checks the internal consistency.
- A model other than the author's reviews the table.
- A table changes only through a D entry.
- `bin/build-lesson-data` validates every table against its schema and compiles it into `app/javascript/lesson/data/DOMAIN-NAME.js`
  (generated; `--check` in CI). A data module is at most 20 KB gzip and loaded only by a card that uses it.
- Ruby reads a table through `Lessons::VettedData` (`E-LESSON-DATA` when a lesson names a row that does not exist).
- Content that is prose (the Costituzione, the codice civile) is not a table: it is a reference text the operator imports (D-074).

The 15 tables and their tracks are in the schemas (`x-banco-table`). The schemas are the contract of W2-0; the tables themselves are
content (phase C0) and arrive with the track that draws them.
