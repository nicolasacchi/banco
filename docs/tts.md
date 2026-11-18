# TTS service (`services/tts`)

A small Python service in its own container that turns lesson text into MP3 with
[Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (`kokoro-onnx`, CPU). The Rails app calls it
only to generate the «Ascolta» clips of a lesson revision ahead of time; the student's browser never
talks to it (it plays the stored clips Rails serves) and nothing is synthesized at the student's request.

## What it sees

Only lesson text: the segments the teacher-approved lesson says. It never receives student data
(no names, answers, ledger rows, tokens), keeps no state, writes no files, and logs one line per
request: `synthesize voice=<v> chars=<n> ms=<n> bytes=<n>`: never the text. Firm rule 1 holds: no model in the student's path.

## API

Base URL in Rails: `ENV["BANCO_TTS_URL"]` (e.g. `http://banco-tts:8000`); unset means no generation.
The service is reachable on the internal compose network only (no Traefik labels).

`POST /synthesize` with JSON `{"text": "...", "voice": "im_nicola", "lang": "it", "speed": 1.0}`:

- `200 audio/mpeg`: mono MP3, ~64 kbps, from the 24 kHz model output (ffmpeg).
- `400 application/json` `{"error": "..."}` for: invalid JSON or body over 16 KiB; unknown voice;
  `lang` not the voice's language; `text` missing, blank or over 1000 characters; `speed` not a number
  in 0.5..2.0 (`speed` is optional, default 1.0).
- `500` `{"error": "synthesis failed"}` if the model or ffmpeg fails.

`GET /health` → `{"ok": true, "engine": "kokoro-82m-v1.0", "voices": [...]}`.

One synthesis runs at a time (a lock); concurrent requests wait. On a CPU a sentence takes about a second.

| voice | lang | espeak code |
|-------|------|-------------|
| `im_nicola` | `it` | `it` |
| `af_heart`, `af_bella` | `en` | `en-us` |
| `ef_dora`, `em_alex` | `es` | `es` |

The voice list is fixed in `server.py` and mirrors `server.voices` in `config/banco/voices.yml`.
Which voice a segment gets, and the clip key, are decided by Rails (D-359), not by this service.

## Models and licences

Kokoro-82M v1.0 is Apache-2.0 (model weights and the `kokoro-onnx` runtime, both Apache-2.0; espeak-ng,
used for phonemes through `espeakng-loader`, is GPL-3.0-or-later and runs as a separate library inside this
container only). Models are **not in git**:

- `kokoro-v1.0.onnx` (325 MB), `voices-v1.0.bin` (28 MB), from the
  [`model-files-v1.0` release](https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0)
  of thewh1teagle/kokoro-onnx.
- `services/tts/models.sha256` pins their SHA-256. The server verifies both files at start and exits on a
  mismatch or a missing file.
- `services/tts/fetch-models.sh [DIR]` downloads them (default `./models`) and runs `sha256sum -c`.

On the host they live in `/home/nik/traefik/data/banco-tts/models`, mounted read-only at `/models`
(`BANCO_TTS_MODELS`, default `/models`).

## Build and run

```sh
services/tts/fetch-models.sh /home/nik/traefik/data/banco-tts/models
docker build -t banco-tts services/tts
docker run --rm -p 127.0.0.1:8000:8000 \
  -v /home/nik/traefik/data/banco-tts/models:/models:ro banco-tts
curl -s localhost:8000/health
curl -s -o ciao.mp3 localhost:8000/synthesize -d '{"text":"Buongiorno.","voice":"im_nicola","lang":"it"}'
```

The image is `python:3.12-slim` + ffmpeg, pinned pip versions (`requirements.txt`), runs as a non-root user,
exposes 8000 and has a `HEALTHCHECK` on `/health` (60 s start period: the checksum pass reads 350 MB).

## Tests

No model, no network: a fake synthesizer stands in for Kokoro.

```sh
cd services/tts && python3 -m unittest test_server
```

They cover request validation, voice/language mismatch, the HTTP handler, the one-at-a-time lock, the log line
(no text) and the checksum refusal. The ffmpeg encoder test runs only where numpy and ffmpeg are present.

## Rails: the clips of the lessons (D-359)

How banco uses the service above. «Ascolta» plays a file made ahead of time; nothing is synthesised when the student asks (firm rule 1: the text is
what the teacher approved, made once, stored by content).

**The voices** (`config/banco/voices.yml`, block `server:`, copied by `bin/build-lesson-types` into the generated `lesson/voices.js` as `voices.server`):
engine `kokoro-82m-v1.0`; Italian `im_nicola`; English `af_heart`, `af_bella`; Spanish `ef_dora`, `em_alex`; `clip_path: /speech/clips`, `format: mp3`.
A segment is `{lang, text, voice}` (`voice` the speaker number, 1 when none). Its server voice is `voices[lang][(voice - 1) % list.size]`: in a dialogue
speaker 1 has the first voice, speaker 2 the second, then they alternate; everything else uses the first. Latin (`la`) has no server voice and no clip.

**The key** of a clip is the lowercase hex SHA-256 of the UTF-8 string `"<engine>|<voice name>|<text>"` (`Speech::Key`; `lesson/speech_clips.js`
in the browser). `test/fixtures/speech/keys.json` holds vectors (accents, quotes, «», an em dash) that both sides test. Changing the engine, a voice
name or a character of the text makes a new key, so the old clip is simply not asked for any more. URL: `/speech/clips/<key>.mp3`.

**Where the segments come from.** The render check (`RenderLessonRevisionJob`, D-249) draws every card in every state in the server's Chrome; its host
(`lesson/render_host.js`, `lesson/speech_segments.js`) collects what each speak path would say: `speechOf` of each card in each state (every figure
state, every exercise of «Prova tu», the opened parts), the dialogues' `segmentsOf` (with the speakers' voices), the speaker beside each `[[en:..]]` /
`[[es:..]]` word and the text of each `listen` check. They are stored with the verdict (`lesson_renders.segments_json`, written with the row).
The check draws the lesson as the student's projection with the fixed seed `preview`: a sentence built from a student's own numbers has no clip, and
the browser then falls back to an accepted device voice (D-267) or skips it. A tiles check's «Ascolta la frase» says the sentence the student built:
no clip either.

