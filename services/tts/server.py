"""banco TTS service: lesson text in, MP3 out, Kokoro-82M on CPU.

POST /synthesize  {"text", "voice", "lang", "speed"} -> 200 audio/mpeg | 400 JSON
GET  /health      -> {"ok", "engine", "voices"}

The service only ever sees lesson text sent by the Rails app's clip generator; it keeps no state
and logs one line per request (voice, chars, ms), never the text.
"""
import hashlib
import json
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENGINE = "kokoro-82m-v1.0"
MAX_CHARS = 1000
MAX_BODY_BYTES = 16 * 1024
MIN_SPEED, MAX_SPEED = 0.5, 2.0

# voice -> request language. Same five voices as config/banco/voices.yml `server.voices`.
VOICES = {
    "im_nicola": "it",
    "af_heart": "en",
    "af_bella": "en",
    "ef_dora": "es",
    "em_alex": "es",
}
# request language -> espeak-ng language code used by kokoro-onnx.
KOKORO_LANG = {"it": "it", "en": "en-us", "es": "es"}

MODEL_FILES = ("kokoro-v1.0.onnx", "voices-v1.0.bin")


class BadRequest(Exception):
    pass


def validate(payload):
    """Returns (text, voice, lang, speed) or raises BadRequest with a message."""
    if not isinstance(payload, dict):
        raise BadRequest("body must be a JSON object")

    text = payload.get("text")
    if not isinstance(text, str) or not text.strip():
        raise BadRequest("text must be a non-empty string")
    if len(text) > MAX_CHARS:
        raise BadRequest(f"text is longer than {MAX_CHARS} characters")

    voice = payload.get("voice")
    if not isinstance(voice, str) or voice not in VOICES:
        raise BadRequest("unknown voice")

    lang = payload.get("lang")
    if lang != VOICES[voice]:
        raise BadRequest(f"voice {voice} speaks {VOICES[voice]}, not {lang!r}")

    speed = payload.get("speed", 1.0)
    if speed is None:
        speed = 1.0
    if isinstance(speed, bool) or not isinstance(speed, (int, float)):
        raise BadRequest("speed must be a number")
    speed = float(speed)
    if not (MIN_SPEED <= speed <= MAX_SPEED):  # also rejects NaN
        raise BadRequest(f"speed must be between {MIN_SPEED} and {MAX_SPEED}")

    return text, voice, lang, speed


class KokoroSynthesizer:
    """synthesize(text, voice, lang, speed) -> (float32 mono samples, sample rate)."""

    def __init__(self, models_dir):
        from kokoro_onnx import Kokoro

        self._kokoro = Kokoro(
            os.path.join(models_dir, MODEL_FILES[0]),
            os.path.join(models_dir, MODEL_FILES[1]),
        )

    def synthesize(self, text, voice, lang, speed):
        return self._kokoro.create(text, voice=voice, speed=speed, lang=KOKORO_LANG[lang])


def encode_mp3(samples, rate):
    """Float32 mono PCM -> MP3 (mono, 64 kbps) through ffmpeg."""
    pcm = samples.astype("<f4", copy=False).tobytes()
    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-f", "f32le", "-ar", str(rate), "-ac", "1", "-i", "pipe:0",
        "-ac", "1", "-b:a", "64k", "-f", "mp3", "pipe:1",
    ]
    done = subprocess.run(cmd, input=pcm, capture_output=True, check=False)
    if done.returncode != 0 or not done.stdout:
        raise RuntimeError("ffmpeg failed: " + done.stderr.decode("utf-8", "replace")[:200])
    return done.stdout


class Service:
    """One synthesis at a time: the model is not thread-safe and the host is small."""

    def __init__(self, synthesizer, encoder=encode_mp3):
        self.synthesizer = synthesizer
        self.encoder = encoder
        self.lock = threading.Lock()

    def render(self, text, voice, lang, speed):
        with self.lock:
            samples, rate = self.synthesizer.synthesize(text, voice, lang, speed)
            return self.encoder(samples, rate)


def make_handler(service):
    class Handler(BaseHTTPRequestHandler):
        server_version = "banco-tts"
        protocol_version = "HTTP/1.1"

        def log_message(self, *_args):  # replaced by the one-line request log below
            pass

        def _send(self, status, body, content_type):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            if self.close_connection:
                self.send_header("Connection", "close")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _json(self, status, payload):
            self._send(status, json.dumps(payload).encode("utf-8"), "application/json")

        def _error(self, status, message):
            self.close_connection = True  # the request body may be unread: do not reuse the socket
            self._json(status, {"error": message})

        def do_GET(self):
            if self.path == "/health":
                self._json(200, {"ok": True, "engine": ENGINE, "voices": list(VOICES)})
            else:
                self._error(404, "not found")

        def do_POST(self):
            if self.path != "/synthesize":
                return self._error(404, "not found")
            started = time.monotonic()
            try:
                text, voice, lang, speed = validate(self._read_json())
            except BadRequest as e:
                return self._error(400, str(e))

            try:
                audio = service.render(text, voice, lang, speed)
            except Exception as e:  # synthesis failure: log the class only, never the text
                self._log(voice, len(text), started, f"error={type(e).__name__}")
                return self._error(500, "synthesis failed")

            self._log(voice, len(text), started, f"bytes={len(audio)}")
            self._send(200, audio, "audio/mpeg")

        def _read_json(self):
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                raise BadRequest("Content-Length is required")
            if length < 0 or length > MAX_BODY_BYTES:
                raise BadRequest("body too large")
            raw = self.rfile.read(length)
            try:
                return json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                raise BadRequest("body is not valid JSON")

        def _log(self, voice, chars, started, extra):
            ms = int((time.monotonic() - started) * 1000)
            print(f"synthesize voice={voice} chars={chars} ms={ms} {extra}", flush=True)

    return Handler


def make_server(service, host="0.0.0.0", port=8000):
    server = ThreadingHTTPServer((host, port), make_handler(service))
    server.daemon_threads = True
    return server


def verify_models(models_dir, sums_path):
    """Refuses (raises SystemExit) unless every pinned file exists with the pinned SHA-256."""
    with open(sums_path, encoding="utf-8") as f:
        pinned = dict(
            (parts[1].lstrip("*"), parts[0])
            for parts in (line.split() for line in f if line.strip())
        )
    if set(pinned) != set(MODEL_FILES):
        raise SystemExit(f"{sums_path} must pin exactly {', '.join(MODEL_FILES)}")
    for name, want in pinned.items():
        path = os.path.join(models_dir, name)
        try:
            digest = hashlib.sha256()
            with open(path, "rb") as f:
                for block in iter(lambda: f.read(1 << 20), b""):
                    digest.update(block)
        except OSError as e:
            raise SystemExit(f"cannot read {path}: {e.strerror}")
        if digest.hexdigest() != want:
            raise SystemExit(f"{path}: SHA-256 mismatch, refusing to start")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    models_dir = os.environ.get("BANCO_TTS_MODELS", "/models")
    port = int(os.environ.get("BANCO_TTS_PORT", "8000"))

    verify_models(models_dir, os.path.join(here, "models.sha256"))
    service = Service(KokoroSynthesizer(models_dir))
    server = make_server(service, port=port)
    print(f"banco-tts {ENGINE} listening on :{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
