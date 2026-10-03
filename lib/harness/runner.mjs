// The harness runner (A-02). It runs inside the page Chrome loads from the harness
// listener, with a CSP that allows no connection. It imports the revision's
// generator.mjs and verify.mjs, stubs the sources of non-determinism so that a
// generator that touches them throws, and answers the server's calls:
//
//   bancoHarness.ready               a promise {ok, generator, verify, error?}
//   bancoHarness.generate(seeds, ms) results {seed, ok, json | error, ms, timeout?}
//   bancoHarness.verify(jobs)        results {id, ok, reason?, threw?}
//
// Parameters of the page address: ?generator=0 (do not load generator.mjs) and
// ?verify=1 (load verify.mjs). Nothing here reads a cookie, a token or storage.

import { makeRng } from "/lib/rng.mjs";

const realNow = performance.now.bind(performance);
const realStringify = JSON.stringify.bind(JSON);
const realKeys = Object.keys;

function unavailable(name) {
  return () => {
    throw new Error(name + " is not available in a generator");
  };
}

Math.random = unavailable("Math.random");
performance.now = unavailable("performance.now");
Object.defineProperty(globalThis, "crypto", { get: unavailable("crypto"), configurable: true });
globalThis.Date = Object.assign(function Date() {
  throw new Error("Date is not available in a generator");
}, { now: unavailable("Date.now") });

// JSON with sorted keys; undefined members are left out like in JSON.
function canon(value) {
  if (Array.isArray(value)) return "[" + value.map((v) => (v === undefined ? "null" : canon(v))).join(",") + "]";
  if (value && typeof value === "object") {
    const parts = [];
    for (const key of realKeys(value).sort()) {
      if (value[key] !== undefined) parts.push(realStringify(key) + ":" + canon(value[key]));
    }
    return "{" + parts.join(",") + "}";
  }
  const text = realStringify(value);
  return text === undefined ? "null" : text;
}

function message(error) {
  return String((error && error.message) || error).slice(0, 300);
}

const params = new URLSearchParams(location.search);
let generator = null;
let verifier = null;

const ready = (async () => {
  const state = { ok: true, generator: false, verify: false };
  if (params.get("generator") !== "0") {
    try {
      generator = await import("./generator.mjs");
      state.generator = typeof generator.generate === "function";
      if (!state.generator) {
        state.ok = false;
        state.error = "generator.mjs does not export generate(seed, rng)";
      }
    } catch (error) {
      state.ok = false;
      state.error = "generator.mjs did not load: " + message(error);
    }
  }
  if (params.get("verify") === "1") {
    try {
      verifier = await import("./verify.mjs");
      state.verify = typeof verifier.verify === "function";
      if (!state.verify) state.verify_error = "verify.mjs does not export verify(instance)";
    } catch (error) {
      state.verify_error = "verify.mjs did not load: " + message(error);
    }
  }
  return state;
})();

async function generate(seeds, limitMs) {
  const out = [];
  for (const seed of seeds) {
    const started = realNow();
    try {
      const result = generator.generate(seed, makeRng(seed));
      const ms = realNow() - started;
      const row = { seed, ok: true, json: canon(result), ms };
      if (ms > limitMs) row.timeout = true;
      out.push(row);
      if (row.timeout) break;
    } catch (error) {
      out.push({ seed, ok: false, error: message(error), ms: realNow() - started });
    }
  }
  return out;
}

async function verify(jobs) {
  const out = [];
  for (const job of jobs) {
    try {
      const result = await Promise.resolve(verifier.verify(job.instance));
      out.push({ id: job.id, ok: !!result && result.ok === true, reason: result && result.reason_it ? String(result.reason_it).slice(0, 200) : undefined });
    } catch (error) {
      out.push({ id: job.id, ok: false, threw: true, reason: message(error) });
    }
  }
  return out;
}

window.bancoHarness = { ready, generate, verify };
