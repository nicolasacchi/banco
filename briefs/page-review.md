---
name: page-review
version: 1
formats: banco.page_review/1
---

# Brief: review of a free page revision (version 1)

You review one revision of a free page as a subject expert and a careful reader of code, and write `banco.page_review/1`
(`config/banco/schemas/page_review.json`): eleven checklist points and findings by file. You are a session of the reviewer role, independent
from every author of the page and on a different model family from every author (`E-PROVIDER-NOT-ALLOWED`). A session that wrote any
revision of the page, or that already reviewed this revision, is refused (`E-SESSION-NOT-INDEPENDENT`).

Start with `banco status` and this brief. Open your session first:
`export BANCO_SESSION=$(banco session new --role reviewer --agent AGENT --model MODEL --id)`.
`banco page-review open REV` gives you the manifest, every file as text, the card that embeds the page, the validation report, and a plain
diff against the previous revision, computed by the server with no model. `banco page shots REV --dir D` writes the screenshots of every seed
(1280 and 390 pixels), the reduced-motion state and the three states of the scripted session: **look at every one**. You are never given the
course sources and must not read any; the page stands on its card. `banco page-review submit REV --file review.json` sends the result (use
`--dry-run` first). Keep your files in a scratch directory that only you own: `mktemp -d "$TMPDIR/pr-SUBJECT-XXXXXX"`. You report; you
never decide and never ask for a decision: the teacher tries the page and approves or sends back in the browser.

## The eleven points

1. Content correct: numbers and science; check some states by hand from the code.
2. Agrees with the card that embeds it: notation, words, colour roles.
3. `why_free_it` holds: could a component of the lesson have done this?
4. The first action is obvious, the instructions are short, everything works with the keyboard alone.
5. Accessibility: a text alternative, visible focus, contrast, no colour alone.
6. Reduced motion and the fallback are meaningful (the screenshots).
7. Performance is plausible; no render loop when idle.
8. The code uses only the allowed APIs and libraries: no hidden network or navigation, randomness only from `banco.random`, time only from `banco.now`.
9. No practice answer and no exercise final is in the page.
10. Readability and tone of the Italian texts; no personal data.
11. **No conditional behaviour without a visible reason.** Every branch on the seed, on a count of interactions or on elapsed time must be explained
    by what the page teaches. Read the diff: a revision that is "only a fix" must change only what the fix needs.

## The file

```json
{ "schema": "banco.page_review/1", "schema_version": 1, "revision": "REV",
  "checklist": [ { "id": 1, "result": "pass|fail|na", "evidence": "what you checked, in at least 4 words and not a stock phrase" }, "... eleven, in order" ],
  "findings": [ { "severity": "blocker|major|minor", "file": "main.mjs", "line": 12, "quote": "an exact substring of that file", "problem_it": "...", "fix_it": "..." } ] }
```

A point marked `fail` needs a finding. A blocker stops approval; a major needs a written reason from the teacher. `file` is a path of the
revision (`page.json` as `banco page-review open` shows it) and `quote` must be an exact substring of it (`E-QUOTE-NOT-FOUND`). Write
`problem_it` and `fix_it` in short, plain Italian.

## Public repository

Reviews stay in the database, but anything written to a file in the repository is public: say "the student" and "the teacher", with no names,
school, city or exam details.
