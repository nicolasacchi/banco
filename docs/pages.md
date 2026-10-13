# Free pages (release 2, D-290)

A free page is a small interactive scene written by an agent (a 3D solid, a simulation) that the lesson's components cannot do. It runs in the
browser inside a sandboxed iframe on its own origin, is validated in the server's Chrome on eight seeds, reviewed by an independent session,
and approved by the teacher for what it shows, never for its code. It never counts for a skill state. Design: SPEC B (private); decision D-262
and D-290.

## Flow

`banco page open KEY` (the card text and a skeleton) -> `banco page submit DIR --dry-run` -> submit -> the job validates in Chrome
(`banco page status|shots`) -> `banco page-review` by another model family -> the lesson pins the page (`::: page`, `revision: latest`, in an
extra card beside a still visual) -> the teacher ticks "Ho provato ..." in `approve_topic`.

## Switch and storage

`BANCO_PAGES_ENABLED=1` turns the production mount on (default 0: the mount answers 404 and a card shows poster, caption and fallback without a
button). Page bytes are the source of truth: `BANCO_PAGES_DIR` (default `$BANCO_DATA_DIR/pages`); posters and screenshots `BANCO_PAGE_SHOTS_DIR`
(default `$BANCO_DATA_DIR/page_shots`). Both are under the bind-mounted data volume in production.

## R6: the infrastructure for the lead (`~/traefik`, not done by T11)

1. DNS: `pages.banco.scc.im` (same target as `banco.scc.im`).
2. Compose env of `banco`: `PAGES_PORT=3300`, `BANCO_PAGES_ORIGIN=https://pages.banco.scc.im`, `BANCO_APP_ORIGIN=https://banco.scc.im`,
   `BANCO_PAGES_ENABLED=0` until the matrix passes. Alias `banco-pages-internal` on `banco-internal` beside `banco-harness`. Port 3300 not published.
3. Router labels on `banco` (no Authelia; the bytes are content addressed and public course material):
   `traefik.http.routers.banco-pages.rule=Host(\`pages.banco.scc.im\`)`, `.entrypoints=websecure`, `.tls.certresolver=myresolver`,
   `.service=banco-pages`, `.middlewares=banco-pages-strip@docker,sec-headers@docker`;
   `traefik.http.services.banco-pages.loadbalancer.server.port=3300` (the Traefik network for the router is `banco-edge`, as the other router);
   `traefik.http.middlewares.banco-pages-strip.headers.customrequestheaders.Cookie=` and `...Authorization=` (empty values strip the headers).
   Check `sec-headers` does not set a `Content-Security-Policy` or `X-Frame-Options` that overrides the app's (the pages app sends its own).
4. `banco-chrome`: `--host-resolver-rules=MAP * ~NOTFOUND,EXCLUDE banco-harness,EXCLUDE banco-pages-internal`; add `--enable-unsafe-swiftshader`
   if a WebGL2 context is null (the self-test and the `webgl: true` pages tell).
5. RUNBOOK: the new listener, the router, `curl -sI https://pages.banco.scc.im/kit/banco-page@1.0/bridge.mjs` (expect the headers of
   `Banco::PagesApp`, `access-control-allow-origin: *`, no `set-cookie`), the cookie check (`banco health`: `pages.cookie_headers_seen` must stay 0),
   the weekly `bin/purge-lesson-shots` and the page shots purge (`PageShots.purge`).
6. Browser matrix before any student sees a page: `CONFIRM=1 bin/rails banco:pages_selftest` in the container, then open
   `/teacher/pages/selftest` on Chrome desktop, Firefox desktop, Safari on iPadOS/iOS and Chrome on Android (with `BANCO_PAGES_ENABLED=1`) and write
   each result table in the RUNBOOK. Every "bloccato" row must hold everywhere. Expected: Firefox sends the cookie header, which the Traefik strip
   removes; WebRTC is covered by the kit stub only, not by the CSP.
7. Traefik check: `curl -s -H 'Cookie: probe=1' https://<pages origin>/kit/banco-page@1.0/bridge.mjs` must leave `banco health` with
   `pages.cookie_headers_seen` 0 (the strip removed the header before the app). The counter is per process and starts again at 0 at every restart,
   so run this curl after each restart and deploy, not only once.

## New kit versions

A released kit directory never changes (`lib/pages_kit/LOCK`, checked by `test/lib/pages_kit_test.rb`). A fix is `1.1`; then `bin/pages-kit-lock` and
`bin/revalidate-pages --kit 1.1`. The pages app serves a revision only with a kit of one of its passed validations.

## Three.js is vendored once

`vendor/pages/three@0.186.1` is the one copy of three for pages; if T10 needs three in `public/vendor`, it links or reuses this copy rather than adding a second one of about 2 MB.
