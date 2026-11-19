"""banco TTS service: lesson text in, MP3 out, Kokoro-82M on CPU.

POST /synthesize  {"text", "voice", "lang", "speed"} -> 200 audio/mpeg | 400 JSON
GET  /health      -> {"ok", "engine", "voices", "worker": {"runs", "rss_mb", "recycled"}}

The service only ever sees lesson text sent by the Rails app's clip generator; it keeps no state
and logs one line per request (voice, chars, ms), never the text.

Memory (D-369): onnxruntime's memory only grows with the longest input it has seen, so (1) the session runs without the CPU memory
arena and the memory pattern, (2) a text is synthesized one sentence at a time, (3) the process that holds the model is a worker
that is replaced after BANCO_TTS_RECYCLE_AFTER sentences or at BANCO_TTS_RECYCLE_RSS_MB MiB resident. The clip's audio is the only
thing that changes; the Rails side (clip keys, segment texts) never sees any of it.
"""
import hashlib
import json
import multiprocessing
import os
import re
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ENGINE = "kokoro-82m-v1.0"
MAX_CHARS = 1000
MAX_BODY_BYTES = 16 * 1024
MIN_SPEED, MAX_SPEED = 0.5, 2.0

# Sentences are synthesized one by one (D-369): a chunk is at most this long, and a shorter one is joined to its neighbour.
MAX_CHUNK_CHARS = 200
MIN_CHUNK_CHARS = 24
PAUSE_SECONDS = 0.15  # silence between two sentences of one clip
# The worker process that holds the model is replaced after this many sentences, or when its resident set reaches this many MiB.
RECYCLE_AFTER = 100
RECYCLE_RSS_MB = 1500
READY_TIMEOUT_SECONDS = 120  # loading the model
CHUNK_TIMEOUT_SECONDS = 120  # one sentence

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


# --- Text in sentences -------------------------------------------------------------------------------------------------------------

# A sentence ends at ., ! ? or … (and the closing quote or bracket after it) when what follows, after spaces, opens with a capital, a digit,
# an inverted mark or an opening quote: «es. aperto» and «3,5 euro» stay in one piece.
_SENTENCE_BREAK = re.compile(
    r"""(?:(?<=[.!?…])|(?<=[.!?…][»”’"')\]]))\s+(?=[«“‘"'(\[]?[A-ZÀ-ÖØ-Þ0-9¿¡])"""
)
_CLAUSE_BREAK = re.compile(r"(?<=[,;:—–])\s+")


def _wrap_words(piece, limit):
    """Greedy lines of whole words, each at most `limit` long (a word longer than that is cut)."""
    lines, current = [], ""
    for word in piece.split():
        while len(word) > limit:
            if current:
                lines.append(current)
                current = ""
            lines.append(word[:limit])
            word = word[limit:]
        if current and len(current) + 1 + len(word) > limit:
            lines.append(current)
            current = word
        else:
            current = f"{current} {word}" if current else word
    if current:
        lines.append(current)
    return lines


def _fit(sentence, limit):
    """A sentence as pieces of at most `limit` characters, broken at clause marks first, at spaces last."""
    if len(sentence) <= limit:
        return [sentence]
    pieces, current = [], ""
    for clause in _CLAUSE_BREAK.split(sentence):
        if len(clause) > limit:
            if current:
                pieces.append(current)
                current = ""
            pieces.extend(_wrap_words(clause, limit))
        elif current and len(current) + 1 + len(clause) > limit:
            pieces.append(current)
            current = clause
        else:
            current = f"{current} {clause}" if current else clause
    if current:
        pieces.append(current)
    return pieces


def split_text(text, limit=MAX_CHUNK_CHARS, minimum=MIN_CHUNK_CHARS):
    """The text as the chunks to synthesize one by one: sentences, never longer than `limit` characters; a chunk shorter than `minimum`
    joins its neighbour when they fit together («1.» with its sentence, «Sì.» with the next). The words, in order, are all kept."""
    chunks = []
    for line in text.split("\n"):
        for sentence in _SENTENCE_BREAK.split(line.strip()):
            for piece in _fit(sentence.strip(), limit):
                if piece:
                    chunks.append(piece)
    merged = []
    for chunk in chunks:
        if merged and (len(merged[-1]) < minimum or len(chunk) < minimum) and len(merged[-1]) + 1 + len(chunk) <= limit:
            merged[-1] = f"{merged[-1]} {chunk}"
        else:
            merged.append(chunk)
    return merged


