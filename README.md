# banco

A study app for one private-candidate student preparing an Italian upper-secondary school exam, with a deterministic engine (no LLM in the student's path) and a Go CLI for the teacher's AI agent.

Work in progress: the first slice is the entry diagnosis.

## Development

```bash
bundle config set --local path vendor/bundle && bundle install
bin/rails test                  # unit and integration tests
(cd cli && go test ./...)       # CLI tests
bin/hygiene                     # public-repository checks
bundle exec puma -C config/puma.rb   # web 3000, API 3100, harness 3200
```

See `AGENTS.md` for the rules and layout and `docs/decisions.md` for every decision.