**Making them.** A render that passes enqueues `SpeakLessonRevisionJob` (queue `speech`, behind the ordinary jobs; `config/queue.yml`). For each
segment of a language with server voices (`Speech::Plan`): the clip is skipped when its file exists, else `POST /synthesize` through `Speech::Client`
(`BANCO_TTS_URL`, e.g. `http://banco-tts:8000`), the MP3 is stored at `storage/speech_clips/<key[0,2]>/<key>.mp3` (`BANCO_SPEECH_CLIPS_DIR`
overrides) and an append-only `speech_clips` row is added (key, engine, voice, lang, bytes, duration_ms, created_at). One clip failing does not stop the
others; a service that is down ends the run after three failures in a row and the job is tried again (5, 10, 15 … minutes, six attempts), the clips
already made being skipped; a clip the service refuses (400) is logged and left. Text longer than the service's 1000 characters has no clip. The service
refuses a voice that does not speak the language (`lang` must match the voice) and takes `speed` from 0.5 to 2.0 (banco asks for 1.0: «Più lento» is the
browser's `playbackRate`). Without `BANCO_TTS_URL` nothing is made and the log says so. `BANCO_TTS_STUB=1` (development, CI) uses a deterministic stand-in.

**Serving.** `GET /speech/clips/:key.mp3` on the web listener (student, preview, teacher, guest) and the view listener: a 64-hex key only, `audio/mpeg`,
`Cache-Control: public, max-age=31536000, immutable`, byte ranges (Safari asks for them), 404 when the file is missing, nothing recorded
(`SpeechClipsController`).

**Backfill.** `bin/rails banco:speech:backfill` lists, for the lesson revisions the official student sees now (`Course::Catalog`) and the approved ones,
what each needs: clips to make, nothing, or a new render check to collect the segments (revisions drawn before D-359). `CONFIRM=1` enqueues the jobs and
the samples of «Prova le voci» (the first sentence of `lesson2.voices.sentences.<lang>`, one clip per server voice, `SpeakSamplesJob`).

**The teacher** sees one line in the lesson box of the topic page: «Audio: N di M frasi pronte».

**Storage.** `storage/speech_clips` is derived and may be deleted: the backfill makes the files again (the `speech_clips` rows stay and are not repeated).