def join_audio(parts, rate, pause=PAUSE_SECONDS):
    """The sentences' audio as one float32 array, with a short silence between them."""
    if len(parts) == 1:
        return parts[0]
    import numpy

    gap = numpy.zeros(int(rate * pause), dtype="float32")
    joined = []
    for i, part in enumerate(parts):
        if i:
            joined.append(gap)
        joined.append(part)
    return numpy.concatenate(joined)


# --- The model ---------------------------------------------------------------------------------------------------------------------


def session_options(ort):
    """onnxruntime session options for a model whose input length changes with every sentence: the CPU memory arena and the memory
    pattern cache both keep what an earlier, longer input needed, which is how the service reached 6 GB (D-369)."""
    options = ort.SessionOptions()
    options.enable_cpu_mem_arena = False
    options.enable_mem_pattern = False
    return options


class KokoroSynthesizer:
    """synthesize(text, voice, lang, speed) -> (float32 mono samples, sample rate), for one sentence. Runs in the worker process."""

    def __init__(self, models_dir):
        import onnxruntime
        from kokoro_onnx import Kokoro

        session = onnxruntime.InferenceSession(
            os.path.join(models_dir, MODEL_FILES[0]),
            sess_options=session_options(onnxruntime),
            providers=["CPUExecutionProvider"],
        )
        self._kokoro = Kokoro.from_session(session, os.path.join(models_dir, MODEL_FILES[1]))

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
    """One synthesis at a time: the model is not thread-safe and the host is small.

    A text is split into sentences (split_text), each sentence is synthesized on its own and the audio is joined: the
    onnxruntime memory grows with the longest input it ever saw, so no input is ever longer than one sentence."""

    def __init__(self, synthesizer, encoder=encode_mp3, joiner=join_audio):
        self.synthesizer = synthesizer
        self.encoder = encoder
        self.joiner = joiner
        self.lock = threading.Lock()

    def render(self, text, voice, lang, speed):
        chunks = split_text(text)
        with self.lock:
            parts, rate = [], None
            for chunk in chunks:
                samples, rate = self.synthesizer.synthesize(chunk, voice, lang, speed)
                parts.append(samples)
            return self.encoder(self.joiner(parts, rate), rate)

    def stats(self):
        """What /health adds about the worker (empty when the synthesizer keeps no worker)."""
        stats = getattr(self.synthesizer, "stats", None)
        return {"worker": stats()} if stats else {}

    def close(self):
        close = getattr(self.synthesizer, "close", None)
        if close:
            close()


class WorkerDied(Exception):
    """The worker process is gone (killed by the OOM killer, crashed) or did not answer in time."""


def process_rss_mb():
    """Resident set of this process now, in MiB (from /proc; the peak from getrusage where /proc is missing)."""
    try:
        with open("/proc/self/statm", encoding="ascii") as f:
            return int(f.read().split()[1]) * os.sysconf("SC_PAGE_SIZE") / (1024 * 1024)
    except (OSError, ValueError, IndexError):
        import resource

        return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024


def worker_loop(conn, synthesizer, rss=process_rss_mb):
    """The worker's side of the pipe: a request is (text, voice, lang, speed), the answer ("ok", samples, rate, rss_mb) or
    ("error", exception class name, rss_mb), never the text. None (or a closed pipe) ends the loop."""
    while True:
        try:
            request = conn.recv()
        except EOFError:
            return
        if request is None:
            return
        try:
            samples, rate = synthesizer.synthesize(*request)
            conn.send(("ok", samples, rate, rss()))
        except Exception as e:
            conn.send(("error", type(e).__name__, rss()))


def _child_main(conn, models_dir):
    synthesizer = KokoroSynthesizer(models_dir)
    conn.send(("ready",))
    worker_loop(conn, synthesizer)


