## Teacher views

The bot reads what the teacher reads in the browser, and what the student sees, without a browser (D-328). Five read-only
endpoints, answered to every token role (`bot_read`, `teacher`, the content agents, `ci`); each has a CLI command. Nothing
here writes: reading a page through the API never records that the teacher read it (`teacher_viewed_topic`,
`teacher_saw_exercise`), so the approval gate's «page opened» and «exercises seen» conditions are still the teacher's, in the
browser (or the operator's attestation at the console).

```bash
export BANCO_URL=https://api.banco.scc.im          # a bare host (api.banco.scc.im) is https too; no trailing slash needed
export BANCO_TOKEN=bnc_...                          # the token the operator issued; it expires, ask for a new one
banco teacher home
```

Every answer is JSON on stdout; an error is `{code, field, message, next}` on stderr with the exit code (2 usage, 3 not found
or invalid, 4 token, 6 network or server). The Italian text the pages show comes in members ending `_it`, next to the key or
the English reason it words (`badge` and `badge_it`, `gate_reasons` and `gate_reasons_it`). Students are named by key only
(`student` is the official one, any other key a trial student).

| Command | Request | Page it mirrors |
|---|---|---|
| `banco teacher home [--student KEY]` | `GET /api/v1/teacher/home[?student=KEY]` | `/teacher` (Cruscotto) |
| `banco teacher course SUBJECT [--only-ready]` | `GET /api/v1/teacher/subjects/:subject/course[?only=ready]` | `/teacher/subjects/:key/course` |
| `banco teacher topic SUBJECT TOPIC [--lesson]` | `GET /api/v1/teacher/subjects/:subject/topics/:topic[?lesson=full]` | `/teacher/subjects/:key/topics/:topic` |
| `banco teacher test SUBJECT` | `GET /api/v1/teacher/subjects/:subject/test` | `/teacher/subjects/:key/test` |
| `banco progress [--student KEY]` | `GET /api/v1/students/:student/progress` | the student's Materia and Diagnosi |

An unknown subject, topic or student is 404 `E-NOT-FOUND`. A subject with no course map or no entry test answers 200 with
`"present": false`.

### `banco teacher home`

What waits for the teacher, subject by subject: the counts of the strip, the to-do list in the order of the page (findings,
graphs, tests ready, tests blocked, topics, corrections, release), one row per subject (stage, what waits, the course line,
what each student did there) and the state of the release.

```json
{
  "student": "student",
  "counts": { "findings": 0, "corrections": 0, "topics": 1, "comments": 2 },
  "todos": [
    { "kind": "topics", "subject": "geography", "count": 1, "clear_findings": null, "text_it": "1 argomento da approvare", "page": "/teacher/subjects/geography/course?only=ready" }
  ],
  "subjects": [
    {
      "key": "geography", "name_it": "Geografia", "stage": "approved", "has_graph": true, "has_blueprint": true,
      "items": { "total": 26, "passed": 26, "sent_back": 0 }, "waiting": [], "blocked_it": null, "clear_findings": 0, "minutes": 12,
      "course": { "approved": 25, "total": 26, "open": true, "awaiting": 1, "in_review": 0, "missing": 0 },
      "students": [ { "student": "student", "official": true, "diagnosis_it": "Fatto", "last_activity_at": "2026-11-13T17:02:11Z", "practised_skills": 3 } ]
    }
  ],
  "state": { "subjects_waiting": 1, "corrections": 0, "minutes_total": 22, "released": true, "consent_recorded": true, "warmup_complete": false,
             "approvals": { "done": 11, "total": 11 } }
}
```

`waiting` rows are `{code, count, text_it}` (`graph_to_approve`, `findings`, `sent_back`, `test_to_approve`). `?student=KEY` shows a
trial student's corrections and activity, as the page's `?student=` does.

### `banco teacher course SUBJECT`

The path of the subject: the topics of the programme in map order as numbered steps, the extra topics («Fuori programma»)
apart, the release state, the warnings and the new skills of the map. `--only-ready` keeps the topics that wait for the teacher.

```json
{
  "subject": { "key": "geography", "name_it": "Geografia" }, "present": true, "revision": { "id": 36, "seq": 5 },
  "open": true, "released_revision_id": 36, "released_latest": true,
  "counts": { "in_map": 26, "approved": 25, "awaiting": 1, "missing": 0, "ready": 1 },
  "notes_it": ["Ordine consigliato: ..."], "warnings": [],
  "topics": [
    {
      "number": 1, "key": "ponte.geography.world-map-coordinates", "kind": "ponte", "extra": false, "title_it": "Orientarsi nel mondo", "term": 1, "minutes": 30,
      "skills": ["geography.coordinates-hemispheres"], "after": [],
      "stage": "awaiting_teacher", "badge": "ready", "badge_it": "Pronto per te", "missing_it": "Manca solo la tua revisione.", "ready": true,
      "lesson_written": true, "exercises": 6, "open_findings": 1,
      "latest_revision": { "id": 448, "seq": 6 }, "approved_revision_id": null, "attested_it": null,
      "gate_reasons": [], "gate_reasons_it": [],
      "progress": [ { "student": "student", "tries": 0, "skills_done": 0, "skills_total": 1 } ],
      "page": "/teacher/subjects/geography/topics/ponte.geography.world-map-coordinates"
    }
  ],
  "extra_topics": [],
  "release": { "releasable": false, "checks": [ { "name": "graph", "done": true }, { "name": "topic", "done": true } ], "reasons": [], "reasons_it": [] },
  "skills": [ { "key": "geography.coordinates-hemispheres", "label_it": "...", "layer": "core", "refs": [], "errors": [] } ]
}
```

`stage` is the one `banco topics list` uses (`missing`, `in_review`, `awaiting_teacher`, `approved`, `approved_newer_pending`) and `badge`
the page's plain word (`missing`, `working`, `ready`, `approved`, `open`, `newer`). `progress` is the official student's when the
course is open, else the trial students'.

### `banco teacher topic SUBJECT TOPIC`

One topic as the teacher reviews it (the four steps of the page): the lesson's facts, the lesson reviews, the exercises with
four stored samples each, every finding with its state, and the approval with what is still missing. The lesson's text is large
and comes only with `--lesson` (`lesson.body`, the same lesson `banco lesson open` gives).

```json
{
  "subject": { "key": "geography", "name_it": "Geografia" }, "key": "ponte.geography.world-map-coordinates", "present": true, "extra": false, "title_it": "Orientarsi nel mondo",
  "latest": { "id": 448, "seq": 6, "intro_it": "..." },
  "approved": { "latest": false, "revision_id": null, "seq": null }, "attested_it": null,
  "map_entry": { "key": "...", "kind": "ponte", "skills": ["..."], "minutes": 30, "term": 1, "after": [] },
  "lesson": { "revision_id": 526, "seq": 4, "schema": "banco.lesson/2", "kind": "ponte", "title_it": "...", "minutes": 30, "scope": "studied", "calculator": false,
              "uses": [], "refs": [], "render": { "state": "passed", "count": 12 }, "cards": 12 },
  "lesson_reviews": [ { "id": 31, "session_id": 772, "model": "gpt-5.2", "declared_model": "gpt-5.2", "independent": true, "results": { "pass": 8, "na": 1 }, "checklist": [], "recomputed": [], "findings": ["L31-1"] } ],
  "exercises": [
    {
      "number": 1, "item": "geography.coordinates-1", "revision_id": 901, "seq": 2, "skill": "geography.coordinates-hemispheres", "skill_label_it": "...", "level": 1,
      "purpose_it": "...", "seen": false,
      "card": { "gate": { "approvable": true, "reasons": [], "reasons_it": [] }, "catalogue": [], "review": { "pass": 12, "fail": 0, "failed": [], "by": { "session_id": 773, "model": "gpt-5.2", "independent": true } },
                "blind_solve": { "ok": 4, "total": 4, "mismatches": [], "by": {} }, "send_backs": [], "findings": [] },
      "samples": [ { "number": 1, "stem": "...", "choices": {}, "key": "...", "errors": [], "hints": [], "steps": [], "final": null } ]
    }
  ],
  "findings": {
    "lesson": [ { "id": "L31-1", "severity": "minor", "place_it": "Scheda 3: ...", "quote": "...", "problem_it": "...", "fix_it": "...", "response": null } ],
    "items": [ { "item": "geography.coordinates-1", "revision_id": 901, "findings": [ { "id": 5512, "severity": "major", "source": "review", "instance": null, "quote": "...", "problem_it": "...", "fix_it": "...",
               "disposition": null, "new_revision_expected": false, "closure": null, "evidence": null, "response": null,
               "opinion": { "state": "clear", "verdict": "finding_right", "first": { "note_it": "..." }, "history": [] } } ] } ],
    "count": 2, "clear": false
  },
  "send_backs": [], "lesson_sent_back": false,
  "steps": { "lesson_read": false, "exercises_seen": false, "findings_clear": false, "approved": false },
  "approval": {
    "approvable": false, "gate_approvable": false, "reasons": ["..."], "reasons_it": ["..."],
    "checks": [ { "name": "map", "done": true, "reasons_it": [] }, { "name": "viewed", "done": false, "reasons_it": ["..."] } ],
    "other_reasons_it": [], "needs_reason": false
  },
  "pages": [], "next_ready": "ripasso.geography.europe-map"
}
```

`opinion.state` is `none`, `clear` (the third reviewer says `author_right` or `finding_right`) or `unclear`; `disposition` is the
teacher's decision on the finding (`dismissed`, `fix_requested`) or `null`. `steps` are the page's progress bar: the teacher's
reading of the lesson and of the exercises (recorded by the browser only), the findings clear, the topic approved.
`approval.checks` is the page's checklist of the last step, each missing condition in the teacher's words.

### `banco teacher test SUBJECT`

The entry test as the teacher approves it: one row per skill with its pinned items (the same card as above, without samples), the
blocker and major findings nobody has decided, the settings the author declared, the formula sheet and the engine's two scripted
traces (all right, all wrong).

```json
{
  "subject": { "key": "geography", "name_it": "Geografia" }, "present": true,
  "blueprint": { "id": 45, "seq": 5, "pinned_items": 26 }, "approved": false,
  "approval": { "approvable": true, "reasons": [], "reasons_it": [] }, "attested_it": null,
  "skills": [ { "skill": "geography.coordinates-hemispheres", "label_it": "...", "role": "entry", "items": [ { "item": "...", "revision_id": 901, "seq": 2, "gate": {}, "findings": [] } ],
                "item_revision_ids": [901], "not_assessed_reason_it": null, "redo_reserve": null, "choice_only_reason_it": null, "reviewed": true, "open_findings": 0 } ],
  "open_findings": [ { "id": 5512, "severity": "major", "skill": "...", "label_it": "...", "item": "...", "instance": null, "problem_it": "...", "opinion": {} } ],
  "clear_open_findings": [5512],
  "settings": { "not_measured_it": "...", "intro_note_it": "...", "calculator": "yes", "budget": { "sitting_minutes": 30, "sittings": 2 }, "depends_on_subjects": [], "kind_overrides": [] },
  "formula_sheet": { "text": null, "offerable": false, "enabled": false },
  "traces": [ { "script": "all-correct", "end_reason": "complete", "served": 20, "minutes": 28, "sittings": 1, "states": { "demonstrated": 11 } } ]
}
```

### `banco progress`

What the student sees, for the official student or `--student KEY`: per subject with a visible course the topics of the programme
and the extra topics (each `done`, `in_progress` or `todo`, the same word as on Materia), the progress tallies Materie and Materia show
(`Course::StudentView#progress`), the state of each skill, and the entry test of every subject in the student's list (the Diagnosi page).

```json
{
  "student": { "key": "student", "official": true },
  "overall": { "programme": { "total": 19, "done": 4, "in_progress": 1, "missing": 15, "percent": 21 }, "extra": { "total": 7, "done": 0, "in_progress": 0, "missing": 7, "percent": 0 } },
  "subjects": [
    {
      "key": "geography", "name_it": "Geografia", "released": true, "mode": "official", "course_revision_id": 36,
      "topics": [ { "key": "ponte.geography.world-map-coordinates", "kind": "ponte", "title_it": "...", "term": 1, "minutes": 30, "skills": ["..."], "after": [],
                    "status": "in_progress", "lesson_read": true, "to_recover": false, "approved": true } ],
      "extra_topics": [ { "key": "extra.geography.europe", "status": "todo" } ],
      "programme": { "total": 19, "done": 4, "in_progress": 1, "missing": 15, "percent": 21 },
      "extra": { "total": 7, "done": 0, "in_progress": 0, "missing": 7, "percent": 0 },
      "entry_test": { "subject": "geography", "name_it": "Geografia", "status": "completed", "done": true, "startable": false, "suggested": false, "label_it": "Fatto", "run_id": 412 },
      "skills": [ { "key": "geography.coordinates-hemispheres", "label_it": "...", "state": "in_study", "since": "2026-11-12T09:00:00Z" } ],
      "skills_without_topic": []
    }
  ],
  "closed_subjects": [],
  "entry_tests": [ { "subject": "math", "name_it": "Matematica", "status": "continue_next_day", "done": false, "startable": true, "suggested": true, "label_it": "Resta una parte da fare", "run_id": 412 } ]
}
```

`programme` counts the topics of the programme (mandatory) and `extra` the extra ones (optional), as Materie and Materia show them: `done`
is every skill of the topic demonstrated, `in_progress` a topic started and not done, `missing` every topic not done (so it includes
the ones in progress), `percent` is `done` over `total`, rounded down. `overall` sums the visible subjects (Oggi's «Il tuo percorso»).
`entry_test` is the subject's row of `entry_tests` (`null` when the subject has no test in the student's list); `skills[].state` follows the
practice rules (`not_seen` when nothing is known). `closed_subjects` are the subjects whose course the teacher withdrew after opening it. The
official student sees no subject before the teacher releases its course.

### Errors

| Code | Status | When |
|---|---|---|
| `E-AUTH` | 401 | no token, a wrong one, an expired one or a revoked one (the server does not say which; ask the operator for a new token) |
| `E-NOT-FOUND` | 404 | unknown subject, topic, or student key |

The CLI turns the 401 into «the token is wrong, expired (tokens last 90 days by default) or revoked» and names where to get a new
one. `E-URL` (exit 2, nothing sent) is a `BANCO_URL` that is not `http(s)://host[:port][/prefix]` or a bare host; `E-CONTRACT`
(exit 6) is a CLI whose embedded contract differs from the server's: take the release build that matches the server.

### Rate limit

The edge (Traefik) limits each client IP to an average of 10 requests per second with a burst of 30; beyond that the answer is 429
without reaching banco. A topic or test read runs the page's own work (a few seconds in the worst case): read it once and keep the
answer, do not poll it.

### What these endpoints never do

They never write: no decision, no comment, no «read» event, no approval of a page by opening it. They show no student's name (keys
only) and no student's answer. They never run agent code. A bot that needs the teacher's decisions uses the teacher token and the
decision endpoints, not these.

### The release build of the CLI

`bin/build-cli-dist` (POSIX sh, needs Go) tests the CLI and cross-compiles it for linux, darwin and windows on amd64 and arm64 into
`dist/` (git-ignored) with `dist/SHA256SUMS`; the version is stamped from git (`banco version` prints
`cli_version` as `<base>+<commit>`, with `.dirty` if `cli/` or `contract/` had uncommitted changes). Copy the file for the bot's
platform, check it with `sha256sum -c SHA256SUMS`, make it executable and put it on the `PATH` as `banco`.
