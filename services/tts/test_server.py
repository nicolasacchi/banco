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


if __name__ == "__main__":
    unittest.main()
