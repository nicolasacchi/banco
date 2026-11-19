"""Run: python3 -m unittest services/tts/test_server.py   (no model, no network: fake synthesizer)."""
import hashlib
import http.client
import json
import os
import shutil
import tempfile
import threading
import unittest

import server

try:
    import numpy
except ImportError:  # the encoder test needs it; the service image always has it
    numpy = None


class FakeSynthesizer:
    def __init__(self):
        self.calls = []
        self.active = 0
        self.max_active = 0
        self.fail = False
        self._guard = threading.Lock()

    def synthesize(self, text, voice, lang, speed):
        with self._guard:
            self.active += 1
            self.max_active = max(self.max_active, self.active)
        try:
            self.calls.append((text, voice, lang, speed))
            if self.fail:
                raise RuntimeError("boom " + text)
            threading.Event().wait(0.02)
            return [0.0] * 10, 24000
        finally:
            with self._guard:
                self.active -= 1


def fake_encoder(samples, rate):
    return b"ID3-fake-mp3-" + str(rate).encode()


class ValidateTest(unittest.TestCase):
    def ok(self, **over):
        body = {"text": "Ciao a tutti", "voice": "im_nicola", "lang": "it", "speed": 1}
        body.update(over)
        return body

    def test_valid_request(self):
        self.assertEqual(
            server.validate(self.ok()), ("Ciao a tutti", "im_nicola", "it", 1.0)
        )

    def test_speed_defaults_to_one(self):
        body = self.ok()
        del body["speed"]
        self.assertEqual(server.validate(body)[3], 1.0)

    def test_each_voice_with_its_language(self):
        for voice, lang in {
            "im_nicola": "it", "af_heart": "en", "af_bella": "en",
            "ef_dora": "es", "em_alex": "es",
        }.items():
            self.assertEqual(server.validate(self.ok(voice=voice, lang=lang))[1:3], (voice, lang))

    def test_rejects(self):
        cases = {
            "unknown voice": self.ok(voice="af_sky"),
            "no voice": {k: v for k, v in self.ok().items() if k != "voice"},
            "voice/lang mismatch": self.ok(voice="im_nicola", lang="en"),
            "latin has no voice": self.ok(lang="la"),
            "no lang": self.ok(lang=None),
            "empty text": self.ok(text=""),
            "blank text": self.ok(text="  \n "),
            "text not a string": self.ok(text=12),
            "text too long": self.ok(text="a" * 1001),
            "speed too low": self.ok(speed=0.4),
            "speed too high": self.ok(speed=2.5),
            "speed string": self.ok(speed="1"),
            "speed bool": self.ok(speed=True),
            "speed NaN": self.ok(speed=float("nan")),
            "not an object": ["text"],
        }
        for name, body in cases.items():
            with self.subTest(name), self.assertRaises(server.BadRequest):
                server.validate(body)

    def test_text_limit_is_inclusive(self):
        server.validate(self.ok(text="a" * 1000))


