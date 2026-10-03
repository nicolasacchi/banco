// Expression grader worker (A-01). One long-lived Node process per Rails process;
// Grading::Expression talks to it in JSON lines over stdin/stdout.
//
//   request  {"id": 1, "op": "check", "item": {...spec}, "answer": "...", "source": "mathlive"}
//            {"id": 2, "op": "compile", "item": {...spec}}
//            {"id": 3, "op": "ping"}
//   response {"id": 1, "ok": true, "result": {...}} or {"id": 1, "ok": false, "error": "..."}
//   first line, once the engine is loaded: {"ready": true, "checker_version": "...", "ce_version": "..."}
//
// Nothing in a request is ever evaluated as code: the checker parses LaTeX and
// walks a tree (firm rule 3).

import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { ComputeEngine, version as CE_VERSION } from './vendor/compute-engine/compute-engine.js';
import { createChecker, CHECKER_VERSION } from './checker.mjs';

const checker = createChecker({ ComputeEngine });
const compiled = new Map();
const CACHE_MAX = 500;

function specKey(spec) {
  return JSON.stringify([spec.expected, spec.form || [], spec.errors || [], spec.unknown || null, spec.domain || {}, spec.mode || 'exact']);
}

function compile(spec) {
  const key = specKey(spec);
  let item = compiled.get(key);
  if (!item) {
    item = checker.compile(spec);
    if (compiled.size >= CACHE_MAX) compiled.delete(compiled.keys().next().value);
    compiled.set(key, item);
  }
  return item;
}

export function handle(req) {
  switch (req.op) {
    case 'ping':
      return { checker_version: CHECKER_VERSION, ce_version: CE_VERSION };
    case 'compile': {
      const item = compile(req.item);
      return { problems: item.problems };
    }
    case 'check': {
      const item = compile(req.item);
      const result = item.check(String(req.answer ?? ''), { source: req.source || 'mathlive' });
      return { ...result, problems: item.problems, checker_version: CHECKER_VERSION, ce_version: CE_VERSION };
    }
    default:
      throw new Error(`unknown op ${req.op}`);
  }
}

const out = (obj) => process.stdout.write(JSON.stringify(obj, (k, v) => (typeof v === 'bigint' ? String(v) : v)) + '\n');

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
  rl.on('line', (line) => {
    if (!line.trim()) return;
    let req;
    try { req = JSON.parse(line); } catch { out({ id: null, ok: false, error: 'bad_json' }); return; }
    try { out({ id: req.id, ok: true, result: handle(req) }); }
    catch (e) { out({ id: req.id, ok: false, error: String((e && e.message) || e).slice(0, 200) }); }
  });
  rl.on('close', () => process.exit(0)); // the parent went away
  out({ ready: true, checker_version: CHECKER_VERSION, ce_version: CE_VERSION });
}
