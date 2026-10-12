# Gallery: family `docs` (Documents and sources)

Status: built by T8 for W2-1 (the legal half of `source`, `reveal`, `oral`, and `document` with its frame and the `invoice` kind). The lesson that
shows them is `docs-lesson.md` (invented content, business subject: an invoice in two views, a legal source with its plain version, a reveal as a flip
card and as a crossroads, an oral). `test/system/docs_family_test.rb` renders it in Chrome at 1366 and 390 px (cream), takes the screenshots of the
look gate (`BANCO_SHOT_DIR`, `docs-<card>-<width>.png`), keeps the pieces' interactions and prints it. `test/lib/lessons/document_test.rb` and
`lesson/test/document.test.mjs` run the vectors of `test/fixtures/diagrams/types/document.json` both ways. The W2-2 halves stay as in the plan
(registry views held back as drafts).

## Shown (docs-lesson.md)

- `document` (diagram; available, batch w2-1, track T8)
  - `kind: invoice`, `view: sheet` (card 1, card 5 with two hidden rows) and `view: cascade` (card 2, five steps and the fence)
  - select targets: `zones`, `rows` (mode `select`: shapes carry `target`; the plumbing of the check is T1's)
  - `kind: contract`, `receipt`, `gazette`, `ballot`, `letter`, `assegno_bancario`, `assegno_circolare`, `cambiale_tratta`, `paghero`, `bonifico`, `ddt` (draft, w2-2: not drawn)
- `source` (block; available for `kind: legal`, batch w2-1, track T8): card 3, the plain words first, the switch, the marks, "Leggi con me"
  - `kind: written`, `iconographic`, `material` (draft, w2-2: not drawn)
- `reveal` (block; available): card 5 as a flip card, card 4 as the crossroads with options
- `oral` (block; available): card 7, the outline put in order, the model answer after the check, "Ora dilla tu"
- `image` (block; draft, schema draft, batch w2-2, track T8): not drawn
