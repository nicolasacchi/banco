// The worker protocol: JSON lines, ready line first, ids echoed, errors as data.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { CHECKER_VERSION } from '../checker.mjs';

const worker = fileURLToPath(new URL('../worker.mjs', import.meta.url));

function start() {
  const child = spawn(process.execPath, [worker], { stdio: ['pipe', 'pipe', 'inherit'] });
  const queue = [];
  const waiters = [];
  createInterface({ input: child.stdout }).on('line', (l) => {
    const msg = JSON.parse(l);
    const w = waiters.shift();
    if (w) w(msg); else queue.push(msg);
  });
  const next = () => new Promise((res) => { const m = queue.shift(); if (m) res(m); else waiters.push(res); });
  const call = (req) => { child.stdin.write(JSON.stringify(req) + '\n'); return next(); };
  return { child, next, call };
}

test('worker announces readiness, answers checks and survives bad input', async () => {
  const w = start();
  const ready = await w.next();
  assert.deepEqual(ready, { ready: true, checker_version: CHECKER_VERSION, ce_version: '0.146.0' });

  const item = { expected: '2\\sqrt{2}', form: ['radical_simplified'], errors: [] };
  const wrong = await w.call({ id: 7, op: 'check', item, answer: '\\sqrt{8}', source: 'mathlive' });
  assert.equal(wrong.id, 7);
  assert.equal(wrong.ok, true);
  assert.equal(wrong.result.verdict, 'wrong_form');
  assert.deepEqual(wrong.result.form_violations, ['radicand_not_reduced']);
  const right = await w.call({ id: 8, op: 'check', item, answer: '2\\sqrt{2}' });
  assert.equal(right.result.verdict, 'correct');

  w.child.stdin.write('not json\n');
  assert.deepEqual(await w.next(), { id: null, ok: false, error: 'bad_json' });
  const unknown = await w.call({ id: 9, op: 'nope' });
  assert.equal(unknown.ok, false);
  const again = await w.call({ id: 10, op: 'ping' });
  assert.equal(again.ok, true);

  w.child.stdin.end();
  await new Promise((res) => w.child.on('exit', res));
});
