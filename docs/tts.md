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