class HttpTest(unittest.TestCase):
    def setUp(self):
        self.synth = FakeSynthesizer()
        self.httpd = server.make_server(
            server.Service(self.synth, fake_encoder), host="127.0.0.1", port=0
        )
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(5)

    def request(self, method, path, body=None, raw=None, headers=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            payload = raw if raw is not None else (json.dumps(body) if body is not None else None)
            conn.request(method, path, body=payload, headers=headers or {})
            res = conn.getresponse()
            return res.status, res.getheader("Content-Type"), res.read()
        finally:
            conn.close()

    def synth_request(self, **over):
        body = {"text": "Hello there", "voice": "af_heart", "lang": "en", "speed": 1.0}
        body.update(over)
        return self.request("POST", "/synthesize", body)

    def test_health(self):
        status, ctype, body = self.request("GET", "/health")
        self.assertEqual((status, ctype), (200, "application/json"))
        data = json.loads(body)
        self.assertIs(data["ok"], True)
        self.assertEqual(data["engine"], "kokoro-82m-v1.0")
        self.assertEqual(
            sorted(data["voices"]),
            ["af_bella", "af_heart", "ef_dora", "em_alex", "im_nicola"],
        )

    def test_synthesize_returns_audio_and_passes_arguments(self):
        status, ctype, body = self.synth_request(voice="ef_dora", lang="es", text="Hola", speed=0.9)
        self.assertEqual((status, ctype), (200, "audio/mpeg"))
        self.assertEqual(body, b"ID3-fake-mp3-24000")
        self.assertEqual(self.synth.calls, [("Hola", "ef_dora", "es", 0.9)])

    def test_bad_input_is_400_json_and_never_synthesizes(self):
        for over in ({"voice": "nope"}, {"lang": "it"}, {"text": ""}, {"text": "x" * 1001}, {"speed": 9}):
            with self.subTest(over):
                status, ctype, body = self.synth_request(**over)
                self.assertEqual((status, ctype), (400, "application/json"))
                self.assertIn("error", json.loads(body))
        self.assertEqual(self.synth.calls, [])

    def test_invalid_json_and_missing_length(self):
        status, _, body = self.request("POST", "/synthesize", raw="{not json")
        self.assertEqual(status, 400)
        self.assertIn("error", json.loads(body))

        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        conn.putrequest("POST", "/synthesize")
        conn.endheaders()
        self.assertEqual(conn.getresponse().status, 400)
        conn.close()

    def test_oversized_body_is_refused(self):
        status, _, _ = self.request("POST", "/synthesize", raw="x" * (server.MAX_BODY_BYTES + 1))
        self.assertEqual(status, 400)

    def test_unknown_paths(self):
        self.assertEqual(self.request("GET", "/nope")[0], 404)
        self.assertEqual(self.request("POST", "/health", body={})[0], 404)
        self.assertEqual(self.request("GET", "/synthesize")[0], 404)

    def test_synthesis_failure_is_500_without_the_text(self):
        self.synth.fail = True
        status, _, body = self.synth_request(text="secret words")
        self.assertEqual(status, 500)
        self.assertNotIn("secret", body.decode())

    def test_log_line_has_voice_chars_ms_and_never_the_text(self):
        import contextlib
        import io

        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.synth_request(text="Hello there")
        line = out.getvalue().strip()
        self.assertRegex(line, r"^synthesize voice=af_heart chars=11 ms=\d+ ")
        self.assertNotIn("Hello", line)

    def test_one_synthesis_at_a_time(self):
        threads = [threading.Thread(target=self.synth_request) for _ in range(6)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(10)
        self.assertEqual(len(self.synth.calls), 6)
        self.assertEqual(self.synth.max_active, 1)


class VerifyModelsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.files = {"kokoro-v1.0.onnx": b"model", "voices-v1.0.bin": b"voices"}
        for name, data in self.files.items():
            with open(os.path.join(self.dir, name), "wb") as f:
                f.write(data)
        self.sums = os.path.join(self.dir, "models.sha256")
        self.write_sums(self.files)

    def write_sums(self, files):
        with open(self.sums, "w") as f:
            for name, data in files.items():
                f.write(f"{hashlib.sha256(data).hexdigest()}  {name}\n")

    def test_accepts_matching_files(self):
        server.verify_models(self.dir, self.sums)

    def test_refuses_mismatch(self):
        with open(os.path.join(self.dir, "voices-v1.0.bin"), "wb") as f:
            f.write(b"tampered")
        with self.assertRaises(SystemExit) as ctx:
            server.verify_models(self.dir, self.sums)
        self.assertIn("mismatch", str(ctx.exception))

    def test_refuses_missing_file(self):
        os.remove(os.path.join(self.dir, "kokoro-v1.0.onnx"))
        with self.assertRaises(SystemExit):
            server.verify_models(self.dir, self.sums)

    def test_refuses_incomplete_pin_file(self):
        self.write_sums({"kokoro-v1.0.onnx": b"model"})
        with self.assertRaises(SystemExit):
            server.verify_models(self.dir, self.sums)

    def test_repo_pins_are_well_formed(self):
        here = os.path.dirname(os.path.abspath(__file__))
        with open(os.path.join(here, "models.sha256")) as f:
            rows = [line.split() for line in f if line.strip()]
        self.assertEqual(sorted(r[1] for r in rows), sorted(server.MODEL_FILES))
        for digest, _ in rows:
            self.assertRegex(digest, r"^[0-9a-f]{64}$")


@unittest.skipUnless(numpy and shutil.which("ffmpeg"), "needs numpy and ffmpeg")
class EncodeMp3Test(unittest.TestCase):
    def test_produces_mono_mp3(self):
        tone = numpy.sin(numpy.linspace(0, 440 * 2 * numpy.pi, 24000)).astype("float32")
        mp3 = server.encode_mp3(tone, 24000)
        self.assertTrue(mp3.startswith(b"ID3") or mp3[0] == 0xFF)
        self.assertGreater(len(mp3), 1000)


class SplitTextTest(unittest.TestCase):
    def test_a_short_text_is_one_chunk(self):
        self.assertEqual(server.split_text("Ciao a tutti"), ["Ciao a tutti"])

    def test_sentences_become_chunks_in_order(self):
        self.assertEqual(
            server.split_text("Il gatto dorme sul divano. Il cane corre nel giardino! Chi arriva per primo alla porta?"),
            ["Il gatto dorme sul divano.", "Il cane corre nel giardino!", "Chi arriva per primo alla porta?"],
        )

    def test_a_newline_ends_a_sentence(self):
        self.assertEqual(
            server.split_text("Il primo punto della lista\nIl secondo punto della lista"),
            ["Il primo punto della lista", "Il secondo punto della lista"],
        )

    def test_a_tiny_sentence_joins_its_neighbour(self):
        self.assertEqual(server.split_text("Sì. Va bene così."), ["Sì. Va bene così."])
        self.assertEqual(
            server.split_text("1. Leggi la prima frase con calma e senza fretta."),
            ["1. Leggi la prima frase con calma e senza fretta."],
        )

    def test_an_abbreviation_or_a_decimal_does_not_end_a_sentence(self):
        text = "Guarda es. aperto nel libro di testo, costa 3,5 euro."
        self.assertEqual(server.split_text(text), [text])

    def test_a_closing_quote_stays_with_its_sentence(self):
        self.assertEqual(
            server.split_text('He said "you should go home now." Then he left the room quietly.'),
            ['He said "you should go home now."', "Then he left the room quietly."],
        )

    def test_spanish_inverted_marks_open_a_sentence(self):
        self.assertEqual(
            server.split_text("Hoy hace mucho calor aquí. ¿Quieres beber un poco de agua fría?"),
            ["Hoy hace mucho calor aquí.", "¿Quieres beber un poco de agua fría?"],
        )

    def test_a_long_sentence_breaks_at_clauses_then_at_spaces(self):
        clause = "il ragazzo legge con attenzione il testo che ha davanti"
        text = ", ".join([clause] * 8) + "."
        chunks = server.split_text(text)
        self.assertGreater(len(chunks), 1)
        self.assertTrue(all(len(c) <= server.MAX_CHUNK_CHARS for c in chunks))
        self.assertTrue(all(c.endswith(",") or c.endswith(".") for c in chunks), chunks)
        spaces = server.split_text(" ".join(["parola"] * 200))
        self.assertTrue(all(len(c) <= server.MAX_CHUNK_CHARS for c in spaces))

    def test_a_word_longer_than_the_limit_is_cut(self):
        chunks = server.split_text("a" * 450)
        self.assertEqual([len(c) for c in chunks], [200, 200, 50])

    def test_no_word_is_lost_and_none_is_longer_than_the_limit(self):
        samples = [
            "Il Risorgimento. " * 60,
            ("Nel 1861 nasce il Regno d'Italia; Torino è la prima capitale, poi Firenze, infine Roma. " * 20)[:1000],
            "Hola, ¿cómo estás? Muy bien, gracias.\n\nY tú: ¿qué tal?" * 15,
            "x " * 500,
            "a" * 1000,
        ]
        for text in samples:
            with self.subTest(text[:30]):
                chunks = server.split_text(text)
                self.assertTrue(chunks)
                self.assertTrue(all(c and c == c.strip() and len(c) <= server.MAX_CHUNK_CHARS for c in chunks))
                if " " in text.strip():
                    self.assertEqual(" ".join(chunks).split(), text.split())
                else:
                    self.assertEqual("".join(chunks), text)


class RenderInSentencesTest(unittest.TestCase):
    def setUp(self):
        self.synth = FakeSynthesizer()
        self.joined = []

        def joiner(parts, rate):
            self.joined.append((len(parts), rate))
            return "joined"

        self.encoded = []

        def encoder(samples, rate):
            self.encoded.append((samples, rate))
            return b"mp3"

        self.service = server.Service(self.synth, encoder, joiner)

    def test_each_sentence_is_synthesized_on_its_own_with_the_same_voice_and_speed(self):
        out = self.service.render("Il gatto dorme sul divano. Il cane corre nel giardino.", "im_nicola", "it", 0.9)
        self.assertEqual(out, b"mp3")
        self.assertEqual(
            self.synth.calls,
            [
                ("Il gatto dorme sul divano.", "im_nicola", "it", 0.9),
                ("Il cane corre nel giardino.", "im_nicola", "it", 0.9),
            ],
        )
        self.assertEqual(self.joined, [(2, 24000)])
        self.assertEqual(self.encoded, [("joined", 24000)])

    def test_no_synthesis_is_longer_than_a_sentence_chunk(self):
        text = " ".join(f"Frase numero {i} del testo molto lungo che la voce deve leggere." for i in range(15))[: server.MAX_CHARS]
        self.service.render(text, "im_nicola", "it", 1.0)
        self.assertGreater(len(self.synth.calls), 5)
        self.assertTrue(all(len(call[0]) <= server.MAX_CHUNK_CHARS for call in self.synth.calls))


@unittest.skipUnless(numpy, "needs numpy")
class JoinAudioTest(unittest.TestCase):
    def test_one_part_is_returned_as_it_is(self):
        part = numpy.ones(10, dtype="float32")
        self.assertIs(server.join_audio([part], 24000), part)

    def test_parts_are_joined_with_a_silence_between_them(self):
        a, b, c = (numpy.ones(100, dtype="float32") * n for n in (1, 2, 3))
        joined = server.join_audio([a, b, c], 24000, pause=0.01)
        gap = int(24000 * 0.01)
        self.assertEqual(len(joined), 300 + 2 * gap)
        self.assertEqual(joined.dtype, numpy.float32)
        self.assertTrue((joined[100 : 100 + gap] == 0).all())
        self.assertEqual(joined[-1], 3.0)


class SessionOptionsTest(unittest.TestCase):
    def test_the_cpu_arena_and_the_memory_pattern_are_off(self):
        import types

        ort = types.SimpleNamespace(SessionOptions=lambda: types.SimpleNamespace(enable_cpu_mem_arena=True, enable_mem_pattern=True))
        options = server.session_options(ort)
        self.assertIs(options.enable_cpu_mem_arena, False)
        self.assertIs(options.enable_mem_pattern, False)


class FakeWorker:
    def __init__(self, rss=100.0, die_on=None):
        self.rss = rss
        self.die_on = die_on  # the number of the run that finds the worker dead
        self.runs = 0
        self.closed = False
        self.refuse = False

    def run(self, text, voice, lang, speed):
        self.runs += 1
        if self.die_on == self.runs:
            raise server.WorkerDied("gone")
        if self.refuse:
            raise RuntimeError("refused")
        return [0.0], 24000, self.rss

    def close(self):
        self.closed = True


class RecyclingSynthesizerTest(unittest.TestCase):
    def make(self, **kwargs):
        self.workers = []
        self.spec = kwargs.pop("spec", {})

        def start_worker():
            worker = FakeWorker(**self.spec.get(len(self.workers), {}))
            self.workers.append(worker)
            return worker

        return server.RecyclingSynthesizer(start_worker, warm=False, **kwargs)

    def run_n(self, synth, n):
        for _ in range(n):
            self.assertEqual(synth.synthesize("Ciao a tutti", "im_nicola", "it", 1.0), ([0.0], 24000))

    def test_the_worker_is_replaced_after_n_syntheses(self):
        synth = self.make(recycle_after=3, recycle_rss_mb=1000)
        self.run_n(synth, 7)
        self.assertEqual([w.runs for w in self.workers], [3, 3, 1])
        self.assertEqual([w.closed for w in self.workers], [True, True, False])
        self.assertEqual(synth.stats()["recycled"], 2)
        self.assertEqual(synth.stats()["runs"], 1)

    def test_the_worker_is_replaced_when_it_grows_past_the_limit(self):
        synth = self.make(recycle_after=100, recycle_rss_mb=1500, spec={0: {"rss": 1600.0}})
        self.run_n(synth, 3)
        self.assertEqual([w.runs for w in self.workers], [1, 2])
        self.assertTrue(self.workers[0].closed)

    def test_a_dead_worker_is_replaced_and_the_sentence_is_tried_again(self):
        synth = self.make(spec={0: {"die_on": 2}})
        self.run_n(synth, 3)
        self.assertEqual(len(self.workers), 2)
        self.assertTrue(self.workers[0].closed)
        self.assertEqual(self.workers[1].runs, 2)

    def test_a_worker_that_dies_twice_is_an_error(self):
        synth = self.make(spec={0: {"die_on": 1}, 1: {"die_on": 1}})
        with self.assertRaises(RuntimeError):
            synth.synthesize("Ciao a tutti", "im_nicola", "it", 1.0)

    def test_a_text_the_model_refuses_is_an_error_and_keeps_the_worker(self):
        synth = self.make()
        self.run_n(synth, 1)
        self.workers[0].refuse = True
        with self.assertRaises(RuntimeError):
            synth.synthesize("Ciao a tutti", "im_nicola", "it", 1.0)
        self.assertEqual(len(self.workers), 1)
        self.assertFalse(self.workers[0].closed)

    def test_the_next_worker_is_loaded_in_the_background_after_a_recycle(self):
        started = threading.Event()
        workers = []

        def start_worker():
            workers.append(FakeWorker())
            if len(workers) == 2:
                started.set()
            return workers[-1]

        synth = server.RecyclingSynthesizer(start_worker, recycle_after=1, recycle_rss_mb=1000)
        synth.synthesize("Ciao a tutti", "im_nicola", "it", 1.0)
        self.assertTrue(started.wait(5), "no replacement was loaded after the recycle")
        synth.close()

    def test_close_closes_the_worker(self):
        synth = self.make()
        self.run_n(synth, 1)
        synth.close()
        self.assertTrue(self.workers[0].closed)


class WorkerLoopTest(unittest.TestCase):
    def start(self, synthesizer):
        import multiprocessing

        parent, child = multiprocessing.Pipe()
        thread = threading.Thread(target=server.worker_loop, args=(child, synthesizer, lambda: 321.5), daemon=True)
        thread.start()
        self.addCleanup(thread.join, 5)
        self.addCleanup(parent.close)
        return parent, thread

    def test_answers_each_request_and_stops_on_none(self):
        synth = FakeSynthesizer()
        parent, thread = self.start(synth)
        parent.send(("Ciao a tutti", "im_nicola", "it", 1.0))
        self.assertEqual(parent.recv(), ("ok", [0.0] * 10, 24000, 321.5))
        parent.send(None)
        thread.join(5)
        self.assertFalse(thread.is_alive())
        self.assertEqual(synth.calls, [("Ciao a tutti", "im_nicola", "it", 1.0)])

    def test_a_failure_is_answered_with_the_class_only_and_the_loop_goes_on(self):
        synth = FakeSynthesizer()
        synth.fail = True
        parent, _ = self.start(synth)
        parent.send(("secret words", "im_nicola", "it", 1.0))
        self.assertEqual(parent.recv(), ("error", "RuntimeError", 321.5))
        synth.fail = False
        parent.send(("Ciao a tutti", "im_nicola", "it", 1.0))
        self.assertEqual(parent.recv()[0], "ok")
        parent.send(None)

    def test_process_rss_is_a_positive_number_of_mib(self):
        self.assertGreater(server.process_rss_mb(), 1)


if __name__ == "__main__":
    unittest.main()
