// The server voices of "Ascolta" (D-359): clips generated ahead of time from the text of a lesson, stored under the SHA-256 of what they say and
// served as MP3. The browser only plays them, and only when the student presses a speaker (nothing is fetched before; no autoplay, no prefetch).
// This file is the pure part: which voice a segment has, the key and the URL of its clip. The player is lesson/speech.js.
//
// Key of a clip: lowercase hex SHA-256 of the UTF-8 string "<engine>|<voice name>|<text>" (the same in Ruby: test/fixtures/speech/keys.json holds the
// shared vectors). The hash is computed here, in plain JS, because it must be ready inside the tap: Safari lets a sound start only from the tap
// itself, and SubtleCrypto answers one turn later.
import voices from "lesson/voices"

// The server voices of voices.yml (`server:`), or null where the build has none.
export const serverConfig = () => voices.server ?? null

// serverVoice(lang, voice, config) -> the voice name of the n-th speaker (1 when none), or null when the language has no server voice.
//   Two voices a language are used in turn: speaker 1 the first, speaker 2 the second, speaker 3 the first again.
export function serverVoice(lang, voice = 1, config = serverConfig()) {
  const list = config?.voices?.[lang]
  if (!Array.isArray(list) || list.length === 0) return null
  const n = Number.isInteger(voice) && voice >= 1 ? voice : 1
  return list[(n - 1) % list.length]
}

const PRIMES = []
for (let n = 2; PRIMES.length < 64; n += 1) if (PRIMES.every((p) => n % p !== 0)) PRIMES.push(n)
const fraction = (x) => Math.floor((x - Math.floor(x)) * 2 ** 32)
const K = Uint32Array.from(PRIMES, (p) => fraction(Math.cbrt(p)))
const H0 = Uint32Array.from(PRIMES.slice(0, 8), (p) => fraction(Math.sqrt(p)))
const rotr = (x, n) => (x >>> n) | (x << (32 - n))

// sha256Hex(text) -> 64 lowercase hex digits of the SHA-256 of the UTF-8 bytes of +text+.
export function sha256Hex(text) {
  const data = new TextEncoder().encode(text)
  const total = (data.length + 9 + 63) & ~63
  const bytes = new Uint8Array(total)
  bytes.set(data)
  bytes[data.length] = 0x80
  const view = new DataView(bytes.buffer)
  view.setUint32(total - 8, Math.floor((data.length * 8) / 2 ** 32))
  view.setUint32(total - 4, (data.length * 8) >>> 0)
  const h = Uint32Array.from(H0)
  const w = new Uint32Array(64)
  for (let offset = 0; offset < total; offset += 64) {
    for (let i = 0; i < 16; i += 1) w[i] = view.getUint32(offset + 4 * i)
    for (let i = 16; i < 64; i += 1) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)
      w[i] = w[i - 16] + s0 + w[i - 7] + s1
    }
    let [a, b, c, d, e, f, g, hh] = h
    for (let i = 0; i < 64; i += 1) {
      const t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) | 0
      const t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0
      hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0
    }
    ;[a, b, c, d, e, f, g, hh].forEach((x, i) => { h[i] += x })
  }
  return Array.from(h, (x) => x.toString(16).padStart(8, "0")).join("")
}

// clipKey(engine, voiceName, text) -> the key of the clip of +text+ said by +voiceName+.
export const clipKey = (engine, voiceName, text) => sha256Hex(`${engine}|${voiceName}|${text}`)

// clipFor(segment, config) -> { voice, key, url } for a segment { lang, text, voice }, or null when its language has no server voice.
//   The text is exactly what the lesson says: it is not trimmed or changed here.
export function clipFor(segment, config = serverConfig()) {
  const voice = serverVoice(segment.lang, segment.voice ?? 1, config)
  if (!voice) return null
  const key = clipKey(config.engine, voice, segment.text)
  return { voice, key, url: `${config.clip_path}/${key}.${config.format ?? "mp3"}` }
}