class ProcessWorker:
    """One child process that holds the model. A spawned process, not a fork: the parent never loads onnxruntime."""

    def __init__(self, models_dir, ready_timeout=READY_TIMEOUT_SECONDS, call_timeout=CHUNK_TIMEOUT_SECONDS):
        self.call_timeout = call_timeout
        ctx = multiprocessing.get_context("spawn")
        self._conn, child_conn = ctx.Pipe()
        self._proc = ctx.Process(target=_child_main, args=(child_conn, models_dir), daemon=True)
        self._proc.start()
        child_conn.close()
        try:
            if self._receive(ready_timeout) != ("ready",):
                raise WorkerDied("unexpected first message")
        except BaseException:
            self.close()
            raise

    def run(self, text, voice, lang, speed):
        """-> (samples, rate, rss_mb). Raises WorkerDied, or RuntimeError when the model refused this text."""
        try:
            self._conn.send((text, voice, lang, speed))
        except (OSError, ValueError) as e:
            raise WorkerDied(type(e).__name__)
        answer = self._receive(self.call_timeout)
        if answer[0] == "ok":
            return answer[1], answer[2], answer[3]
        raise RuntimeError(f"synthesis failed in the worker: {answer[1]}")

    def _receive(self, timeout):
        try:
            if not self._conn.poll(timeout):
                raise WorkerDied("no answer in %s s" % timeout)
            return self._conn.recv()
        except (EOFError, OSError) as e:
            raise WorkerDied(type(e).__name__)

    def close(self):
        try:
            self._conn.send(None)
        except (OSError, ValueError):
            pass
        self._proc.join(3)
        if self._proc.is_alive():
            self._proc.kill()
            self._proc.join(3)
        self._conn.close()


class RecyclingSynthesizer:
    """synthesize(text, voice, lang, speed) through a worker that is replaced before it grows (onnxruntime's memory only goes up).

    The worker is retired after `recycle_after` syntheses or as soon as its resident set reaches `recycle_rss_mb`, and the next one is
    loaded in the background, so a request almost never waits for a model load. A worker that died (killed, crashed, no answer) is replaced
    and the sentence is tried once more on the new one. `start_worker()` returns an object with run() and close() (ProcessWorker)."""

    def __init__(self, start_worker, recycle_after=RECYCLE_AFTER, recycle_rss_mb=RECYCLE_RSS_MB, warm=True):
        self._start_worker = start_worker
        self.recycle_after = recycle_after
        self.recycle_rss_mb = recycle_rss_mb
        self._warm = warm
        self._worker = None
        self._lock = threading.Lock()
        self.runs = 0
        self.rss_mb = 0.0
        self.recycled = 0

    def start(self):
        self._current()

    def synthesize(self, text, voice, lang, speed):
        for attempt in (1, 2):
            worker = self._current()
            try:
                samples, rate, rss = worker.run(text, voice, lang, speed)
            except WorkerDied as e:
                print(f"worker lost ({e}), starting another", flush=True)
                self._retire("died")
                if attempt == 2:
                    raise RuntimeError("the worker died twice")
                continue
            self.runs += 1
            self.rss_mb = round(rss, 1)
            if self.runs >= self.recycle_after:
                self._retire("runs")
            elif rss >= self.recycle_rss_mb:
                self._retire("rss")
            return samples, rate

    def stats(self):
        return {"runs": self.runs, "rss_mb": self.rss_mb, "recycled": self.recycled}

    def close(self):
        with self._lock:
            worker, self._worker = self._worker, None
        if worker:
            worker.close()

    def _current(self):
        with self._lock:
            if self._worker is None:
                self._worker = self._start_worker()
            return self._worker

    def _retire(self, reason):
        with self._lock:
            worker, self._worker = self._worker, None
            self.runs = 0
            self.recycled += 1
        if worker:
            worker.close()
        print(f"worker retired reason={reason} rss_mb={self.rss_mb}", flush=True)
        if self._warm:
            threading.Thread(target=self._warm_up, daemon=True).start()

    def _warm_up(self):
        try:
            self._current()
        except Exception as e:  # the next request starts one (and says why when that fails too)
            print(f"worker warm-up failed: {type(e).__name__}", flush=True)


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
                self._json(200, {"ok": True, "engine": ENGINE, "voices": list(VOICES), **service.stats()})
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
    synthesizer = RecyclingSynthesizer(
        lambda: ProcessWorker(models_dir),
        recycle_after=int(os.environ.get("BANCO_TTS_RECYCLE_AFTER", RECYCLE_AFTER)),
        recycle_rss_mb=int(os.environ.get("BANCO_TTS_RECYCLE_RSS_MB", RECYCLE_RSS_MB)),
    )
    synthesizer.start()  # the model is loaded before the first request and before /health answers
    service = Service(synthesizer)
    server = make_server(service, port=port)
    print(f"banco-tts {ENGINE} listening on :{port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        service.close()


if __name__ == "__main__":
    sys.exit(main())
